#include "resultmodel.h"

#include <KRunner/AbstractRunner>
#include <KRunner/Action>

#include <QIcon>
#include <QSet>

#include <algorithm>

namespace
{
constexpr int GroupLimit = 5;
constexpr int BrowseLimit = 80;
const QString TopHit = QStringLiteral("Top Hit");

QString runnerId(const KRunner::QueryMatch &m)
{
    return m.runner() ? m.runner()->id() : QString();
}

bool better(const KRunner::QueryMatch &a, const KRunner::QueryMatch &b)
{
    if (a.categoryRelevance() != b.categoryRelevance()) {
        return a.categoryRelevance() > b.categoryRelevance();
    }
    return a.relevance() > b.relevance();
}
}

ResultModel::ResultModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int ResultModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_rows.size());
}

QHash<int, QByteArray> ResultModel::roleNames() const
{
    return {
        {TitleRole, "title"},
        {SubtitleRole, "subtitle"},
        {IconRole, "icon"},
        {SectionRole, "section"},
        {RunnerRole, "runner"},
        {ActionRole, "action"},
        {TopRole, "topHit"},
    };
}

QVariant ResultModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_rows.size()) {
        return {};
    }
    const Row &row = m_rows.at(index.row());
    switch (role) {
    case TitleRole:
        return row.match.text();
    case SubtitleRole:
        return row.match.subtext();
    case IconRole:
        if (!row.match.iconName().isEmpty()) {
            return row.match.iconName();
        }
        return row.match.icon();
    case SectionRole:
        return row.section;
    case RunnerRole:
        return runnerId(row.match);
    case ActionRole:
        return row.match.actions().isEmpty() ? QString() : row.match.actions().constFirst().text();
    case TopRole:
        return row.section == TopHit;
    default:
        return {};
    }
}

KRunner::QueryMatch ResultModel::match(int row) const
{
    return row >= 0 && row < m_rows.size() ? m_rows.at(row).match : KRunner::QueryMatch();
}

QString ResultModel::topTitle() const
{
    return m_topTitle;
}

void ResultModel::clear()
{
    setMatches({}, false);
}

void ResultModel::setMatches(const QList<KRunner::QueryMatch> &matches, bool browse)
{
    QList<Row> rows;
    if (browse) {
        QList<KRunner::QueryMatch> sorted = matches;
        std::stable_sort(sorted.begin(), sorted.end(), [](const auto &a, const auto &b) {
            return a.relevance() > b.relevance();
        });
        QSet<QString> seen;
        for (const auto &m : std::as_const(sorted)) {
            if (rows.size() >= BrowseLimit) {
                break;
            }
            const QString key = m.text() + QChar(0x1f) + m.subtext();
            if (seen.contains(key)) {
                continue;
            }
            seen.insert(key);
            rows.append({m, m.matchCategory()});
        }
    } else {
        QSet<QString> titles;
        for (const auto &m : matches) {
            if (m.matchCategory() != QLatin1String("Command Line")) {
                titles.insert(m.text().toLower());
            }
        }
        QHash<QString, QList<KRunner::QueryMatch>> groups;
        QSet<QString> seen;
        QList<KRunner::QueryMatch> sorted = matches;
        std::stable_sort(sorted.begin(), sorted.end(), better);
        for (const auto &m : std::as_const(sorted)) {
            if (m.matchCategory() == QLatin1String("Command Line") && titles.contains(m.text().toLower())) {
                continue;
            }
            const QString key = m.text() + QChar(0x1f) + m.subtext();
            if (seen.contains(key)) {
                continue;
            }
            seen.insert(key);
            groups[m.matchCategory()].append(m);
        }
        QList<QString> order = groups.keys();
        std::sort(order.begin(), order.end(), [&groups](const QString &a, const QString &b) {
            return better(groups[a].constFirst(), groups[b].constFirst());
        });
        if (!order.isEmpty()) {
            QList<KRunner::QueryMatch> &first = groups[order.constFirst()];
            rows.append({first.takeFirst(), TopHit});
            if (first.isEmpty()) {
                order.removeFirst();
            }
        }
        for (const QString &name : std::as_const(order)) {
            const auto &group = groups[name];
            for (int i = 0; i < group.size() && i < GroupLimit; ++i) {
                rows.append({group.at(i), name});
            }
        }
    }
    const QString top = !browse && !rows.isEmpty() ? rows.constFirst().match.text() : QString();
    const bool countChange = rows.size() != m_rows.size();
    beginResetModel();
    m_rows = std::move(rows);
    endResetModel();
    if (countChange) {
        Q_EMIT countChanged();
    }
    if (top != m_topTitle) {
        m_topTitle = top;
        Q_EMIT topTitleChanged();
    }
}
