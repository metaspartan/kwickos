#pragma once

#include "protocol.h"

#include <QHash>
#include <QList>
#include <QObject>
#include <QPointer>
#include <QSslConfiguration>

class QNetworkAccessManager;
class QNetworkReply;

struct ShareItem
{
    QString id;
    QString path;
    QString name;
    QString mime;
    QByteArray text;
    qint64 size = 0;
    qint64 modified = 0;
    bool isText = false;
};

QList<ShareItem> collectItems(const QStringList &paths, const QString &text);

class Transfer : public QObject
{
    Q_OBJECT

public:
    Transfer(QNetworkAccessManager *nam, const QSslConfiguration &tls, const SelfInfo &self, const Device &target, const QList<ShareItem> &items, QObject *parent = nullptr);
    ~Transfer() override;

    void start(const QString &pin = QString());
    void cancel();
    bool finished() const;

    Device target;
    QString state = QStringLiteral("idle");
    QString detail;
    qint64 sent = 0;
    qint64 total = 0;
    int filesDone = 0;
    int filesTotal = 0;
    bool contact = false;

Q_SIGNALS:
    void changed();
    void progressed();

private:
    void setState(const QString &value, const QString &text = QString());
    void uploadNext();
    QByteArray prepareBody() const;

    QNetworkAccessManager *m_nam;
    QSslConfiguration m_tls;
    SelfInfo m_self;
    QList<ShareItem> m_items;
    QHash<QString, int> m_index;
    QString m_sessionId;
    QHash<QString, QString> m_tokens;
    QStringList m_queue;
    QPointer<QNetworkReply> m_reply;
    qint64 m_doneBytes = 0;
    QString m_pin;
};
