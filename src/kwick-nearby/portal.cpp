#include "portal.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QPointer>
#include <QRandomGenerator>

PortalRequest::PortalRequest(const QString &path, Done done, QObject *parent)
    : QObject(parent)
    , m_path(path)
    , m_done(std::move(done))
{
    QDBusConnection::sessionBus().connect(Portal::service(), m_path, QStringLiteral("org.freedesktop.portal.Request"), QStringLiteral("Response"), this, SLOT(response(uint, QVariantMap)));
}

void PortalRequest::response(uint code, const QVariantMap &results)
{
    QDBusConnection::sessionBus().disconnect(Portal::service(), m_path, QStringLiteral("org.freedesktop.portal.Request"), QStringLiteral("Response"), this, SLOT(response(uint, QVariantMap)));
    if (m_done) {
        Done done = std::move(m_done);
        m_done = nullptr;
        done(code, results);
    }
    deleteLater();
}

namespace Portal
{
QString service()
{
    return QStringLiteral("org.freedesktop.portal.Desktop");
}

QString path()
{
    return QStringLiteral("/org/freedesktop/portal/desktop");
}

QString sessionToken()
{
    return QStringLiteral("kwicknearby%1").arg(QRandomGenerator::global()->generate());
}

bool hasInterface(const QString &interface)
{
    QDBusMessage message = QDBusMessage::createMethodCall(service(), path(), QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
    message << interface << QStringLiteral("version");
    const QDBusMessage reply = QDBusConnection::sessionBus().call(message, QDBus::Block, 1500);
    return reply.type() == QDBusMessage::ReplyMessage;
}

void call(const QString &interface, const QString &method, const QVariantList &leading, QVariantMap options, PortalRequest::Done done, QObject *parent)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    const QString token = sessionToken();
    options.insert(QStringLiteral("handle_token"), token);
    QString sender = bus.baseService().mid(1);
    sender.replace(QLatin1Char('.'), QLatin1Char('_'));
    const QString requestPath = QStringLiteral("/org/freedesktop/portal/desktop/request/%1/%2").arg(sender, token);
    auto *request = new PortalRequest(requestPath, done, parent);
    QDBusMessage message = QDBusMessage::createMethodCall(service(), path(), interface, method);
    QVariantList arguments = leading;
    arguments << options;
    message.setArguments(arguments);
    auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(message, 600000), parent);
    QObject::connect(watcher, &QDBusPendingCallWatcher::finished, parent, [request = QPointer<PortalRequest>(request), watcher]() {
        watcher->deleteLater();
        if (watcher->isError() && request) {
            request->response(2, {{QStringLiteral("error"), watcher->error().message()}});
        }
    });
}
}
