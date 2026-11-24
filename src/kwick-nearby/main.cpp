#include "identity.h"
#include "nearby.h"
#include "settings.h"

#include <KDBusService>

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QIcon>
#include <QJsonDocument>
#include <QProcess>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QSslCertificate>
#include <QTextStream>

namespace
{
const QString ServiceName = QStringLiteral("org.kwickos.kwick-nearby");

bool shouldRun(const Settings &s)
{
    const QString v = s.effectiveVisibility(QDateTime::currentMSecsSinceEpoch());
    return v == QLatin1String("everyone") || (v == QLatin1String("contacts") && !s.known.isEmpty());
}

bool daemonRunning()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    return bus.isConnected() && bus.interface() && bus.interface()->isServiceRegistered(ServiceName).value();
}

int status()
{
    Settings s;
    s.load();
    QJsonObject o = s.toJson();
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    o.insert(QLatin1String("effective"), s.effectiveVisibility(now));
    o.insert(QLatin1String("minutesLeft"), s.visibility == QLatin1String("everyone") && s.everyoneUntil > now ? double((s.everyoneUntil - now + 59999) / 60000) : 0.0);
    o.insert(QLatin1String("running"), daemonRunning());
    o.insert(QLatin1String("port"), Protocol::Port);
    QFile cert(Settings::dataDir() + QStringLiteral("/cert.pem"));
    if (cert.open(QIODevice::ReadOnly)) {
        o.insert(QLatin1String("fingerprint"), Identity::fingerprintOf(QSslCertificate(cert.readAll(), QSsl::Pem)));
    }
    QTextStream(stdout) << QJsonDocument(o).toJson(QJsonDocument::Compact) << "\n";
    return 0;
}

int set(const QString &key, const QString &value)
{
    Settings s;
    s.load();
    if (key == QLatin1String("alias") || key == QLatin1String("name")) {
        const QString alias = value.trimmed().left(64);
        s.alias = alias.isEmpty() ? Settings::defaultAlias() : alias;
    } else if (key == QLatin1String("visibility")) {
        if (value == QLatin1String("everyone")) {
            s.visibility = value;
            s.everyoneUntil = QDateTime::currentMSecsSinceEpoch() + EveryoneWindowMs;
        } else if (value == QLatin1String("contacts") || value == QLatin1String("off")) {
            s.visibility = value;
            s.everyoneUntil = 0;
        } else {
            QTextStream(stderr) << "kwick-nearby: visibility is off, contacts or everyone\n";
            return 2;
        }
    } else if (key == QLatin1String("folder")) {
        const QString dir = QDir(value).absolutePath();
        if (!QDir().mkpath(dir)) {
            QTextStream(stderr) << "kwick-nearby: cannot use " << dir << "\n";
            return 1;
        }
        s.folder = dir;
    } else if (key == QLatin1String("pin")) {
        const QString pin = value.trimmed();
        if (!pin.isEmpty() && (pin.size() < 4 || pin.size() > 12)) {
            QTextStream(stderr) << "kwick-nearby: the PIN needs 4 to 12 characters\n";
            return 2;
        }
        s.pin = pin;
        s.requirePin = !pin.isEmpty();
    } else if (key == QLatin1String("require-pin")) {
        s.requirePin = (value == QLatin1String("1") || value == QLatin1String("true") || value == QLatin1String("on")) && !s.pin.isEmpty();
    } else {
        QTextStream(stderr) << "kwick-nearby: unknown setting " << key << "\n";
        return 2;
    }
    if (!s.save()) {
        QTextStream(stderr) << "kwick-nearby: cannot write " << Settings::path() << "\n";
        return 1;
    }
    if (shouldRun(s) && !daemonRunning()) {
        QProcess::startDetached(QCoreApplication::applicationFilePath(), {QStringLiteral("--daemon")});
    }
    return 0;
}

int forget(const QString &fingerprint)
{
    Settings s;
    s.load();
    if (fingerprint == QLatin1String("all")) {
        s.known.clear();
    } else if (!s.forget(fingerprint)) {
        return 1;
    }
    return s.save() ? 0 : 1;
}

void usage()
{
    QTextStream(stdout) << "Usage: kwick-nearby [option] [FILE...]\n\n"
                        << "  FILE...                   share files or folders with a nearby device\n"
                        << "  --share [FILE...]         open the share sheet\n"
                        << "  --text TEXT               share text\n"
                        << "  --daemon                  receive in the background while visible\n"
                        << "  --autostart               start the receiver only if receiving is on\n"
                        << "  --status                  print the settings as JSON\n"
                        << "  --set KEY VALUE           alias, visibility (off|contacts|everyone), folder, pin, require-pin\n"
                        << "  --forget FINGERPRINT|all  forget a known device\n\n"
                        << "Send Nearby speaks the LocalSend protocol v2 on TCP and UDP port 53317.\n";
}
}

int main(int argc, char **argv)
{
    QStringList early;
    for (int i = 1; i < argc; ++i) {
        early.append(QString::fromLocal8Bit(argv[i]));
    }
    const QString first = early.value(0);
    if (first == QLatin1String("--help") || first == QLatin1String("-h")) {
        usage();
        return 0;
    }
    if (first == QLatin1String("--status") || first == QLatin1String("--set") || first == QLatin1String("--forget")) {
        QCoreApplication app(argc, argv);
        app.setApplicationName(QStringLiteral("kwick-nearby"));
        if (first == QLatin1String("--status")) {
            return status();
        }
        if (first == QLatin1String("--set") && early.size() >= 3) {
            return set(early.at(1), early.mid(2).join(QLatin1Char(' ')));
        }
        if (first == QLatin1String("--forget") && early.size() >= 2) {
            return forget(early.at(1));
        }
        usage();
        return 2;
    }
    if (first == QLatin1String("--autostart")) {
        Settings s;
        s.load();
        if (!shouldRun(s)) {
            return 0;
        }
    }
    if (!qEnvironmentVariableIsSet("QT_QUICK_BACKEND") && !qEnvironmentVariableIsSet("QSG_RHI_BACKEND")) {
        QQuickWindow::setGraphicsApi(QSGRendererInterface::Software);
    }
    if (qgetenv("XDG_CURRENT_DESKTOP").toLower().contains("gnome") && !qEnvironmentVariableIsSet("QT_WAYLAND_DECORATION")) {
        qputenv("QT_WAYLAND_DECORATION", "adwaita");
    }
    const QList<QByteArray> hidden{"QT_QPA_PLATFORMTHEME", "XDG_CURRENT_DESKTOP", "KDE_FULL_SESSION", "DESKTOP_SESSION", "XDG_SESSION_DESKTOP"};
    QList<QByteArray> saved;
    const bool lean = !qEnvironmentVariableIsSet("KWICK_NEARBY_THEME");
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
    app.setApplicationName(QStringLiteral("kwick-nearby"));
    app.setApplicationDisplayName(QStringLiteral("Send Nearby"));
    app.setOrganizationDomain(QStringLiteral("kwickos.org"));
    app.setDesktopFileName(QStringLiteral("kwick-nearby"));
    app.setQuitOnLastWindowClosed(false);
    app.setWindowIcon(QIcon::fromTheme(QStringLiteral("kwick-nearby")));

    KDBusService service(KDBusService::Unique);
    Nearby nearby;
    QObject::connect(&service, &KDBusService::activateRequested, &nearby, [&nearby](const QStringList &arguments, const QString &workingDirectory) {
        nearby.handle(arguments, workingDirectory);
    });
    nearby.handle(app.arguments(), QDir::currentPath());
    return app.exec();
}
