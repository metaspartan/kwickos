#include "quicklook.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QStandardPaths>
#include <QTextStream>
#include <QTimer>
#include <QUrl>

int main(int argc, char **argv)
{
    QStringList files;
    QString host;
    bool toggle = false;
    bool service = false;
    for (int i = 1; i < argc; ++i) {
        const QString arg = QString::fromLocal8Bit(argv[i]);
        if (arg == QLatin1String("--help") || arg == QLatin1String("-h")) {
            QTextStream(stdout) << "Usage: kwick-quicklook [--toggle] FILE...\n\nPreview files: Space or Esc closes, arrow keys move, Enter opens.\n";
            return 0;
        } else if (arg == QLatin1String("--toggle")) {
            toggle = true;
        } else if (arg == QLatin1String("--service")) {
            service = true;
        } else if (arg == QLatin1String("--host") && i + 1 < argc) {
            host = QString::fromLocal8Bit(argv[++i]);
        } else {
            const QUrl u = arg.contains(QLatin1String("://")) ? QUrl(arg) : QUrl::fromLocalFile(QFileInfo(arg).absoluteFilePath());
            files.append(u.isLocalFile() ? u.toLocalFile() : arg);
        }
    }

    QDBusConnection bus = QDBusConnection::sessionBus();
    if (bus.isConnected() && bus.interface()->isServiceRegistered(QStringLiteral("org.kwickos.QuickLook"))) {
        if (!files.isEmpty()) {
            QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.kwickos.QuickLook"), QStringLiteral("/org/kwickos/QuickLook"), QStringLiteral("org.kwickos.QuickLook"), toggle ? QStringLiteral("Toggle") : QStringLiteral("Show"));
            msg.setArguments({files, 0, host});
            bus.call(msg, QDBus::Block, 3000);
        }
        return 0;
    }

    auto hasMenu = [](const QString &prefix) {
        return !QStandardPaths::locate(QStandardPaths::GenericConfigLocation, QStringLiteral("menus/") + prefix + QStringLiteral("applications.menu")).isEmpty();
    };
    if (!hasMenu(qEnvironmentVariable("XDG_MENU_PREFIX"))) {
        if (hasMenu(QStringLiteral("plasma-"))) {
            qputenv("XDG_MENU_PREFIX", "plasma-");
        } else if (hasMenu(QString())) {
            qunsetenv("XDG_MENU_PREFIX");
        }
    }
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("kwick-quicklook"));
    app.setApplicationDisplayName(QStringLiteral("Quick Look"));
    app.setOrganizationDomain(QStringLiteral("kwickos.org"));
    app.setDesktopFileName(QStringLiteral("kwick-quicklook"));
    app.setQuitOnLastWindowClosed(false);

    QuickLook ql;
    new QuickLookService(&ql);
    new NautilusPreviewer(&ql);
    bus.registerObject(QStringLiteral("/org/kwickos/QuickLook"), &ql, QDBusConnection::ExportAdaptors);
    bus.registerObject(QStringLiteral("/org/gnome/NautilusPreviewer"), &ql, QDBusConnection::ExportAdaptors);
    if (!bus.registerService(QStringLiteral("org.kwickos.QuickLook"))) {
        return 0;
    }
    bus.registerService(QStringLiteral("org.gnome.NautilusPreviewer"));

    QTimer idle;
    idle.setSingleShot(true);
    idle.setInterval(180000);
    QObject::connect(&idle, &QTimer::timeout, &app, [&ql]() {
        if (!ql.shown()) {
            QCoreApplication::quit();
        }
    });
    QObject::connect(&ql, &QuickLook::shownChanged, &app, [&ql, &idle]() {
        ql.shown() ? idle.stop() : idle.start();
    });
    idle.start();

    if (!files.isEmpty()) {
        ql.show(files, 0, host);
    } else if (!service) {
        idle.setInterval(1000);
        idle.start();
    }
    return app.exec();
}
