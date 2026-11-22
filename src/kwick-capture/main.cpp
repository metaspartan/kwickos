#include "app.h"

#include <KDBusService>

#include <QDateTime>
#include <QDir>
#include <QGuiApplication>
#include <QIcon>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QTextStream>

int main(int argc, char **argv)
{
    const qint64 started = QDateTime::currentMSecsSinceEpoch();
    for (int i = 1; i < argc; ++i) {
        const QByteArray arg(argv[i]);
        if (arg == "--help" || arg == "-h") {
            QTextStream out(stdout);
            out << "Usage: kwick-capture [option]\n\n"
                << "  (no option)             show the capture bar\n"
                << "  --area                  capture a selection\n"
                << "  --window                capture a window\n"
                << "  --screen                capture the entire screen\n"
                << "  --text                  copy text from a selection\n"
                << "  --color                 pick a color from the screen\n"
                << "  --record [area|screen]  start or stop a screen recording\n"
                << "  --stop                  stop the current recording\n"
                << "  --markup FILE           open the markup editor on an image\n";
            return 0;
        }
    }
    if (!qEnvironmentVariableIsSet("QT_QUICK_BACKEND") && !qEnvironmentVariableIsSet("QSG_RHI_BACKEND")) {
        QQuickWindow::setGraphicsApi(QSGRendererInterface::Software);
    }
    const QList<QByteArray> hidden{"QT_QPA_PLATFORMTHEME", "XDG_CURRENT_DESKTOP", "KDE_FULL_SESSION", "DESKTOP_SESSION", "XDG_SESSION_DESKTOP"};
    QList<QByteArray> saved;
    const bool lean = !qEnvironmentVariableIsSet("KWICK_CAPTURE_THEME");
    for (const QByteArray &name : hidden) {
        saved.append(qgetenv(name.constData()));
        if (lean) {
            qunsetenv(name.constData());
        }
    }
    if (lean) {
        qputenv("QT_QPA_PLATFORMTHEME", "generic");
    }
    QGuiApplication app(argc, argv);
    for (int i = 0; i < hidden.size(); ++i) {
        if (saved.at(i).isEmpty()) {
            qunsetenv(hidden.at(i).constData());
        } else {
            qputenv(hidden.at(i).constData(), saved.at(i));
        }
    }
    app.setApplicationName(QStringLiteral("kwick-capture"));
    app.setApplicationDisplayName(QStringLiteral("Capture"));
    app.setOrganizationDomain(QStringLiteral("kwickos.org"));
    app.setDesktopFileName(QStringLiteral("kwick-capture"));
    app.setQuitOnLastWindowClosed(false);
    app.setProperty("started", started);
    app.setWindowIcon(QIcon::fromTheme(QStringLiteral("kwick-capture")));

    const bool trace = qEnvironmentVariableIsSet("KWICK_CAPTURE_TRACE");
    if (trace) {
        qInfo("kwick-capture: application %lld ms", static_cast<long long>(QDateTime::currentMSecsSinceEpoch() - started));
    }
    KDBusService service(KDBusService::Unique);
    if (trace) {
        qInfo("kwick-capture: dbus %lld ms", static_cast<long long>(QDateTime::currentMSecsSinceEpoch() - started));
    }
    App capture(qEnvironmentVariable("KWICK_CAPTURE_DESKTOP"), nullptr);
    if (trace) {
        qInfo("kwick-capture: app %lld ms", static_cast<long long>(QDateTime::currentMSecsSinceEpoch() - started));
    }
    QObject::connect(&service, &KDBusService::activateRequested, &capture, [&capture](const QStringList &arguments, const QString &workingDirectory) {
        capture.handle(arguments, workingDirectory);
    });
    capture.handle(app.arguments(), QDir::currentPath());
    return app.exec();
}
