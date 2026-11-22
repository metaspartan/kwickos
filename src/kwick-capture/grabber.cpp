#include "grabber.h"

#include "portal.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusUnixFileDescriptor>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPointer>
#include <QProcess>
#include <QScreen>
#include <QSet>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QUrl>

#include <algorithm>
#include <cerrno>
#include <fcntl.h>
#include <memory>
#include <thread>
#include <unistd.h>

namespace
{
struct PipeState {
    QByteArray bytes;
    QVariantMap meta;
    bool haveBytes = false;
    bool haveMeta = false;
    bool failed = false;
};

QString tempPng()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    return QStringLiteral("%1/kwick-capture-%2-%3.png").arg(dir.isEmpty() ? QDir::tempPath() : dir).arg(QCoreApplication::applicationPid()).arg(QDateTime::currentMSecsSinceEpoch());
}

void collectSway(const QJsonObject &node, QVariantList &out)
{
    const bool leaf = node.value(QStringLiteral("pid")).toInt() > 0 && node.value(QStringLiteral("visible")).toBool();
    if (leaf) {
        const QJsonObject rect = node.value(QStringLiteral("rect")).toObject();
        out.append(QVariantMap{
            {QStringLiteral("x"), rect.value(QStringLiteral("x")).toInt()},
            {QStringLiteral("y"), rect.value(QStringLiteral("y")).toInt()},
            {QStringLiteral("w"), rect.value(QStringLiteral("width")).toInt()},
            {QStringLiteral("h"), rect.value(QStringLiteral("height")).toInt()},
            {QStringLiteral("title"), node.value(QStringLiteral("name")).toString()},
        });
    }
    for (const QString key : {QStringLiteral("floating_nodes"), QStringLiteral("nodes")}) {
        const QJsonArray children = node.value(key).toArray();
        for (const QJsonValue &child : children) {
            collectSway(child.toObject(), out);
        }
    }
}

QByteArray runSync(const QString &program, const QStringList &arguments, int timeout = 2000)
{
    QProcess process;
    process.start(program, arguments);
    if (!process.waitForFinished(timeout)) {
        process.kill();
        return {};
    }
    return process.readAllStandardOutput();
}
}

Grabber::Grabber(const QString &desktop, QObject *parent)
    : QObject(parent)
    , m_desktop(desktop)
{
}

bool Grabber::hasTool(const QString &name)
{
    return !QStandardPaths::findExecutable(name).isEmpty();
}

QRect Grabber::virtualGeometry()
{
    QRect all;
    for (QScreen *screen : QGuiApplication::screens()) {
        all = all.united(screen->geometry());
    }
    return all;
}

bool Grabber::ownWindowPicker() const
{
    return m_desktop == QLatin1String("hyprland") || m_desktop == QLatin1String("sway");
}

QVariantList Grabber::windows(const QRect &virtualGeometry) const
{
    QVariantList out;
    if (m_desktop == QLatin1String("hyprland") && hasTool(QStringLiteral("hyprctl"))) {
        QSet<int> active;
        const QJsonArray monitors = QJsonDocument::fromJson(runSync(QStringLiteral("hyprctl"), {QStringLiteral("monitors"), QStringLiteral("-j")})).array();
        for (const QJsonValue &monitor : monitors) {
            active.insert(monitor.toObject().value(QStringLiteral("activeWorkspace")).toObject().value(QStringLiteral("id")).toInt());
            const int special = monitor.toObject().value(QStringLiteral("specialWorkspace")).toObject().value(QStringLiteral("id")).toInt();
            if (special != 0) {
                active.insert(special);
            }
        }
        QJsonArray clients = QJsonDocument::fromJson(runSync(QStringLiteral("hyprctl"), {QStringLiteral("clients"), QStringLiteral("-j")})).array();
        QList<QJsonObject> sorted;
        for (const QJsonValue &client : clients) {
            const QJsonObject object = client.toObject();
            if (!object.value(QStringLiteral("mapped")).toBool(true) || object.value(QStringLiteral("hidden")).toBool()) {
                continue;
            }
            if (!active.contains(object.value(QStringLiteral("workspace")).toObject().value(QStringLiteral("id")).toInt())) {
                continue;
            }
            sorted.append(object);
        }
        std::sort(sorted.begin(), sorted.end(), [](const QJsonObject &a, const QJsonObject &b) {
            const bool fa = a.value(QStringLiteral("floating")).toBool();
            const bool fb = b.value(QStringLiteral("floating")).toBool();
            if (fa != fb) {
                return fa;
            }
            return a.value(QStringLiteral("focusHistoryID")).toInt() < b.value(QStringLiteral("focusHistoryID")).toInt();
        });
        for (const QJsonObject &object : sorted) {
            const QJsonArray at = object.value(QStringLiteral("at")).toArray();
            const QJsonArray size = object.value(QStringLiteral("size")).toArray();
            out.append(QVariantMap{
                {QStringLiteral("x"), at.at(0).toInt() - virtualGeometry.x()},
                {QStringLiteral("y"), at.at(1).toInt() - virtualGeometry.y()},
                {QStringLiteral("w"), size.at(0).toInt()},
                {QStringLiteral("h"), size.at(1).toInt()},
                {QStringLiteral("title"), object.value(QStringLiteral("class")).toString()},
            });
        }
    } else if (m_desktop == QLatin1String("sway") && hasTool(QStringLiteral("swaymsg"))) {
        QVariantList raw;
        collectSway(QJsonDocument::fromJson(runSync(QStringLiteral("swaymsg"), {QStringLiteral("-t"), QStringLiteral("get_tree")})).object(), raw);
        for (const QVariant &entry : raw) {
            QVariantMap map = entry.toMap();
            map[QStringLiteral("x")] = map.value(QStringLiteral("x")).toInt() - virtualGeometry.x();
            map[QStringLiteral("y")] = map.value(QStringLiteral("y")).toInt() - virtualGeometry.y();
            out.append(map);
        }
    }
    return out;
}

void Grabber::desktop(bool pointer, Ok ok, Fail fail)
{
    if (m_desktop == QLatin1String("kde")) {
        const QVariantMap options{
            {QStringLiteral("include-cursor"), pointer},
            {QStringLiteral("native-resolution"), true},
        };
        QStringList fallback{QStringLiteral("-b"), QStringLiteral("-n"), QStringLiteral("-f")};
        if (pointer) {
            fallback << QStringLiteral("-p");
        }
        kwin(QStringLiteral("CaptureWorkspace"), {}, options, ok, fail, [this, fallback, ok, fail]() {
            spectacle(fallback, ok, fail);
        });
    } else if (m_desktop == QLatin1String("hyprland") || m_desktop == QLatin1String("sway") || (m_desktop != QLatin1String("gnome") && hasTool(QStringLiteral("grim")))) {
        grim(pointer, ok, fail);
    } else {
        portal(false, ok, fail);
    }
}

void Grabber::window(bool pointer, Ok ok, Fail fail)
{
    if (m_desktop == QLatin1String("kde")) {
        const QVariantMap options{
            {QStringLiteral("include-cursor"), pointer},
            {QStringLiteral("include-decoration"), true},
            {QStringLiteral("include-shadow"), false},
            {QStringLiteral("native-resolution"), true},
        };
        QStringList fallback{QStringLiteral("-b"), QStringLiteral("-n"), QStringLiteral("-a")};
        if (pointer) {
            fallback << QStringLiteral("-p");
        }
        kwin(QStringLiteral("CaptureInteractive"), {QVariant::fromValue(0u)}, options, ok, fail, [this, fallback, ok, fail]() {
            spectacle(fallback, ok, fail);
        });
    } else {
        portal(true, ok, fail);
    }
}

void Grabber::kwin(const QString &method, const QVariantList &leading, const QVariantMap &options, Ok ok, Fail fail, std::function<void()> fallback)
{
    int fds[2];
    if (pipe2(fds, O_CLOEXEC) != 0) {
        fallback();
        return;
    }
    auto state = std::make_shared<PipeState>();
    QPointer<Grabber> self(this);
    const bool opaque = method != QLatin1String("CaptureInteractive") && method != QLatin1String("CaptureActiveWindow");
    auto finish = [state, ok, fail, fallback, opaque]() {
        if (!state->haveBytes || !state->haveMeta || state->failed) {
            return;
        }
        const int width = state->meta.value(QStringLiteral("width")).toInt();
        const int height = state->meta.value(QStringLiteral("height")).toInt();
        const int stride = state->meta.value(QStringLiteral("stride")).toInt();
        const auto format = static_cast<QImage::Format>(state->meta.value(QStringLiteral("format")).toInt());
        if (width <= 0 || height <= 0 || state->bytes.size() < qsizetype(stride) * height) {
            fallback();
            return;
        }
        QImage image(reinterpret_cast<const uchar *>(state->bytes.constData()), width, height, stride, format);
        const qreal scale = state->meta.value(QStringLiteral("scale"), 1.0).toReal();
        image.setDevicePixelRatio(1);
        Shot shot;
        shot.image = image.convertToFormat(opaque ? QImage::Format_RGB32 : QImage::Format_ARGB32);
        shot.geometry = Grabber::virtualGeometry();
        if (shot.geometry.isEmpty()) {
            shot.geometry = QRect(0, 0, qRound(width / scale), qRound(height / scale));
        }
        ok(shot);
    };
    const int readFd = fds[0];
    std::thread([readFd, state, self, finish]() {
        QByteArray bytes;
        char buffer[65536];
        for (;;) {
            const ssize_t n = ::read(readFd, buffer, sizeof buffer);
            if (n > 0) {
                bytes.append(buffer, n);
            } else if (n == 0 || errno != EINTR) {
                break;
            }
        }
        ::close(readFd);
        QMetaObject::invokeMethod(qApp, [state, bytes, self, finish]() {
            if (!self) {
                return;
            }
            state->bytes = bytes;
            state->haveBytes = true;
            if (qEnvironmentVariableIsSet("KWICK_CAPTURE_TRACE")) {
                qInfo("kwick-capture: KWin pipe %lld bytes", static_cast<long long>(bytes.size()));
            }
            finish();
        }, Qt::QueuedConnection);
    }).detach();

    QDBusMessage message = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/org/kde/KWin/ScreenShot2"), QStringLiteral("org.kde.KWin.ScreenShot2"), method);
    QVariantList arguments = leading;
    arguments << options << QVariant::fromValue(QDBusUnixFileDescriptor(fds[1]));
    message.setArguments(arguments);
    ::close(fds[1]);
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(message, 600000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [state, finish, fallback, fail](QDBusPendingCallWatcher *call) {
        call->deleteLater();
        const QDBusPendingReply<QVariantMap> reply = *call;
        if (reply.isError()) {
            state->failed = true;
            if (reply.error().name().endsWith(QLatin1String("Cancelled"))) {
                fail({QString(), QString(), true});
            } else {
                qInfo("kwick-capture: KWin ScreenShot2 %s, using Spectacle", qPrintable(reply.error().name()));
                fallback();
            }
            return;
        }
        state->meta = reply.value();
        if (qEnvironmentVariableIsSet("KWICK_CAPTURE_TRACE")) {
            qInfo() << "kwick-capture: KWin reply" << state->meta;
        }
        state->haveMeta = true;
        finish();
    });
}

void Grabber::spectacle(const QStringList &arguments, Ok ok, Fail fail)
{
    if (!hasTool(QStringLiteral("spectacle"))) {
        fail({QStringLiteral("Spectacle is not installed."), QStringLiteral("kde-spectacle")});
        return;
    }
    const QString file = tempPng();
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process, file, ok, fail]() {
        process->deleteLater();
        if (!QFile::exists(file)) {
            fail({QString(), QString(), true});
            return;
        }
        loadFile(file, true, ok, fail);
    });
    process->start(QStringLiteral("spectacle"), QStringList(arguments) << QStringLiteral("-o") << file);
}

void Grabber::grim(bool pointer, Ok ok, Fail fail)
{
    if (!hasTool(QStringLiteral("grim"))) {
        fail({QStringLiteral("Screenshots on this desktop need grim."), QStringLiteral("grim")});
        return;
    }
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [process, ok, fail](int code) {
        process->deleteLater();
        const QByteArray data = process->readAllStandardOutput();
        QImage image;
        if (code == 0) {
            image.loadFromData(data, "PPM");
        }
        if (image.isNull()) {
            fail({QStringLiteral("grim could not capture the screen: %1").arg(QString::fromUtf8(process->readAllStandardError()).trimmed()), QString()});
            return;
        }
        ok({image.convertToFormat(QImage::Format_RGB32), Grabber::virtualGeometry()});
    });
    QStringList arguments{QStringLiteral("-t"), QStringLiteral("ppm")};
    if (pointer) {
        arguments << QStringLiteral("-c");
    }
    arguments << QStringLiteral("-");
    process->start(QStringLiteral("grim"), arguments);
}

void Grabber::portal(bool interactive, Ok ok, Fail fail)
{
    const QVariantMap options{
        {QStringLiteral("interactive"), interactive},
        {QStringLiteral("modal"), true},
    };
    Portal::call(QStringLiteral("org.freedesktop.portal.Screenshot"), QStringLiteral("Screenshot"), {QString()}, options, [this, ok, fail, interactive](uint code, const QVariantMap &results) {
        if (code != 0) {
            if (results.contains(QStringLiteral("error"))) {
                fail({QStringLiteral("The screenshot portal is not available: %1").arg(results.value(QStringLiteral("error")).toString()), QStringLiteral("xdg-desktop-portal-gnome")});
            } else {
                fail({QString(), QString(), true});
            }
            return;
        }
        const QString file = QUrl(results.value(QStringLiteral("uri")).toString()).toLocalFile();
        loadFile(file, true, [ok, interactive](const Shot &shot) {
            Shot copy = shot;
            if (!interactive) {
                copy.geometry = Grabber::virtualGeometry();
            }
            ok(copy);
        }, fail);
    }, this);
}

void Grabber::loadFile(const QString &path, bool remove, Ok ok, Fail fail)
{
    QImage image(path);
    if (remove) {
        QFile::remove(path);
    }
    if (image.isNull()) {
        fail({QStringLiteral("The screenshot could not be read."), QString()});
        return;
    }
    image.setDevicePixelRatio(1);
    ok({image.convertToFormat(QImage::Format_ARGB32), QRect(QPoint(0, 0), image.size())});
}
