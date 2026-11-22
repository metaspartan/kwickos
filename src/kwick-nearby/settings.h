#pragma once

#include <QJsonArray>
#include <QJsonObject>
#include <QString>

struct KnownDevice
{
    QString fingerprint;
    QString alias;
    QString model;
    QString type;
    qint64 seen = 0;
};

class Settings
{
public:
    static QString path();
    static QString dataDir();
    static QString defaultAlias();
    static QString defaultFolder();

    void load();
    bool save() const;

    QString effectiveVisibility(qint64 now) const;
    bool isKnown(const QString &fingerprint) const;
    void remember(const KnownDevice &device);
    bool forget(const QString &fingerprint);
    QJsonObject toJson() const;

    QString alias;
    QString visibility = QStringLiteral("off");
    qint64 everyoneUntil = 0;
    QString folder;
    QString pin;
    bool requirePin = false;
    QList<KnownDevice> known;
};

constexpr qint64 EveryoneWindowMs = 10 * 60 * 1000;
