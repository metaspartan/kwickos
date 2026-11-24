#include "spotlight.h"

#include <KDBusService>
#include <KRunner/RunnerManager>

#include <QGuiApplication>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QStandardPaths>
#include <QTextStream>

namespace
{
bool hasMenu(const QString &prefix)
{
    return !QStandardPaths::locate(QStandardPaths::GenericConfigLocation, QStringLiteral("menus/") + prefix + QStringLiteral("applications.menu")).isEmpty();
}
}

int main(int argc, char **argv)
{
    if (!hasMenu(qEnvironmentVariable("XDG_MENU_PREFIX"))) {
        if (hasMenu(QStringLiteral("plasma-"))) {
            qputenv("XDG_MENU_PREFIX", "plasma-");
        } else if (hasMenu(QString())) {
            qunsetenv("XDG_MENU_PREFIX");
        }
    }
    if (!qEnvironmentVariableIsSet("QT_QUICK_BACKEND") && !qEnvironmentVariableIsSet("QSG_RHI_BACKEND")) {
        QQuickWindow::setGraphicsApi(QSGRendererInterface::Software);
    }
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("kwick-spotlight"));
    app.setApplicationDisplayName(QStringLiteral("Search"));
    app.setOrganizationDomain(QStringLiteral("kwickos.org"));
    app.setDesktopFileName(QStringLiteral("kwick-search"));
    app.setQuitOnLastWindowClosed(false);
    app.setQuitLockEnabled(false);

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
