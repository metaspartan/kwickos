#include "discovery.h"

#include "identity.h"

#include <QJsonDocument>
#include <QNetworkAccessManager>
#include <QNetworkDatagram>
#include <QNetworkInterface>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QPointer>
#include <QSslCertificate>
#include <QUdpSocket>

namespace Http
{
QString url(const Device &device, const QString &route)
{
    return QStringLiteral("%1://%2:%3%4%5").arg(device.protocol, Util::urlHost(device.ip)).arg(device.port).arg(QLatin1String(Protocol::Api), route);
}

QString peerFingerprint(QNetworkReply *reply)
{
    return Identity::fingerprintOf(reply->sslConfiguration().peerCertificate());
}

void pin(QNetworkReply *reply, const QString &expected)
{
    QPointer<QNetworkReply> guard(reply);
    QObject::connect(reply, &QNetworkReply::encrypted, reply, [guard, expected]() {
        if (guard && peerFingerprint(guard).compare(expected, Qt::CaseInsensitive) != 0) {
            qWarning("kwick-nearby: certificate of %s does not match its fingerprint", qPrintable(guard->url().host()));
            guard->setProperty("kwickPinFailed", true);
            guard->abort();
        }
    });
}

bool pinFailed(QNetworkReply *reply)
{
    return reply->property("kwickPinFailed").toBool();
}

QNetworkReply *post(QNetworkAccessManager *nam, const QSslConfiguration &tls, const QString &target, const QByteArray &body, const QString &expected, int timeoutMs)
{
    QNetworkRequest request{QUrl(target)};
    request.setHeader(QNetworkRequest::ContentTypeHeader, QByteArrayLiteral("application/json"));
    request.setHeader(QNetworkRequest::UserAgentHeader, QByteArrayLiteral("KwickOS-Nearby/1.0"));
    request.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
    request.setSslConfiguration(tls);
    if (timeoutMs > 0) {
        request.setTransferTimeout(timeoutMs);
    }
    QNetworkReply *reply = nam->post(request, body);
    if (!expected.isEmpty() && target.startsWith(QLatin1String("https:"))) {
        pin(reply, expected);
    }
    return reply;
}
}

Discovery::Discovery(QNetworkAccessManager *nam, QObject *parent)
    : QObject(parent)
    , m_nam(nam)
{
    m_rejoin.setInterval(15000);
    connect(&m_rejoin, &QTimer::timeout, this, &Discovery::joinAll);
}

void Discovery::setSelf(const SelfInfo &self, const QSslConfiguration &tls)
{
    m_self = self;
    m_tls = tls;
}

bool Discovery::running() const
{
    return m_socket != nullptr;
}

bool Discovery::start()
{
    if (m_socket) {
        return true;
    }
    m_socket = new QUdpSocket(this);
    if (!m_socket->bind(QHostAddress::AnyIPv4, Protocol::Port, QUdpSocket::ShareAddress | QUdpSocket::ReuseAddressHint)) {
        qWarning("kwick-nearby: cannot bind UDP %u: %s", Protocol::Port, qPrintable(m_socket->errorString()));
        delete m_socket;
        m_socket = nullptr;
        return false;
    }
    m_socket->setSocketOption(QAbstractSocket::MulticastTtlOption, 1);
    m_socket->setSocketOption(QAbstractSocket::MulticastLoopbackOption, 0);
    connect(m_socket, &QUdpSocket::readyRead, this, &Discovery::readPending);
    m_joined.clear();
    joinAll();
    m_rejoin.start();
    return true;
}

void Discovery::stop()
{
    m_rejoin.stop();
    m_scanQueue.clear();
    if (m_socket) {
        m_socket->close();
        delete m_socket;
        m_socket = nullptr;
    }
    m_joined.clear();
}

void Discovery::joinAll()
{
    if (!m_socket) {
        return;
    }
    const QHostAddress group(QLatin1String(Protocol::MulticastGroup));
    QSet<QString> now;
    const auto interfaces = QNetworkInterface::allInterfaces();
    for (const QNetworkInterface &iface : interfaces) {
        const auto flags = iface.flags();
        if (!(flags & QNetworkInterface::IsUp) || !(flags & QNetworkInterface::IsRunning) || (flags & QNetworkInterface::IsLoopBack) || !(flags & QNetworkInterface::CanMulticast)) {
            continue;
        }
        bool v4 = false;
        for (const QNetworkAddressEntry &entry : iface.addressEntries()) {
            v4 = v4 || entry.ip().protocol() == QAbstractSocket::IPv4Protocol;
        }
        if (!v4) {
            continue;
        }
        const QString key = iface.name() + QLatin1Char('#') + QString::number(iface.index());
        now.insert(key);
        if (!m_joined.contains(key)) {
            m_socket->joinMulticastGroup(group, iface);
        }
    }
    m_joined = now;
}

void Discovery::sendMulticast(bool announce)
{
    if (!m_socket) {
        return;
    }
    const QByteArray payload = QJsonDocument(m_self.announceJson(announce)).toJson(QJsonDocument::Compact);
    const QHostAddress group(QLatin1String(Protocol::MulticastGroup));
    const auto interfaces = QNetworkInterface::allInterfaces();
    bool sent = false;
    for (const QNetworkInterface &iface : interfaces) {
        const QString key = iface.name() + QLatin1Char('#') + QString::number(iface.index());
        if (!m_joined.contains(key)) {
            continue;
        }
        m_socket->setMulticastInterface(iface);
        sent = m_socket->writeDatagram(payload, group, Protocol::Port) > 0 || sent;
    }
    if (!sent) {
        m_socket->writeDatagram(payload, group, Protocol::Port);
    }
}

void Discovery::announce()
{
    if (!m_socket) {
        return;
    }
    joinAll();
    for (int delay : {100, 500, 2000}) {
        QTimer::singleShot(delay, this, [this]() { sendMulticast(true); });
    }
}

void Discovery::readPending()
{
    while (m_socket && m_socket->hasPendingDatagrams()) {
        const QNetworkDatagram datagram = m_socket->receiveDatagram(65536);
        if (datagram.data().size() > 8192) {
            continue;
        }
        const QJsonObject o = QJsonDocument::fromJson(datagram.data()).object();
        if (o.isEmpty()) {
            continue;
        }
        const QString ip = Util::normalizeIp(datagram.senderAddress());
        Device d = Device::fromJson(o, ip);
        if (d.fingerprint.isEmpty() || d.fingerprint.compare(m_self.fingerprint, Qt::CaseInsensitive) == 0) {
            continue;
        }
        const bool isAnnounce = o.value(QLatin1String("announce")).toBool(o.value(QLatin1String("announcement")).toBool());
        if (isAnnounce) {
            if (shouldAnswer && shouldAnswer(d)) {
                registerWith(ip, d.port, d.protocol, d.protocol == QLatin1String("https") ? d.fingerprint : QString(), true);
            }
        } else {
            Q_EMIT found(d);
        }
    }
}

void Discovery::registerWith(const QString &ip, quint16 port, const QString &protocol, const QString &expected, bool fallbackMulticast)
{
    const QString key = ip + QLatin1Char(':') + QString::number(port);
    if (m_dialing.contains(key)) {
        return;
    }
    m_dialing.insert(key);
    Device target;
    target.ip = ip;
    target.port = port;
    target.protocol = protocol;
    const QByteArray body = QJsonDocument(m_self.registerJson()).toJson(QJsonDocument::Compact);
    QNetworkReply *reply = Http::post(m_nam, m_tls, Http::url(target, QStringLiteral("register")), body, expected, fallbackMulticast ? 5000 : 2500);
    connect(reply, &QNetworkReply::finished, this, [this, reply, key, ip, port, protocol, expected, fallbackMulticast]() {
        reply->deleteLater();
        m_dialing.remove(key);
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (reply->error() == QNetworkReply::NoError && status == 200) {
            const QJsonObject o = QJsonDocument::fromJson(reply->readAll()).object();
            Device d = Device::fromJson(o, ip);
            d.port = port;
            d.protocol = protocol;
            if (protocol == QLatin1String("https")) {
                const QString cert = Http::peerFingerprint(reply);
                if (cert.isEmpty() || (!expected.isEmpty() && cert.compare(expected, Qt::CaseInsensitive) != 0)) {
                    return;
                }
                d.fingerprint = cert;
                d.verified = true;
            }
            if (!d.fingerprint.isEmpty() && d.fingerprint.compare(m_self.fingerprint, Qt::CaseInsensitive) != 0) {
                Q_EMIT found(d);
            }
            return;
        }
        if (fallbackMulticast && status == 0) {
            sendMulticast(false);
        }
    });
}

void Discovery::scan()
{
    if (!m_scanQueue.isEmpty() || m_scanActive > 0) {
        return;
    }
    QSet<QString> mine;
    QStringList hosts;
    const auto interfaces = QNetworkInterface::allInterfaces();
    for (const QNetworkInterface &iface : interfaces) {
        const auto flags = iface.flags();
        if (!(flags & QNetworkInterface::IsUp) || (flags & QNetworkInterface::IsLoopBack)) {
            continue;
        }
        const QString name = iface.name();
        if (name.startsWith(QLatin1String("docker")) || name.startsWith(QLatin1String("veth")) || name.startsWith(QLatin1String("virbr")) || name.startsWith(QLatin1String("br-"))) {
            continue;
        }
        for (const QNetworkAddressEntry &entry : iface.addressEntries()) {
            if (entry.ip().protocol() != QAbstractSocket::IPv4Protocol || entry.prefixLength() < 16 || entry.prefixLength() > 30) {
                continue;
            }
            const quint32 self = entry.ip().toIPv4Address();
            mine.insert(entry.ip().toString());
            const quint32 base = self & 0xffffff00u;
            for (quint32 i = 1; i < 255; ++i) {
                const QString host = QHostAddress(base | i).toString();
                if ((base | i) != self && !hosts.contains(host)) {
                    hosts.append(host);
                }
            }
        }
    }
    for (const QString &h : std::as_const(hosts)) {
        if (!mine.contains(h)) {
            m_scanQueue.append(h);
        }
    }
    pumpScan();
}

void Discovery::pumpScan()
{
    while (m_scanActive < 48 && !m_scanQueue.isEmpty()) {
        const QString ip = m_scanQueue.takeFirst();
        Device target;
        target.ip = ip;
        ++m_scanActive;
        const QByteArray body = QJsonDocument(m_self.registerJson()).toJson(QJsonDocument::Compact);
        QNetworkReply *reply = Http::post(m_nam, m_tls, Http::url(target, QStringLiteral("register")), body, QString(), 1800);
        connect(reply, &QNetworkReply::finished, this, [this, reply, ip]() {
            reply->deleteLater();
            --m_scanActive;
            const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            if (reply->error() == QNetworkReply::NoError && status == 200) {
                const QJsonObject o = QJsonDocument::fromJson(reply->readAll()).object();
                Device d = Device::fromJson(o, ip);
                d.port = Protocol::Port;
                d.protocol = QStringLiteral("https");
                d.fingerprint = Http::peerFingerprint(reply);
                d.verified = true;
                if (!d.fingerprint.isEmpty() && d.fingerprint.compare(m_self.fingerprint, Qt::CaseInsensitive) != 0) {
                    Q_EMIT found(d);
                }
            }
            pumpScan();
        });
    }
}
