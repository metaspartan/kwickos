#pragma once

#include "protocol.h"

#include <QCryptographicHash>
#include <QElapsedTimer>
#include <QFile>
#include <QHash>
#include <QJsonArray>
#include <QObject>
#include <QPointer>
#include <QSet>
#include <QSslConfiguration>
#include <QTimer>

#include <functional>
#include <memory>
#include <unordered_map>

class TlsServer;
class Connection;

struct IncomingFile
{
    QString id;
    QString name;
    QString type;
    QString sha256;
    QString preview;
    qint64 size = 0;
    qint64 modified = 0;
    QString token;
    QString path;
    qint64 received = 0;
    int state = 0;
};

struct IncomingSession
{
    QString id;
    QString ip;
    Device sender;
    QString certFingerprint;
    QHash<QString, IncomingFile> files;
    QStringList order;
    QString folder;
    QHash<QString, QString> tops;
    QPointer<Connection> pending;
    bool active = false;
    qint64 total = 0;
    QStringList saved;
};

class Server : public QObject
{
    Q_OBJECT

public:
    explicit Server(QObject *parent = nullptr);
    ~Server() override;

    bool start(const QSslConfiguration &config, quint16 port);
    void stop();
    bool running() const;
    quint16 port() const;
    void setSelf(const SelfInfo &self);
    void setPin(const QString &pin);
    bool busy() const;

    void accept(const QString &sessionId, const QString &folder);
    void decline(const QString &sessionId, int status);
    void finishMessage(const QString &sessionId);
    void cancelIncoming(const QString &sessionId);

    std::function<bool(const QString &fingerprint)> allowRegister;
    std::function<QString(const QString &certFingerprint)> refuseUpload;

    void handle(Connection *connection);
    int beginUpload(Connection *connection);
    bool uploadData(Connection *connection, const char *data, qint64 size);
    int finishUpload(Connection *connection);
    void abortUpload(Connection *connection);
    void connectionGone(Connection *connection);

Q_SIGNALS:
    void registered(const Device &device);
    void request(const QString &sessionId, const Device &sender, const QString &certFingerprint, const QJsonArray &files, qint64 total, bool message);
    void progress(const QString &sessionId, qint64 received, qint64 total, int done, int count);
    void finished(const QString &sessionId, bool ok, const QStringList &saved);
    void cancelled(const QString &sessionId);

private:
    struct Upload
    {
        QString fileId;
        std::unique_ptr<QFile> file;
        std::unique_ptr<QCryptographicHash> hash;
        QString partPath;
    };

    void respondJson(Connection *connection, int status, const QJsonObject &body);
    void prepareUpload(Connection *connection);
    void cancelRequest(Connection *connection);
    void clearSession(bool removeParts);
    void checkFinished();
    void emitProgress(bool force);
    QString targetPath(IncomingFile &file);
    int pinStatus(const QString &ip, const QString &given);
    QList<Connection *> uploadConnections() const;

    friend class Connection;

    TlsServer *m_server = nullptr;
    SelfInfo m_self;
    QString m_pin;
    QHash<QString, int> m_pinAttempts;
    std::unique_ptr<IncomingSession> m_session;
    std::unordered_map<Connection *, Upload> m_uploads;
    QSet<Connection *> m_connections;
    QElapsedTimer m_progressClock;
    QTimer m_promptTimer;
};
