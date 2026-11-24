#include "identity.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QSaveFile>

#include <openssl/bio.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/rand.h>
#include <openssl/x509.h>

#include <memory>

namespace
{
QByteArray bioBytes(BIO *bio)
{
    char *data = nullptr;
    const long size = BIO_get_mem_data(bio, &data);
    return size > 0 ? QByteArray(data, static_cast<qsizetype>(size)) : QByteArray();
}

bool generate(QByteArray &certPem, QByteArray &keyPem)
{
    std::unique_ptr<EVP_PKEY, decltype(&EVP_PKEY_free)> pkey(EVP_RSA_gen(2048), EVP_PKEY_free);
    if (!pkey) {
        return false;
    }
    std::unique_ptr<X509, decltype(&X509_free)> x509(X509_new(), X509_free);
    if (!x509) {
        return false;
    }
    X509_set_version(x509.get(), 2);
    unsigned char serial[16];
    RAND_bytes(serial, sizeof serial);
    serial[0] &= 0x7f;
    std::unique_ptr<BIGNUM, decltype(&BN_free)> bn(BN_bin2bn(serial, sizeof serial, nullptr), BN_free);
    BN_to_ASN1_INTEGER(bn.get(), X509_get_serialNumber(x509.get()));
    X509_gmtime_adj(X509_getm_notBefore(x509.get()), -86400L * 2);
    X509_time_adj_ex(X509_getm_notAfter(x509.get()), 365 * 30, 0, nullptr);
    X509_set_pubkey(x509.get(), pkey.get());
    X509_NAME *name = X509_get_subject_name(x509.get());
    X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC, reinterpret_cast<const unsigned char *>("KwickOS Send Nearby"), -1, -1, 0);
    X509_set_issuer_name(x509.get(), name);
    if (X509_sign(x509.get(), pkey.get(), EVP_sha256()) <= 0) {
        return false;
    }
    std::unique_ptr<BIO, decltype(&BIO_free)> certBio(BIO_new(BIO_s_mem()), BIO_free);
    std::unique_ptr<BIO, decltype(&BIO_free)> keyBio(BIO_new(BIO_s_mem()), BIO_free);
    if (!PEM_write_bio_X509(certBio.get(), x509.get()) || !PEM_write_bio_PrivateKey(keyBio.get(), pkey.get(), nullptr, nullptr, 0, nullptr, nullptr)) {
        return false;
    }
    certPem = bioBytes(certBio.get());
    keyPem = bioBytes(keyBio.get());
    return !certPem.isEmpty() && !keyPem.isEmpty();
}

bool writePrivate(const QString &path, const QByteArray &data)
{
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        return false;
    }
    file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    file.write(data);
    return file.commit();
}
}

QString Identity::fingerprintOf(const QSslCertificate &certificate)
{
    if (certificate.isNull()) {
        return {};
    }
    return QString::fromLatin1(QCryptographicHash::hash(certificate.toDer(), QCryptographicHash::Sha256).toHex().toUpper());
}

bool Identity::load(const QString &dir)
{
    QDir().mkpath(dir);
    QFile::setPermissions(dir, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner);
    const QString certPath = dir + QStringLiteral("/cert.pem");
    const QString keyPath = dir + QStringLiteral("/key.pem");
    QByteArray certPem;
    QByteArray keyPem;
    QFile certFile(certPath);
    QFile keyFile(keyPath);
    if (certFile.open(QIODevice::ReadOnly) && keyFile.open(QIODevice::ReadOnly)) {
        certPem = certFile.readAll();
        keyPem = keyFile.readAll();
    }
    certificate = QSslCertificate(certPem, QSsl::Pem);
    key = QSslKey(keyPem, QSsl::Rsa, QSsl::Pem, QSsl::PrivateKey);
    if (certificate.isNull() || key.isNull() || certificate.expiryDate() < QDateTime::currentDateTimeUtc().addDays(30)) {
        if (!generate(certPem, keyPem) || !writePrivate(keyPath, keyPem) || !writePrivate(certPath, certPem)) {
            return false;
        }
        certificate = QSslCertificate(certPem, QSsl::Pem);
        key = QSslKey(keyPem, QSsl::Rsa, QSsl::Pem, QSsl::PrivateKey);
    }
    fingerprint = fingerprintOf(certificate);
    return !certificate.isNull() && !key.isNull();
}

QSslConfiguration Identity::serverConfiguration() const
{
    QSslConfiguration config = QSslConfiguration::defaultConfiguration();
    config.setLocalCertificate(certificate);
    config.setPrivateKey(key);
    config.setProtocol(QSsl::TlsV1_2OrLater);
    config.setPeerVerifyMode(QSslSocket::QueryPeer);
    return config;
}

QSslConfiguration Identity::clientConfiguration() const
{
    QSslConfiguration config = QSslConfiguration::defaultConfiguration();
    config.setLocalCertificate(certificate);
    config.setPrivateKey(key);
    config.setProtocol(QSsl::TlsV1_2OrLater);
    config.setPeerVerifyMode(QSslSocket::VerifyNone);
    return config;
}
