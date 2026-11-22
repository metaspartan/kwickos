#include "protocol.h"

#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QRandomGenerator>

Device Device::fromJson(const QJsonObject &o, const QString &ip)
{
    Device d;
    d.fingerprint = o.value(QLatin1String("fingerprint")).toString();
    d.alias = o.value(QLatin1String("alias")).toString().trimmed().left(64);
    d.model = o.value(QLatin1String("deviceModel")).toString().trimmed().left(48);
    d.type = o.value(QLatin1String("deviceType")).toString(QStringLiteral("desktop"));
    if (d.type != QLatin1String("mobile") && d.type != QLatin1String("desktop") && d.type != QLatin1String("web") && d.type != QLatin1String("headless") && d.type != QLatin1String("server")) {
        d.type = QStringLiteral("desktop");
    }
    d.version = o.value(QLatin1String("version")).toString(QStringLiteral("2.0"));
    const int port = o.value(QLatin1String("port")).toInt(Protocol::Port);
    d.port = port > 0 && port < 65536 ? static_cast<quint16>(port) : Protocol::Port;
    d.protocol = o.value(QLatin1String("protocol")).toString(QStringLiteral("https")) == QLatin1String("http") ? QStringLiteral("http") : QStringLiteral("https");
    d.download = o.value(QLatin1String("download")).toBool();
    d.ip = ip;
    d.seen = QDateTime::currentMSecsSinceEpoch();
    if (d.alias.isEmpty()) {
        d.alias = QStringLiteral("Unknown Device");
    }
    return d;
}

bool Device::valid() const
{
    return !fingerprint.isEmpty() && !ip.isEmpty();
}

QJsonObject SelfInfo::infoJson() const
{
    QJsonObject o;
    o.insert(QLatin1String("alias"), alias);
    o.insert(QLatin1String("version"), QLatin1String(Protocol::Version));
    o.insert(QLatin1String("deviceModel"), QStringLiteral("KwickOS"));
    o.insert(QLatin1String("deviceType"), QStringLiteral("desktop"));
    o.insert(QLatin1String("fingerprint"), fingerprint);
    o.insert(QLatin1String("download"), false);
    return o;
}

QJsonObject SelfInfo::registerJson() const
{
    QJsonObject o = infoJson();
    o.insert(QLatin1String("port"), port);
    o.insert(QLatin1String("protocol"), QStringLiteral("https"));
    return o;
}

QJsonObject SelfInfo::announceJson(bool announce) const
{
    QJsonObject o = registerJson();
    o.insert(QLatin1String("announce"), announce);
    return o;
}

namespace Util
{
QString normalizeIp(const QHostAddress &address)
{
    bool ok = false;
    const quint32 v4 = address.toIPv4Address(&ok);
    if (ok) {
        return QHostAddress(v4).toString();
    }
    QHostAddress copy(address);
    copy.setScopeId(QString());
    return copy.toString();
}

QString urlHost(const QString &ip)
{
    return ip.contains(QLatin1Char(':')) ? QStringLiteral("[") + ip + QStringLiteral("]") : ip;
}

QString mimeFor(const QString &path)
{
    static QMimeDatabase db;
    const QString name = db.mimeTypeForFile(path).name();
    return name.isEmpty() ? QStringLiteral("application/octet-stream") : name;
}

QString sanitizeRelative(const QString &name)
{
    QString n = name;
    n.replace(QLatin1Char('\\'), QLatin1Char('/'));
    QStringList out;
    const QStringList parts = n.split(QLatin1Char('/'), Qt::SkipEmptyParts);
    for (QString part : parts) {
        part = part.trimmed();
        QString clean;
        for (const QChar c : std::as_const(part)) {
            if (c.unicode() < 0x20 || c == QLatin1Char(':') || c == QLatin1Char('*') || c == QLatin1Char('?') || c == QLatin1Char('"') || c == QLatin1Char('<') || c == QLatin1Char('>') || c == QLatin1Char('|')) {
                clean.append(QLatin1Char('_'));
            } else {
                clean.append(c);
            }
        }
        while (clean.startsWith(QLatin1Char('.'))) {
            clean.remove(0, 1);
        }
        clean = clean.left(200);
        if (clean.isEmpty() || clean == QLatin1String("..")) {
            continue;
        }
        out.append(clean);
    }
    if (out.size() > 16) {
        out = out.mid(out.size() - 16);
    }
    if (out.isEmpty()) {
        out.append(QStringLiteral("file"));
    }
    return out.join(QLatin1Char('/'));
}

QString uniquePath(const QString &dir, const QString &relative)
{
    const QString top = relative.section(QLatin1Char('/'), 0, 0);
    const bool nested = relative.contains(QLatin1Char('/'));
    if (nested) {
        return QDir(dir).filePath(relative);
    }
    QFileInfo info(QDir(dir).filePath(top));
    if (!info.exists()) {
        return info.filePath();
    }
    const QString base = info.completeBaseName();
    const QString suffix = info.suffix().isEmpty() ? QString() : QStringLiteral(".") + info.suffix();
    for (int i = 2; i < 10000; ++i) {
        const QString candidate = QDir(dir).filePath(QStringLiteral("%1 %2%3").arg(base).arg(i).arg(suffix));
        if (!QFileInfo::exists(candidate)) {
            return candidate;
        }
    }
    return QDir(dir).filePath(base + QStringLiteral(" ") + randomToken().left(6) + suffix);
}

QString randomToken()
{
    quint64 a = QRandomGenerator::system()->generate64();
    quint64 b = QRandomGenerator::system()->generate64();
    return QString::number(a, 16).rightJustified(16, QLatin1Char('0')) + QString::number(b, 16).rightJustified(16, QLatin1Char('0'));
}

QString iso(qint64 msecs)
{
    return QDateTime::fromMSecsSinceEpoch(msecs).toUTC().toString(Qt::ISODateWithMs);
}

bool isMessage(const QString &fileType, const QString &preview, qint64 size, int count)
{
    if (count != 1 || preview.isNull()) {
        return false;
    }
    const bool text = fileType.startsWith(QLatin1String("text/")) || fileType == QLatin1String("text");
    return text && size <= Protocol::MessageLimit && preview.toUtf8().size() <= Protocol::MessageLimit;
}
}
