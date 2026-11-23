#include "platform.h"

#include <QApplication>
#include <QDir>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QUrl>

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    const QString id = qEnvironmentVariable("KWICK_APP_ID", QStringLiteral("kwick-settings"));
    app.setApplicationName(id);
    app.setApplicationDisplayName(qEnvironmentVariable("KWICK_APP_NAME", QStringLiteral("KwickOS Settings")));
    app.setOrganizationDomain(QStringLiteral("kwickos.org"));
    app.setDesktopFileName(id);
    app.setWindowIcon(QIcon::fromTheme(qEnvironmentVariable("KWICK_APP_ICON", id)));
    QQuickWindow::setDefaultAlphaBuffer(true);

    const QString qml = qEnvironmentVariable("KWICK_APP_QML", QDir(qEnvironmentVariable("KWICK_SETTINGS_DIR", QStringLiteral("/usr/share/kwick/settings"))).absoluteFilePath(QStringLiteral("Main.qml")));
    QQmlApplicationEngine engine;
    Platform platform;
    engine.rootContext()->setContextProperty(QStringLiteral("Platform"), &platform);
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() {
            QCoreApplication::exit(1);
        },
        Qt::QueuedConnection);
    engine.load(QUrl::fromLocalFile(qml));
    return app.exec();
}
