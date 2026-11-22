#include "settings.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QSaveFile>
#include <QStandardPaths>
#include <QSysInfo>

#include <pwd.h>
#include <unistd.h>

QString Settings::path()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/kwick/nearby.json");
}

QString Settings::dataDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/kwick/nearby");
}

QString Settings::defaultAlias()
{
    QString first;
    if (const passwd *pw = getpwuid(getuid())) {
        QString gecos = QString::fromUtf8(pw->pw_gecos).section(QLatin1Char(','), 0, 0).trimmed();
        if (gecos.isEmpty() || gecos.contains(QLatin1String("KwickOS"))) {
            gecos = QString::fromUtf8(pw->pw_name);
        }
        first = gecos.section(QLatin1Char(' '), 0, 0);
        if (!first.isEmpty()) {
            first[0] = first.at(0).toUpper();
        }
    }
    QString machine = QStringLiteral("KwickOS");
    QFile chassis(QStringLiteral("/sys/class/dmi/id/chassis_type"));
    if (chassis.open(QIODevice::ReadOnly)) {
        const int type = chassis.readAll().trimmed().toInt();
        if (type == 8 || type == 9 || type == 10 || type == 14 || type == 31 || type == 32) {
            machine = QStringLiteral("KwickOS Laptop");
        }
    }
    if (first.isEmpty() || first == QLatin1String("Root")) {
        return machine;
    }
    return first + QStringLiteral("’s ") + machine;
}

QString Settings::defaultFolder()
{
    QString dir = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    if (dir.isEmpty()) {
        dir = QDir::homePath() + QStringLiteral("/Downloads");
    }
    return dir;
}

void Settings::load()
{
    alias.clear();
    visibility = QStringLiteral("off");
    everyoneUntil = 0;
    folder.clear();
    pin.clear();
    requirePin = false;
    known.clear();
    QFile file(path());
    if (file.open(QIODevice::ReadOnly)) {
        const QJsonObject o = QJsonDocument::fromJson(file.readAll()).object();
        alias = o.value(QLatin1String("alias")).toString().trimmed();
        visibility = o.value(QLatin1String("visibility")).toString(QStringLiteral("off"));
        everyoneUntil = static_cast<qint64>(o.value(QLatin1String("everyoneUntil")).toDouble());
        folder = o.value(QLatin1String("folder")).toString();
        pin = o.value(QLatin1String("pin")).toString();
        requirePin = o.value(QLatin1String("requirePin")).toBool();
        const QJsonArray list = o.value(QLatin1String("known")).toArray();
        for (const QJsonValue &v : list) {
            const QJsonObject d = v.toObject();
            KnownDevice k;
            k.fingerprint = d.value(QLatin1String("fingerprint")).toString().toUpper();
            k.alias = d.value(QLatin1String("alias")).toString();
            k.model = d.value(QLatin1String("model")).toString();
            k.type = d.value(QLatin1String("type")).toString();
            k.seen = static_cast<qint64>(d.value(QLatin1String("seen")).toDouble());
            if (!k.fingerprint.isEmpty()) {
                known.append(k);
            }
        }
    }
    if (visibility != QLatin1String("contacts") && visibility != QLatin1String("everyone")) {
        visibility = QStringLiteral("off");
    }
    if (alias.isEmpty()) {
        alias = defaultAlias();
    }
    if (folder.isEmpty()) {
        folder = defaultFolder();
    }
    if (pin.isEmpty()) {
        requirePin = false;
    }
}

bool Settings::save() const
{
    QDir().mkpath(QFileInfo(path()).absolutePath());
    QSaveFile file(path());
    if (!file.open(QIODevice::WriteOnly)) {
        return false;
    }
    file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    file.write(QJsonDocument(toJson()).toJson(QJsonDocument::Indented));
    return file.commit();
}

QString Settings::effectiveVisibility(qint64 now) const
{
    if (visibility == QLatin1String("everyone") && everyoneUntil > 0 && now >= everyoneUntil) {
        return QStringLiteral("contacts");
    }
    return visibility;
}

bool Settings::isKnown(const QString &fingerprint) const
{
    const QString fp = fingerprint.toUpper();
    for (const KnownDevice &k : known) {
        if (k.fingerprint == fp) {
            return true;
        }
    }
    return false;
}

void Settings::remember(const KnownDevice &device)
{
    KnownDevice d = device;
    d.fingerprint = d.fingerprint.toUpper();
    for (KnownDevice &k : known) {
        if (k.fingerprint == d.fingerprint) {
            k = d;
            return;
        }
    }
    known.append(d);
}

bool Settings::forget(const QString &fingerprint)
{
    const QString fp = fingerprint.toUpper();
    for (int i = 0; i < known.size(); ++i) {
        if (known.at(i).fingerprint == fp) {
            known.removeAt(i);
            return true;
        }
    }
    return false;
}

QJsonObject Settings::toJson() const
{
    QJsonObject o;
    o.insert(QLatin1String("alias"), alias);
    o.insert(QLatin1String("visibility"), visibility);
    o.insert(QLatin1String("everyoneUntil"), static_cast<double>(everyoneUntil));
    o.insert(QLatin1String("folder"), folder);
    o.insert(QLatin1String("pin"), pin);
    o.insert(QLatin1String("requirePin"), requirePin);
    QJsonArray list;
    for (const KnownDevice &k : known) {
        QJsonObject d;
        d.insert(QLatin1String("fingerprint"), k.fingerprint);
        d.insert(QLatin1String("alias"), k.alias);
        d.insert(QLatin1String("model"), k.model);
        d.insert(QLatin1String("type"), k.type);
        d.insert(QLatin1String("seen"), static_cast<double>(k.seen));
        list.append(d);
    }
    o.insert(QLatin1String("known"), list);
    return o;
}
