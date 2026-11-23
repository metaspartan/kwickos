#include "sender.h"

#include "discovery.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrlQuery>

QList<ShareItem> collectItems(const QStringList &paths, const QString &text)
{
    QList<ShareItem> items;
    int counter = 0;
    auto nextId = [&counter]() { return Util::randomToken().left(16) + QString::number(++counter); };
    for (const QString &raw : paths) {
        const QFileInfo info(raw);
        if (!info.exists() || !info.isReadable()) {
            continue;
        }
        if (info.isDir()) {
            const QString root = info.absoluteFilePath();
            const QString top = info.fileName().isEmpty() ? QStringLiteral("Folder") : info.fileName();
            QDirIterator it(root, QDir::Files | QDir::Hidden | QDir::NoSymLinks | QDir::Readable, QDirIterator::Subdirectories);
            while (it.hasNext() && items.size() < 10000) {
                it.next();
                const QFileInfo f = it.fileInfo();
                ShareItem item;
                item.id = nextId();
                item.path = f.absoluteFilePath();
                item.name = top + QLatin1Char('/') + QDir(root).relativeFilePath(item.path);
                item.size = f.size();
                item.mime = Util::mimeFor(item.path);
                item.modified = f.lastModified().toMSecsSinceEpoch();
                items.append(item);
            }
            continue;
        }
        ShareItem item;
        item.id = nextId();
        item.path = info.absoluteFilePath();
        item.name = info.fileName();
        item.size = info.size();
        item.mime = Util::mimeFor(item.path);
        item.modified = info.lastModified().toMSecsSinceEpoch();
        items.append(item);
    }
    if (!text.isEmpty()) {
        ShareItem item;
        item.id = nextId();
        item.isText = true;
        item.text = text.toUtf8();
        item.name = item.id + QStringLiteral(".txt");
        item.size = item.text.size();
        item.mime = QStringLiteral("text/plain");
        items.append(item);
    }
    return items;
}

Transfer::Transfer(QNetworkAccessManager *nam, const QSslConfiguration &tls, const SelfInfo &self, const Device &device, const QList<ShareItem> &items, QObject *parent)
    : QObject(parent)
    , target(device)
    , m_nam(nam)
    , m_tls(tls)
    , m_self(self)
    , m_items(items)
{
    for (int i = 0; i < m_items.size(); ++i) {
        m_index.insert(m_items.at(i).id, i);
        total += m_items.at(i).size;
    }
    filesTotal = m_items.size();
}

Transfer::~Transfer()
{
    if (m_reply) {
        m_reply->abort();
    }
}

bool Transfer::finished() const
{
    return state == QLatin1String("done") || state == QLatin1String("declined") || state == QLatin1String("failed") || state == QLatin1String("cancelled") || state == QLatin1String("busy");
}

void Transfer::setState(const QString &value, const QString &text)
{
    state = value;
    detail = text;
    Q_EMIT changed();
}

QByteArray Transfer::prepareBody() const
{
    QJsonObject files;
    const bool single = m_items.size() == 1;
    for (const ShareItem &item : m_items) {
        QJsonObject f;
        f.insert(QLatin1String("id"), item.id);
        f.insert(QLatin1String("fileName"), item.name);
        f.insert(QLatin1String("size"), static_cast<double>(item.size));
        f.insert(QLatin1String("fileType"), item.mime);
        f.insert(QLatin1String("sha256"), QJsonValue::Null);
        if (item.isText && single && item.size <= Protocol::MessageLimit) {
            f.insert(QLatin1String("preview"), QString::fromUtf8(item.text));
        } else {
            f.insert(QLatin1String("preview"), QJsonValue::Null);
        }
        if (item.modified > 0) {
            QJsonObject meta;
            meta.insert(QLatin1String("modified"), Util::iso(item.modified));
            meta.insert(QLatin1String("accessed"), Util::iso(item.modified));
            f.insert(QLatin1String("metadata"), meta);
        }
        files.insert(item.id, f);
    }
    QJsonObject o;
    o.insert(QLatin1String("info"), m_self.registerJson());
    o.insert(QLatin1String("files"), files);
    return QJsonDocument(o).toJson(QJsonDocument::Compact);
}

void Transfer::start(const QString &pin)
{
    if (m_reply) {
        return;
    }
    m_pin = pin;
    sent = 0;
    m_doneBytes = 0;
    filesDone = 0;
    m_tokens.clear();
    m_queue.clear();
    m_sessionId.clear();
    QString url = Http::url(target, QStringLiteral("prepare-upload"));
    if (!pin.isEmpty()) {
        QUrlQuery q;
        q.addQueryItem(QStringLiteral("pin"), pin);
        url += QLatin1Char('?') + q.toString(QUrl::FullyEncoded);
    }
    if (target.protocol != QLatin1String("https") && contact) {
        qWarning("kwick-nearby: refusing to send to known device %s over unencrypted HTTP", qPrintable(target.ip));
        setState(QStringLiteral("failed"), QStringLiteral("Not verified"));
        return;
    }
    setState(QStringLiteral("waiting"));
    const QString expected = target.protocol == QLatin1String("https") ? target.fingerprint : QString();
    m_reply = Http::post(m_nam, m_tls, url, prepareBody(), expected, 150000);
    QNetworkReply *reply = m_reply;
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (m_reply == reply) {
            m_reply = nullptr;
        }
        if (state == QLatin1String("cancelled")) {
            return;
        }
        if (Http::pinFailed(reply)) {
            setState(QStringLiteral("failed"), QStringLiteral("Certificate mismatch"));
            return;
        }
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (status == 204) {
            sent = total;
            filesDone = filesTotal;
            setState(QStringLiteral("done"));
            return;
        }
        if (status == 200) {
            const QJsonObject o = QJsonDocument::fromJson(reply->readAll()).object();
            m_sessionId = o.value(QLatin1String("sessionId")).toString();
            const QJsonObject files = o.value(QLatin1String("files")).toObject();
            for (auto it = files.constBegin(); it != files.constEnd(); ++it) {
                if (m_index.contains(it.key())) {
                    m_tokens.insert(it.key(), it.value().toString());
                }
            }
            for (const ShareItem &item : std::as_const(m_items)) {
                if (m_tokens.contains(item.id)) {
                    m_queue.append(item.id);
                }
            }
            total = 0;
            for (const QString &id : std::as_const(m_queue)) {
                total += m_items.at(m_index.value(id)).size;
            }
            filesTotal = m_queue.size();
            setState(QStringLiteral("sending"));
            uploadNext();
            return;
        }
        if (status == 401) {
            setState(QStringLiteral("pin"), m_pin.isEmpty() ? QString() : QStringLiteral("Wrong PIN"));
        } else if (status == 403) {
            const QString reason = QJsonDocument::fromJson(reply->readAll()).object().value(QLatin1String("message")).toString();
            setState(QStringLiteral("declined"), reason.startsWith(QLatin1String("Known devices only")) ? QStringLiteral("Known devices only") : QString());
        } else if (status == 409) {
            setState(QStringLiteral("busy"));
        } else if (status == 429) {
            setState(QStringLiteral("failed"), QStringLiteral("Too many PIN attempts"));
        } else if (reply->error() == QNetworkReply::OperationCanceledError || reply->error() == QNetworkReply::TimeoutError) {
            setState(QStringLiteral("failed"), QStringLiteral("No response"));
        } else {
            setState(QStringLiteral("failed"), status ? QStringLiteral("Error %1").arg(status) : QStringLiteral("Not reachable"));
        }
    });
}

void Transfer::uploadNext()
{
    if (state != QLatin1String("sending")) {
        return;
    }
    if (m_queue.isEmpty()) {
        sent = total;
        setState(QStringLiteral("done"));
        return;
    }
    const QString id = m_queue.takeFirst();
    const ShareItem &item = m_items.at(m_index.value(id));
    QByteArray body;
    QFile *file = nullptr;
    QIODevice *device = nullptr;
    qint64 length = 0;
    if (item.isText) {
        body = item.text;
        length = body.size();
    } else {
        file = new QFile(item.path, this);
        if (!file->open(QIODevice::ReadOnly)) {
            delete file;
            setState(QStringLiteral("failed"), QStringLiteral("Cannot read %1").arg(QFileInfo(item.path).fileName()));
            return;
        }
        length = file->size();
        uchar *mapped = length > 0 ? file->map(0, length) : nullptr;
        if (mapped) {
            body = QByteArray::fromRawData(reinterpret_cast<const char *>(mapped), length);
        } else if (length > 0) {
            device = file;
        }
    }
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("sessionId"), m_sessionId);
    q.addQueryItem(QStringLiteral("fileId"), id);
    q.addQueryItem(QStringLiteral("token"), m_tokens.value(id));
    QNetworkRequest request{QUrl(Http::url(target, QStringLiteral("upload")) + QLatin1Char('?') + q.toString(QUrl::FullyEncoded))};
    request.setHeader(QNetworkRequest::ContentTypeHeader, QByteArrayLiteral("application/octet-stream"));
    request.setHeader(QNetworkRequest::ContentLengthHeader, length);
    request.setHeader(QNetworkRequest::UserAgentHeader, QByteArrayLiteral("KwickOS-Nearby/1.0"));
    request.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
    request.setSslConfiguration(m_tls);
    request.setTransferTimeout(60000);
    QNetworkReply *reply = device ? m_nam->post(request, device) : m_nam->post(request, body);
    if (file) {
        file->setParent(reply);
    }
    m_reply = reply;
    const qint64 itemSize = item.size;
    if (target.protocol == QLatin1String("https") && !target.fingerprint.isEmpty()) {
        Http::pin(reply, target.fingerprint);
    }
    connect(reply, &QNetworkReply::uploadProgress, this, [this](qint64 bytes, qint64) {
        sent = m_doneBytes + bytes;
        Q_EMIT progressed();
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, itemSize]() {
        reply->deleteLater();
        if (m_reply == reply) {
            m_reply = nullptr;
        }
        if (state != QLatin1String("sending")) {
            return;
        }
        if (Http::pinFailed(reply)) {
            setState(QStringLiteral("failed"), QStringLiteral("Certificate mismatch"));
            return;
        }
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (status != 200) {
            setState(QStringLiteral("failed"), status == 409 || status == 403 ? QStringLiteral("Stopped by the receiver") : QStringLiteral("Transfer interrupted"));
            return;
        }
        m_doneBytes += itemSize;
        sent = m_doneBytes;
        ++filesDone;
        uploadNext();
    });
}

void Transfer::cancel()
{
    if (finished()) {
        return;
    }
    const bool hadSession = !m_sessionId.isEmpty();
    setState(QStringLiteral("cancelled"));
    if (m_reply) {
        m_reply->abort();
    }
    if (target.protocol != QLatin1String("https") && contact) {
        return;
    }
    QString url = Http::url(target, QStringLiteral("cancel"));
    if (hadSession) {
        url += QStringLiteral("?sessionId=") + m_sessionId;
    }
    QNetworkReply *reply = Http::post(m_nam, m_tls, url, QByteArray(), target.protocol == QLatin1String("https") ? target.fingerprint : QString(), 4000);
    connect(reply, &QNetworkReply::finished, reply, &QObject::deleteLater);
}
