#include "fileindex.h"

#include <QByteArrayView>
#include <QDateTime>
#include <QFile>
#include <QMutexLocker>
#include <QThread>
#include <QThreadPool>

#include <algorithm>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <string>
#include <sys/stat.h>
#include <utility>

namespace
{
constexpr std::size_t MaxEntries = 400000;
constexpr int MaxDepth = 16;

bool skipped(const char *name)
{
    if (name[0] == '.') {
        return true;
    }
    static const char *const names[] = {"node_modules", "__pycache__", "lost+found"};
    for (const char *n : names) {
        if (std::strcmp(name, n) == 0) {
            return true;
        }
    }
    return false;
}

bool separator(char c)
{
    return c == ' ' || c == '-' || c == '_' || c == '.' || c == '(' || c == '[';
}
}

FileIndex::FileIndex(const QString &root)
    : m_root(root)
    , m_state(std::make_shared<State>())
{
}

std::shared_ptr<const FileIndex::Data> FileIndex::data() const
{
    QMutexLocker locker(&m_state->lock);
    return m_state->data;
}

void FileIndex::refresh(int maxAgeSeconds)
{
    const auto current = data();
    const qint64 now = QDateTime::currentSecsSinceEpoch();
    if (current && now - current->built < maxAgeSeconds) {
        return;
    }
    if (m_state->scanning.exchange(true)) {
        return;
    }
    QThreadPool::globalInstance()->start([state = m_state, root = m_root]() {
        auto fresh = scan(root);
        {
            QMutexLocker locker(&state->lock);
            state->data = std::move(fresh);
        }
        state->scanning.store(false);
    });
}

void FileIndex::ensure()
{
    for (int i = 0; i < 400 && !data(); ++i) {
        if (!m_state->scanning.exchange(true)) {
            auto fresh = scan(m_root);
            QMutexLocker locker(&m_state->lock);
            m_state->data = std::move(fresh);
            m_state->scanning.store(false);
            return;
        }
        QThread::msleep(5);
    }
}

std::shared_ptr<const FileIndex::Data> FileIndex::scan(const QString &root)
{
    auto d = std::make_shared<Data>();
    d->built = QDateTime::currentSecsSinceEpoch();
    d->entries.reserve(16384);
    struct Pending {
        quint32 index;
        std::string path;
        int depth;
    };
    std::vector<Pending> stack;
    stack.push_back({UINT32_MAX, QFile::encodeName(root).toStdString(), 0});
    while (!stack.empty() && d->entries.size() < MaxEntries) {
        Pending dir = std::move(stack.back());
        stack.pop_back();
        DIR *handle = opendir(dir.path.c_str());
        if (!handle) {
            continue;
        }
        const int fd = dirfd(handle);
        while (dirent *e = readdir(handle)) {
            if (skipped(e->d_name)) {
                continue;
            }
            struct stat st;
            if (fstatat(fd, e->d_name, &st, AT_SYMLINK_NOFOLLOW) != 0) {
                continue;
            }
            const bool isDir = S_ISDIR(st.st_mode);
            if (!isDir && !S_ISREG(st.st_mode)) {
                continue;
            }
            const QByteArray name(e->d_name);
            const QByteArray lower = QString::fromUtf8(name).toLower().toUtf8();
            if (name.size() > 0xffff || lower.size() > 0xffff) {
                continue;
            }
            Entry entry;
            entry.parent = dir.index;
            entry.name = quint32(d->names.size());
            entry.nameLen = quint16(name.size());
            entry.lower = quint32(d->lowers.size());
            entry.lowerLen = quint16(lower.size());
            entry.depth = quint16(dir.depth);
            entry.dir = isDir;
            entry.mtime = st.st_mtim.tv_sec;
            d->names.append(name);
            d->lowers.append(lower);
            d->entries.push_back(entry);
            if (isDir && dir.depth + 1 < MaxDepth) {
                stack.push_back({quint32(d->entries.size() - 1), dir.path + '/' + e->d_name, dir.depth + 1});
            }
            if (d->entries.size() >= MaxEntries) {
                break;
            }
        }
        closedir(handle);
    }
    d->entries.shrink_to_fit();
    d->names.squeeze();
    d->lowers.squeeze();
    return d;
}

QString FileIndex::pathOf(const Data &d, quint32 index) const
{
    QByteArray path;
    std::vector<quint32> chain;
    for (quint32 i = index; i != UINT32_MAX; i = d.entries[i].parent) {
        chain.push_back(i);
    }
    path = QFile::encodeName(m_root);
    for (auto it = chain.rbegin(); it != chain.rend(); ++it) {
        const Entry &e = d.entries[*it];
        path += '/';
        path += QByteArrayView(d.names.constData() + e.name, e.nameLen);
    }
    return QFile::decodeName(path);
}

FileIndex::Hit FileIndex::hitFor(const Data &d, quint32 index, double score) const
{
    const Entry &e = d.entries[index];
    Hit hit;
    hit.path = pathOf(d, index);
    hit.name = QString::fromUtf8(d.names.constData() + e.name, e.nameLen);
    hit.dir = e.dir;
    hit.mtime = e.mtime;
    hit.score = score;
    return hit;
}

std::vector<FileIndex::Hit> FileIndex::search(const QString &query, int limit, bool filesOnly) const
{
    std::vector<Hit> hits;
    const auto d = data();
    if (!d) {
        return hits;
    }
    std::vector<QByteArray> words;
    for (const QString &w : query.toLower().split(QLatin1Char(' '), Qt::SkipEmptyParts)) {
        words.push_back(w.toUtf8());
    }
    if (words.empty()) {
        return hits;
    }
    const QByteArray whole = query.trimmed().toLower().toUtf8();
    const qint64 now = QDateTime::currentSecsSinceEpoch();
    std::vector<std::pair<double, quint32>> found;
    const char *lowers = d->lowers.constData();
    for (quint32 i = 0; i < d->entries.size(); ++i) {
        const Entry &e = d->entries[i];
        if (filesOnly && e.dir) {
            continue;
        }
        const QByteArrayView name(lowers + e.lower, e.lowerLen);
        double score = 0.0;
        bool all = true;
        for (std::size_t w = 0; w < words.size(); ++w) {
            const qsizetype pos = name.indexOf(words[w]);
            if (pos < 0) {
                all = false;
                break;
            }
            if (w == 0) {
                if (pos == 0) {
                    score = 0.86;
                } else if (separator(name[pos - 1])) {
                    score = 0.76;
                } else {
                    score = 0.62;
                }
            }
        }
        if (!all) {
            continue;
        }
        if (name == whole) {
            score = 1.0;
        } else if (name.startsWith(whole)) {
            const qsizetype rest = name.size() - whole.size();
            if (name[whole.size()] == '.' && name.indexOf('.', whole.size() + 1) < 0) {
                score = 0.96;
            } else {
                score += 0.06 * std::max<double>(0.0, 1.0 - rest / 40.0);
            }
        }
        const qint64 age = now - e.mtime;
        if (age < 3 * 86400) {
            score += 0.05;
        } else if (age < 30 * 86400) {
            score += 0.025;
        }
        score -= std::min(0.06, e.depth * 0.008);
        found.emplace_back(score, i);
    }
    const std::size_t keep = std::min<std::size_t>(found.size(), std::size_t(limit));
    std::partial_sort(found.begin(), found.begin() + keep, found.end(), [](const auto &a, const auto &b) {
        return a.first > b.first;
    });
    hits.reserve(keep);
    for (std::size_t i = 0; i < keep; ++i) {
        hits.push_back(hitFor(*d, found[i].second, std::clamp(found[i].first, 0.0, 1.0)));
    }
    return hits;
}

std::vector<FileIndex::Hit> FileIndex::recent(int limit) const
{
    std::vector<Hit> hits;
    const auto d = data();
    if (!d) {
        return hits;
    }
    std::vector<std::pair<qint64, quint32>> files;
    files.reserve(d->entries.size());
    for (quint32 i = 0; i < d->entries.size(); ++i) {
        if (!d->entries[i].dir) {
            files.emplace_back(d->entries[i].mtime, i);
        }
    }
    const std::size_t keep = std::min<std::size_t>(files.size(), std::size_t(limit));
    std::partial_sort(files.begin(), files.begin() + keep, files.end(), [](const auto &a, const auto &b) {
        return a.first > b.first;
    });
    for (std::size_t i = 0; i < keep; ++i) {
        hits.push_back(hitFor(*d, files[i].second, 1.0 - double(i) / double(keep + 1)));
    }
    return hits;
}
