#pragma once

#include <KRunner/QueryMatch>

#include <QAbstractListModel>

class ResultModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(QString topTitle READ topTitle NOTIFY topTitleChanged)

public:
    enum Role {
        TitleRole = Qt::UserRole + 1,
        SubtitleRole,
        IconRole,
        SectionRole,
        RunnerRole,
        ActionRole,
        TopRole,
    };

    explicit ResultModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setMatches(const QList<KRunner::QueryMatch> &matches, bool browse);
    void clear();
    KRunner::QueryMatch match(int row) const;
    QString topTitle() const;

Q_SIGNALS:
    void countChanged();
    void topTitleChanged();

private:
    struct Row {
        KRunner::QueryMatch match;
        QString section;
    };

    QList<Row> m_rows;
    QString m_topTitle;
};
