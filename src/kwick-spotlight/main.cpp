#include "spotlight.h"

#include <KDBusService>
#include <KRunner/RunnerManager>

#include <QGuiApplication>
#include <QTextStream>

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("kwick-spotlight"));
    app.setApplicationDisplayName(QStringLiteral("Spotlight"));
    app.setOrganizationDomain(QStringLiteral("kwickos.org"));
    app.setDesktopFileName(QStringLiteral("kwick-search"));
    app.setQuitOnLastWindowClosed(false);

    if (app.arguments().contains(QStringLiteral("--list-runners"))) {
        QTextStream out(stdout);
        for (const KPluginMetaData &data : KRunner::RunnerManager::runnerMetaDataList()) {
            out << data.pluginId() << '\t' << data.name() << '\n';
        }
        return 0;
    }

    KDBusService service(KDBusService::Unique);
    Spotlight spotlight;
    QObject::connect(&service, &KDBusService::activateRequested, &spotlight, [&spotlight](const QStringList &arguments) {
        spotlight.handle(arguments);
    });
    spotlight.handle(app.arguments());
    return app.exec();
}
