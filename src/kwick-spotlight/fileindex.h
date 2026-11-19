#pragma once

#include <QByteArray>
#include <QMutex>
#include <QString>

#include <atomic>
#include <memory>
#include <vector>

class FileIndex
{
public:
    struct Hit {
        QString path;
        QString name;
        bool dir = false;
        qint64 mtime = 0;
        double score = 0.0;
    };

    explicit FileIndex(const QString &root);

    void refresh(int maxAgeSeconds);
    void ensure();
    std::vector<Hit> search(const QString &query, int limit, bool filesOnly) const;
    std::vector<Hit> recent(int limit) const;

private:
    struct Entry {
        quint32 parent;
        quint32 name;
        quint32 lower;
        quint16 nameLen;
        quint16 lowerLen;
        quint16 depth;
        bool dir;
        qint64 mtime;
    };

    struct Data {
        std::vector<Entry> entries;
        QByteArray names;
        QByteArray lowers;
        qint64 built = 0;
    };

    struct State {
        QMutex lock;
        std::shared_ptr<const Data> data;
        std::atomic<bool> scanning = false;
    };

    static std::shared_ptr<const Data> scan(const QString &root);
    std::shared_ptr<const Data> data() const;
    QString pathOf(const Data &d, quint32 index) const;
    Hit hitFor(const Data &d, quint32 index, double score) const;

    const QString m_root;
    const std::shared_ptr<State> m_state;
};
