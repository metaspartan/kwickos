#pragma once

#include "fileindex.h"

#include <KRunner/AbstractRunner>
#include <KRunner/QueryMatch>

#include <QIcon>
#include <QMimeDatabase>
#include <QMutex>
#include <QStringList>

#include <memory>

class KwickRunner : public KRunner::AbstractRunner
{
    Q_OBJECT

public:
    KwickRunner(QObject *parent, const KPluginMetaData &metaData);

    void match(KRunner::RunnerContext &context) override;
    void run(const KRunner::RunnerContext &context, const KRunner::QueryMatch &match) override;

private:
    struct Page {
        QString name;
        QString keywords;
        QIcon icon;
    };

    struct Command {
        QString id;
        QString title;
        QString keywords;
        QString icon;
        QString subtitle;
    };

    struct State {
        bool dark = true;
        bool wifiHardware = false;
        bool wifi = false;
        QList<QStringList> vpns;
        QString layout;
    };

    struct Shared {
        QMutex lock;
        State state;
    };

    void prepareSession();
    void loadPages();
    QList<Command> commands() const;
    State state() const;

    void matchPages(KRunner::RunnerContext &context, const QString &query);
    void matchCommands(KRunner::RunnerContext &context, const QString &query, bool browse);
    void matchFiles(KRunner::RunnerContext &context, const QString &query, bool browse);
    void matchApps(KRunner::RunnerContext &context, const QString &query);
    void matchClipboard(KRunner::RunnerContext &context, const QString &query);
    void runCommand(const QString &id);

    static double score(const QString &query, const QString &title, const QString &keywords);
    QString category(const FileIndex::Hit &hit) const;

    FileIndex m_files;
    QMimeDatabase m_mime;
    QList<Page> m_pages;
    const std::shared_ptr<Shared> m_shared;
    const QString m_home;
};
