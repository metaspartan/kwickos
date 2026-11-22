#include "recorder.h"

#include "portal.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusUnixFileDescriptor>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QScreen>
#include <QStandardPaths>
#include <QThread>
#include <QTimer>

#include <csignal>
#include <unistd.h>

namespace
{
QSize sizeOf(const QVariant &value)
{
    if (value.canConvert<QDBusArgument>()) {
        const QDBusArgument argument = value.value<QDBusArgument>();
        int w = 0;
        int h = 0;
        argument.beginStructure();
        argument >> w >> h;
        argument.endStructure();
        return QSize(w, h);
    }
    return {};
}

int even(qreal value)
{
    const int rounded = qMax(0, qRound(value));
    return rounded - rounded % 2;
}
}

Recorder::Recorder(const QString &desktop, QObject *parent)
    : QObject(parent)
    , m_desktop(desktop)
{
}

bool Recorder::active() const
{
    return m_process && m_process->state() != QProcess::NotRunning;
}

qint64 Recorder::elapsed() const
{
    return m_clock.isValid() ? m_clock.elapsed() : 0;
}

QString Recorder::restoreToken() const
{
    return m_token;
}

void Recorder::setRestoreToken(const QString &token)
{
    m_token = token;
}

QString Recorder::uniquePath(const Request &request, const QString &extension) const
{
    QDir().mkpath(request.folder);
    QString path = QStringLiteral("%1/%2.%3").arg(request.folder, request.stem, extension);
    for (int i = 2; QFileInfo::exists(path); ++i) {
        path = QStringLiteral("%1/%2 (%3).%4").arg(request.folder, request.stem).arg(i).arg(extension);
    }
    return path;
}

void Recorder::start(const Request &request)
{
    if (active()) {
        return;
    }
    m_stopping = false;
    const bool wlroots = m_desktop == QLatin1String("hyprland") || m_desktop == QLatin1String("sway");
    const bool gst = Grabber::hasTool(QStringLiteral("gst-launch-1.0"));
    if (wlroots && Grabber::hasTool(QStringLiteral("wf-recorder"))) {
        startWf(request);
    } else if (gst && Portal::hasInterface(QStringLiteral("org.freedesktop.portal.ScreenCast"))) {
        startPortal(request);
    } else if (m_desktop == QLatin1String("kde") && Grabber::hasTool(QStringLiteral("spectacle"))) {
        startSpectacle(request);
    } else if (wlroots) {
        Q_EMIT failed({QStringLiteral("Screen recording needs wf-recorder."), QStringLiteral("wf-recorder")});
    } else {
        Q_EMIT failed({QStringLiteral("Screen recording needs the GStreamer tools."), QStringLiteral("gstreamer1.0-tools gstreamer1.0-pipewire")});
    }
}

void Recorder::watch(QProcess *process, const QString &path)
{
    m_process = process;
    m_path = path;
    connect(process, &QProcess::started, this, [this]() {
        m_clock.start();
        Q_EMIT started();
    });
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            process->deleteLater();
            m_clock.invalidate();
            closeSession();
            Q_EMIT failed({QStringLiteral("The recorder could not be started."), QString()});
        }
    });
    connect(process, &QProcess::finished, this, [this, process, path]() {
        process->deleteLater();
        m_clock.invalidate();
        closeSession();
        const QByteArray log = process->readAllStandardError().trimmed();
        if (QFileInfo(path).size() > 0) {
            Q_EMIT finished(path);
        } else {
            QFile::remove(path);
            const QString detail = QString::fromUtf8(log.split('\n').constLast()).trimmed();
            Q_EMIT failed({m_stopping ? QStringLiteral("The recording was empty.") : QStringLiteral("Recording stopped: %1").arg(detail), QString()});
        }
    });
}

void Recorder::startWf(const Request &request)
{
    const QString path = uniquePath(request, QStringLiteral("mp4"));
    QStringList arguments{QStringLiteral("-f"), path};
    if (request.region) {
        arguments << QStringLiteral("-g") << QStringLiteral("%1,%2 %3x%4").arg(request.area.x()).arg(request.area.y()).arg(request.area.width()).arg(request.area.height());
    } else {
        for (QScreen *screen : QGuiApplication::screens()) {
            if (screen->geometry().contains(request.area.center())) {
                arguments << QStringLiteral("-o") << screen->name();
                break;
            }
        }
    }
    if (request.microphone) {
        arguments << QStringLiteral("--audio");
    }
    auto *process = new QProcess(this);
    process->setProcessChannelMode(QProcess::SeparateChannels);
    process->setStandardInputFile(QProcess::nullDevice());
    watch(process, path);
    process->start(QStringLiteral("wf-recorder"), arguments);
}

void Recorder::startSpectacle(const Request &request)
{
    auto *process = new QProcess(this);
    m_process = process;
    connect(process, &QProcess::finished, this, [this, process]() {
        process->deleteLater();
        m_clock.invalidate();
        Q_EMIT finished(QString());
    });
    process->start(QStringLiteral("spectacle"), {QStringLiteral("-R"), request.region ? QStringLiteral("r") : QStringLiteral("s")});
    m_clock.start();
}

void Recorder::startPortal(const Request &request)
{
    const QString interface = QStringLiteral("org.freedesktop.portal.ScreenCast");
    const QVariantMap create{{QStringLiteral("session_handle_token"), Portal::sessionToken()}};
    Portal::call(interface, QStringLiteral("CreateSession"), {}, create, [this, interface, request](uint code, const QVariantMap &results) {
        if (code != 0) {
            Q_EMIT failed({QStringLiteral("Screen recording is not available here."), QString()});
            return;
        }
        m_session = results.value(QStringLiteral("session_handle")).toString();
        QVariantMap select{
            {QStringLiteral("types"), 1u},
            {QStringLiteral("multiple"), false},
            {QStringLiteral("cursor_mode"), request.pointer ? 2u : 1u},
            {QStringLiteral("persist_mode"), 2u},
        };
        if (!m_token.isEmpty()) {
            select.insert(QStringLiteral("restore_token"), m_token);
        }
        Portal::call(interface, QStringLiteral("SelectSources"), {QVariant::fromValue(QDBusObjectPath(m_session))}, select, [this, interface, request](uint code, const QVariantMap &) {
            if (code != 0) {
                closeSession();
                Q_EMIT failed({QString(), QString(), true});
                return;
            }
            Portal::call(interface, QStringLiteral("Start"), {QVariant::fromValue(QDBusObjectPath(m_session)), QString()}, {}, [this, interface, request](uint code, const QVariantMap &results) {
                if (code != 0) {
                    closeSession();
                    Q_EMIT failed({QString(), QString(), true});
                    return;
                }
                const QString token = results.value(QStringLiteral("restore_token")).toString();
                if (!token.isEmpty() && token != m_token) {
                    m_token = token;
                    Q_EMIT tokenChanged(token);
                }
                uint node = 0;
                QSize size;
                const QDBusArgument streams = results.value(QStringLiteral("streams")).value<QDBusArgument>();
                streams.beginArray();
                while (!streams.atEnd()) {
                    uint id = 0;
                    QVariantMap properties;
                    streams.beginStructure();
                    streams >> id >> properties;
                    streams.endStructure();
                    if (node == 0) {
                        node = id;
                        size = sizeOf(properties.value(QStringLiteral("size")));
                    }
                }
                streams.endArray();
                QDBusMessage open = QDBusMessage::createMethodCall(Portal::service(), Portal::path(), interface, QStringLiteral("OpenPipeWireRemote"));
                open << QVariant::fromValue(QDBusObjectPath(m_session)) << QVariantMap();
                auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(open), this);
                connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, request, node, size](QDBusPendingCallWatcher *call) {
                    call->deleteLater();
                    const QDBusPendingReply<QDBusUnixFileDescriptor> reply = *call;
                    if (reply.isError() || node == 0) {
                        closeSession();
                        Q_EMIT failed({QStringLiteral("The screen cast could not be opened."), QString()});
                        return;
                    }
                    launchGst(request, ::dup(reply.value().fileDescriptor()), node, size);
                });
            }, this);
        }, this);
    }, this);
}

void Recorder::launchGst(const Request &request, int fd, uint node, const QSize &streamSize)
{
    const QString path = uniquePath(request, QStringLiteral("webm"));
    QStringList pipeline{QStringLiteral("-e"), QStringLiteral("pipewiresrc"), QStringLiteral("fd=3"), QStringLiteral("path=%1").arg(node), QStringLiteral("do-timestamp=true"), QStringLiteral("keepalive-time=1000"), QStringLiteral("always-copy=true"), QStringLiteral("!"), QStringLiteral("videoconvert"), QStringLiteral("!")};
    if (request.region && streamSize.isValid() && request.screen.width() > 0) {
        const qreal scale = qreal(streamSize.width()) / request.screen.width();
        const QRect area = request.area.intersected(request.screen).translated(-request.screen.topLeft());
        const int left = even(area.x() * scale);
        const int top = even(area.y() * scale);
        const int width = even(area.width() * scale);
        const int height = even(area.height() * scale);
        pipeline << QStringLiteral("videocrop") << QStringLiteral("left=%1").arg(left) << QStringLiteral("top=%1").arg(top)
                 << QStringLiteral("right=%1").arg(qMax(0, streamSize.width() - left - width)) << QStringLiteral("bottom=%1").arg(qMax(0, streamSize.height() - top - height))
                 << QStringLiteral("!") << QStringLiteral("videoconvert") << QStringLiteral("!");
    }
    const int threads = qBound(2, QThread::idealThreadCount(), 8);
    pipeline << QStringLiteral("video/x-raw,format=I420") << QStringLiteral("!") << QStringLiteral("queue") << QStringLiteral("!")
             << QStringLiteral("vp8enc") << QStringLiteral("deadline=1") << QStringLiteral("cpu-used=8") << QStringLiteral("threads=%1").arg(threads)
             << QStringLiteral("target-bitrate=8000000") << QStringLiteral("min-quantizer=4") << QStringLiteral("max-quantizer=40")
             << QStringLiteral("!") << QStringLiteral("queue") << QStringLiteral("!") << QStringLiteral("webmmux") << QStringLiteral("name=mux")
             << QStringLiteral("!") << QStringLiteral("filesink") << QStringLiteral("location=%1").arg(path);
    if (request.microphone) {
        pipeline << QStringLiteral("pulsesrc") << QStringLiteral("do-timestamp=true") << QStringLiteral("!") << QStringLiteral("audioconvert") << QStringLiteral("!")
                 << QStringLiteral("audioresample") << QStringLiteral("!") << QStringLiteral("opusenc") << QStringLiteral("!") << QStringLiteral("queue")
                 << QStringLiteral("!") << QStringLiteral("mux.");
    }
    auto *process = new QProcess(this);
    process->setStandardInputFile(QProcess::nullDevice());
    process->setStandardOutputFile(QProcess::nullDevice());
    process->setChildProcessModifier([fd]() {
        ::dup2(fd, 3);
    });
    watch(process, path);
    process->start(QStringLiteral("gst-launch-1.0"), pipeline);
    ::close(fd);
}

void Recorder::stop()
{
    if (!active()) {
        return;
    }
    m_stopping = true;
    const qint64 pid = m_process->processId();
    if (pid > 0) {
        ::kill(pid_t(pid), SIGINT);
    }
    QPointer<QProcess> process = m_process;
    QTimer::singleShot(8000, this, [process]() {
        if (process && process->state() != QProcess::NotRunning) {
            process->terminate();
        }
    });
}

void Recorder::closeSession()
{
    if (m_session.isEmpty()) {
        return;
    }
    QDBusMessage close = QDBusMessage::createMethodCall(Portal::service(), m_session, QStringLiteral("org.freedesktop.portal.Session"), QStringLiteral("Close"));
    QDBusConnection::sessionBus().asyncCall(close);
    m_session.clear();
}
