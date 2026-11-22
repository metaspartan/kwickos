#pragma once

#include <QSslCertificate>
#include <QSslConfiguration>
#include <QSslKey>
#include <QString>

class Identity
{
public:
    bool load(const QString &dir);
    QSslConfiguration serverConfiguration() const;
    QSslConfiguration clientConfiguration() const;
    static QString fingerprintOf(const QSslCertificate &certificate);

    QSslCertificate certificate;
    QSslKey key;
    QString fingerprint;
};
