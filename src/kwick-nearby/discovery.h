#pragma once

#include "protocol.h"

#include <QHash>
#include <QObject>
#include <QSet>
#include <QSslConfiguration>
#include <QStringList>
#include <QTimer>

#include <functional>

class QNetworkAccessManager;
class QNetworkReply;
class QUdpSocket;

namespace Http
{
QNetworkReply *post(QNetworkAccessManager *nam, const QSslConfiguration &tls, const QString &url, const QByteArray &body, const QString &expectedFingerprint, int timeoutMs);
QString url(const Device &device, const QString &route);
QString peerFingerprint(QNetworkReply *reply);
void pin(QNetworkReply *reply, const QString &expectedFingerprint);
bool pinFailed(QNetworkReply *reply);
}

class Discovery : public QObject
{
    Q_OBJECT

public:
    Discovery(QNetworkAccessManager *nam, QObject *parent = nullptr);

    bool start();
    void stop();
    bool running() const;
    void setSelf(const SelfInfo &self, const QSslConfiguration &tls);
    void announce();
    void scan();
    void registerWith(const QString &ip, quint16 port, const QString &protocol, const QString &expectedFingerprint, bool fallbackMulticast);

    std::function<bool(const Device &device)> shouldAnswer;

Q_SIGNALS:
    void found(const Device &device);

private:
    void readPending();
    void joinAll();
    void sendMulticast(bool announce);
    void pumpScan();

    QNetworkAccessManager *m_nam;
    QUdpSocket *m_socket = nullptr;
    SelfInfo m_self;
    QSslConfiguration m_tls;
    QTimer m_rejoin;
    QSet<QString> m_joined;
    QSet<QString> m_dialing;
    QStringList m_scanQueue;
    int m_scanActive = 0;
};
