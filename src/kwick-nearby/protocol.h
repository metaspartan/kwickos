#pragma once

#include <QHostAddress>
#include <QJsonObject>
#include <QString>

namespace Protocol
{
constexpr quint16 Port = 53317;
inline const char *MulticastGroup = "224.0.0.167";
inline const char *Version = "2.1";
inline const char *Api = "/api/localsend/v2/";
constexpr qint64 MessageLimit = 16 * 1024;
}

struct Device
{
    QString fingerprint;
    QString alias;
    QString model;
    QString type;
    QString version;
    QString ip;
    quint16 port = Protocol::Port;
    QString protocol = QStringLiteral("https");
    bool download = false;
    bool verified = false;
    qint64 seen = 0;

    static Device fromJson(const QJsonObject &o, const QString &ip);
    bool valid() const;
};

struct SelfInfo
{
    QString alias;
    QString fingerprint;
    quint16 port = Protocol::Port;

    QJsonObject registerJson() const;
    QJsonObject infoJson() const;
    QJsonObject announceJson(bool announce) const;
};

namespace Util
{
QString normalizeIp(const QHostAddress &address);
QString urlHost(const QString &ip);
QString mimeFor(const QString &path);
QString sanitizeRelative(const QString &name);
QString uniquePath(const QString &dir, const QString &relative);
QString randomToken();
QString iso(qint64 msecs);
bool isMessage(const QString &fileType, const QString &preview, qint64 size, int count);
}
