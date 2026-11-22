#include "server.h"

#include "identity.h"

#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QTcpServer>
#include <QSslSocket>
#include <QStorageInfo>
#include <QUrl>
#include <QUrlQuery>

class Connection : public QObject
{
public:
    Connection(QSslSocket *socket, Server *server);
    ~Connection() override;

    void respond(int status, const QByteArray &body, const QByteArray &type = QByteArrayLiteral("application/json"));
    void close();

    QSslSocket *socket;
    Server *server;
    QString method;
    QString path;
    QUrlQuery query;
    QHash<QByteArray, QByteArray> headers;
    QByteArray body;
    QString ip;
    QString certFingerprint;
    bool waiting = false;
    bool uploading = false;

private:
    enum class Stage { Headers, Body, Done };
    enum class Chunk { Size, Data, DataEnd, Trailer };

    void readable();
    bool parseHeaders();
    bool consumeBody();
    bool sink(const char *data, qint64 size);
    void complete();
    void reset();

    Stage m_stage = Stage::Headers;
    QByteArray m_buffer;
    qint64 m_remaining = 0;
    bool m_chunked = false;
    Chunk m_chunk = Chunk::Size;
    qint64 m_chunkLeft = 0;
    bool m_failed = false;
    QTimer m_idle;
};

namespace
{
QByteArray reason(int status)
{
    switch (status) {
    case 100: return "Continue";
    case 200: return "OK";
    case 204: return "No Content";
    case 400: return "Bad Request";
    case 401: return "Unauthorized";
    case 403: return "Forbidden";
    case 404: return "Not Found";
    case 409: return "Conflict";
    case 412: return "Precondition Failed";
    case 413: return "Payload Too Large";
    case 422: return "Unprocessable Entity";
    case 429: return "Too Many Requests";
    case 507: return "Insufficient Storage";
    default: return "Internal Server Error";
    }
}

QJsonObject message(const QString &text)
{
    return QJsonObject{{QStringLiteral("message"), text}};
}

constexpr qint64 JsonLimit = 4 * 1024 * 1024;
constexpr int MaxConnections = 64;
constexpr int MaxHandshakes = 32;
}

class TlsServer : public QTcpServer
{
public:
    TlsServer(const QSslConfiguration &config, QObject *parent)
        : QTcpServer(parent)
        , m_config(config)
    {
    }

    std::function<void(QSslSocket *)> ready;

protected:
    void incomingConnection(qintptr descriptor) override
    {
        auto *socket = new QSslSocket(this);
        if (!socket->setSocketDescriptor(descriptor)) {
            delete socket;
            return;
        }
        if (m_handshakes >= MaxHandshakes) {
            socket->abort();
            socket->deleteLater();
            return;
        }
        ++m_handshakes;
        socket->setSslConfiguration(m_config);
        auto *timer = new QTimer(socket);
        timer->setSingleShot(true);
        auto done = std::make_shared<bool>(false);
        auto finish = [this, socket, timer, done](bool ok) {
            if (*done) {
                return;
            }
            *done = true;
            --m_handshakes;
            timer->stop();
            if (ok && ready) {
                ready(socket);
            } else {
                socket->abort();
                socket->deleteLater();
            }
        };
        connect(socket, &QSslSocket::encrypted, this, [finish]() { finish(true); });
        connect(socket, &QSslSocket::sslErrors, socket, [socket](const QList<QSslError> &) { socket->ignoreSslErrors(); });
        connect(socket, &QSslSocket::peerVerifyError, socket, [socket](const QSslError &) { socket->ignoreSslErrors(); });
        connect(socket, &QAbstractSocket::errorOccurred, this, [finish](QAbstractSocket::SocketError) { finish(false); });
        connect(socket, &QAbstractSocket::disconnected, this, [finish]() { finish(false); });
        connect(timer, &QTimer::timeout, this, [finish]() { finish(false); });
        timer->start(8000);
        socket->startServerEncryption();
    }

private:
    QSslConfiguration m_config;
    int m_handshakes = 0;
};

Connection::Connection(QSslSocket *s, Server *srv)
    : QObject(srv)
    , socket(s)
    , server(srv)
{
    socket->setParent(this);
    server->m_connections.insert(this);
    ip = Util::normalizeIp(socket->peerAddress());
    certFingerprint = Identity::fingerprintOf(socket->peerCertificate());
    m_idle.setSingleShot(true);
    m_idle.setInterval(90000);
    QObject::connect(&m_idle, &QTimer::timeout, this, [this]() {
        if (!waiting) {
            close();
        }
    });
    QObject::connect(socket, &QSslSocket::readyRead, this, [this]() { readable(); });
    QObject::connect(socket, &QSslSocket::disconnected, this, [this]() {
        server->connectionGone(this);
        deleteLater();
    });
    QObject::connect(socket, &QSslSocket::errorOccurred, this, [this](QAbstractSocket::SocketError error) {
        if (error != QAbstractSocket::RemoteHostClosedError) {
            close();
        }
    });
    m_idle.start();
    if (socket->bytesAvailable() > 0) {
        QTimer::singleShot(0, this, [this]() { readable(); });
    }
}

Connection::~Connection()
{
    server->m_connections.remove(this);
}

void Connection::close()
{
    if (socket->state() != QAbstractSocket::UnconnectedState) {
        socket->disconnectFromHost();
        if (socket->state() != QAbstractSocket::UnconnectedState) {
            socket->abort();
        }
    }
}

void Connection::respond(int status, const QByteArray &payload, const QByteArray &type)
{
    QByteArray out = "HTTP/1.1 " + QByteArray::number(status) + ' ' + reason(status) + "\r\n";
    if (!payload.isEmpty()) {
        out += "Content-Type: " + type + "\r\n";
    }
    out += "Content-Length: " + QByteArray::number(payload.size()) + "\r\n";
    out += m_failed ? "Connection: close\r\n\r\n" : "Connection: keep-alive\r\n\r\n";
    out += payload;
    socket->write(out);
    waiting = false;
    if (m_failed) {
        socket->disconnectFromHost();
        return;
    }
    if (m_stage == Stage::Done) {
        reset();
        if (!m_buffer.isEmpty()) {
            QTimer::singleShot(0, this, [this]() { readable(); });
        }
    }
}

void Connection::reset()
{
    m_stage = Stage::Headers;
    method.clear();
    path.clear();
    query.clear();
    headers.clear();
    body.clear();
    m_remaining = 0;
    m_chunked = false;
    m_chunk = Chunk::Size;
    m_chunkLeft = 0;
    uploading = false;
    m_idle.start();
}

void Connection::readable()
{
    if (m_failed) {
        socket->readAll();
        return;
    }
    m_buffer += socket->readAll();
    m_idle.start();
    while (!m_failed) {
        if (m_stage == Stage::Headers) {
            if (!parseHeaders()) {
                return;
            }
        }
        if (m_stage == Stage::Body) {
            if (!consumeBody()) {
                return;
            }
        }
        if (m_stage == Stage::Done) {
            if (!waiting) {
                complete();
            }
            return;
        }
    }
}

bool Connection::parseHeaders()
{
    const qsizetype end = m_buffer.indexOf("\r\n\r\n");
    if (end < 0) {
        if (m_buffer.size() > 16384) {
            m_failed = true;
            m_stage = Stage::Done;
            respond(400, QJsonDocument(message(QStringLiteral("Header too large"))).toJson(QJsonDocument::Compact));
        }
        return false;
    }
    const QByteArray head = m_buffer.left(end);
    m_buffer.remove(0, end + 4);
    const QList<QByteArray> lines = head.split('\n');
    const QList<QByteArray> requestLine = lines.value(0).trimmed().split(' ');
    if (requestLine.size() < 2) {
        m_failed = true;
        m_stage = Stage::Done;
        respond(400, {});
        return false;
    }
    method = QString::fromLatin1(requestLine.at(0));
    const QUrl url(QString::fromLatin1(requestLine.at(1)));
    path = url.path();
    query = QUrlQuery(url.query(QUrl::FullyEncoded));
    for (int i = 1; i < lines.size(); ++i) {
        const QByteArray line = lines.at(i).trimmed();
        const qsizetype colon = line.indexOf(':');
        if (colon > 0) {
            headers.insert(line.left(colon).trimmed().toLower(), line.mid(colon + 1).trimmed());
        }
    }
    m_chunked = headers.value("transfer-encoding").toLower().contains("chunked");
    m_remaining = m_chunked ? 0 : headers.value("content-length", "0").toLongLong();
    if (m_remaining < 0) {
        m_remaining = 0;
    }
    m_stage = Stage::Body;
    const bool upload = path.endsWith(QLatin1String("/upload"));
    if (upload) {
        const int status = server->beginUpload(this);
        if (status != 0) {
            m_failed = true;
            m_stage = Stage::Done;
            respond(status, QJsonDocument(message(QStringLiteral("Upload rejected"))).toJson(QJsonDocument::Compact));
            return false;
        }
        uploading = true;
    } else if (!m_chunked && m_remaining > JsonLimit) {
        m_failed = true;
        m_stage = Stage::Done;
        respond(413, {});
        return false;
    }
    if (headers.value("expect").toLower() == "100-continue") {
        socket->write("HTTP/1.1 100 Continue\r\n\r\n");
    }
    return true;
}

bool Connection::sink(const char *data, qint64 size)
{
    if (size <= 0) {
        return true;
    }
    if (uploading) {
        if (!server->uploadData(this, data, size)) {
            m_failed = true;
            m_stage = Stage::Done;
            uploading = false;
            respond(500, {});
            return false;
        }
        return true;
    }
    if (body.size() + size > JsonLimit) {
        m_failed = true;
        m_stage = Stage::Done;
        respond(413, {});
        return false;
    }
    body.append(data, size);
    return true;
}

bool Connection::consumeBody()
{
    if (!m_chunked) {
        const qint64 take = qMin<qint64>(m_remaining, m_buffer.size());
        if (take > 0) {
            if (!sink(m_buffer.constData(), take)) {
                return false;
            }
            m_buffer.remove(0, take);
            m_remaining -= take;
        }
        if (m_remaining == 0) {
            m_stage = Stage::Done;
            return true;
        }
        return false;
    }
    while (true) {
        switch (m_chunk) {
        case Chunk::Size: {
            const qsizetype eol = m_buffer.indexOf("\r\n");
            if (eol < 0) {
                if (m_buffer.size() > 1024) {
                    m_failed = true;
                    m_stage = Stage::Done;
                    respond(400, {});
                }
                return false;
            }
            const QByteArray sizeLine = m_buffer.left(eol).split(';').value(0).trimmed();
            m_buffer.remove(0, eol + 2);
            bool ok = false;
            m_chunkLeft = sizeLine.toLongLong(&ok, 16);
            if (!ok || m_chunkLeft < 0) {
                m_failed = true;
                m_stage = Stage::Done;
                respond(400, {});
                return false;
            }
            m_chunk = m_chunkLeft == 0 ? Chunk::Trailer : Chunk::Data;
            break;
        }
        case Chunk::Data: {
            const qint64 take = qMin<qint64>(m_chunkLeft, m_buffer.size());
            if (take == 0) {
                return false;
            }
            if (!sink(m_buffer.constData(), take)) {
                return false;
            }
            m_buffer.remove(0, take);
            m_chunkLeft -= take;
            if (m_chunkLeft == 0) {
                m_chunk = Chunk::DataEnd;
            }
            break;
        }
        case Chunk::DataEnd:
            if (m_buffer.size() < 2) {
                return false;
            }
            m_buffer.remove(0, 2);
            m_chunk = Chunk::Size;
            break;
        case Chunk::Trailer: {
            const qsizetype eol = m_buffer.indexOf("\r\n");
            if (eol < 0) {
                return false;
            }
            const bool last = eol == 0;
            m_buffer.remove(0, eol + 2);
            if (last) {
                m_stage = Stage::Done;
                return true;
            }
            break;
        }
        }
    }
}

void Connection::complete()
{
    if (uploading) {
        uploading = false;
        const int status = server->finishUpload(this);
        respond(status, status == 200 ? QByteArray() : QJsonDocument(message(QStringLiteral("Upload failed"))).toJson(QJsonDocument::Compact));
        return;
    }
    server->handle(this);
}

Server::Server(QObject *parent)
    : QObject(parent)
{
    m_promptTimer.setSingleShot(true);
    m_promptTimer.setInterval(120000);
    connect(&m_promptTimer, &QTimer::timeout, this, [this]() {
        if (m_session && !m_session->active) {
            const QString id = m_session->id;
            decline(id, 403);
            Q_EMIT cancelled(id);
        }
    });
}

Server::~Server()
{
    stop();
}

bool Server::start(const QSslConfiguration &config, quint16 port)
{
    if (m_server) {
        return true;
    }
    m_server = new TlsServer(config, this);
    m_server->ready = [this](QSslSocket *socket) {
        if (m_connections.size() >= MaxConnections) {
            socket->abort();
            socket->deleteLater();
            return;
        }
        new Connection(socket, this);
    };
    if (!m_server->listen(QHostAddress::Any, port)) {
        qWarning("kwick-nearby: cannot listen on port %u: %s", port, qPrintable(m_server->errorString()));
        delete m_server;
        m_server = nullptr;
        return false;
    }
    return true;
}

void Server::stop()
{
    if (m_session) {
        clearSession(true);
    }
    const QList<Connection *> connections = m_connections.values();
    for (Connection *c : connections) {
        c->socket->abort();
        delete c;
    }
    m_uploads.clear();
    if (m_server) {
        m_server->close();
        delete m_server;
        m_server = nullptr;
    }
}

bool Server::running() const
{
    return m_server && m_server->isListening();
}

quint16 Server::port() const
{
    return m_server ? m_server->serverPort() : 0;
}

void Server::setSelf(const SelfInfo &self)
{
    m_self = self;
}

void Server::setPin(const QString &pin)
{
    m_pin = pin;
}

bool Server::busy() const
{
    return m_session != nullptr;
}

void Server::respondJson(Connection *connection, int status, const QJsonObject &body)
{
    connection->respond(status, body.isEmpty() ? QByteArray() : QJsonDocument(body).toJson(QJsonDocument::Compact));
}

void Server::handle(Connection *c)
{
    const QString api = QLatin1String(Protocol::Api);
    if (!c->path.startsWith(api)) {
        respondJson(c, 404, message(QStringLiteral("Not found")));
        return;
    }
    const QString route = c->path.mid(api.size());
    if (route == QLatin1String("register") && c->method == QLatin1String("POST")) {
        const QJsonObject o = QJsonDocument::fromJson(c->body).object();
        Device d = Device::fromJson(o, c->ip);
        if (!c->certFingerprint.isEmpty()) {
            d.fingerprint = c->certFingerprint;
        }
        if (d.fingerprint.isEmpty()) {
            respondJson(c, 400, message(QStringLiteral("Invalid body")));
            return;
        }
        if (d.fingerprint.compare(m_self.fingerprint, Qt::CaseInsensitive) == 0) {
            respondJson(c, 412, message(QStringLiteral("Self-discovered")));
            return;
        }
        if (allowRegister && !allowRegister(d.fingerprint)) {
            respondJson(c, 403, message(QStringLiteral("Not visible")));
            return;
        }
        respondJson(c, 200, m_self.infoJson());
        Q_EMIT registered(d);
        return;
    }
    if (route == QLatin1String("info") && c->method == QLatin1String("GET")) {
        if (allowRegister && !allowRegister(c->certFingerprint)) {
            respondJson(c, 403, message(QStringLiteral("Not visible")));
            return;
        }
        respondJson(c, 200, m_self.infoJson());
        return;
    }
    if (route == QLatin1String("prepare-upload") && c->method == QLatin1String("POST")) {
        prepareUpload(c);
        return;
    }
    if (route == QLatin1String("cancel") && c->method == QLatin1String("POST")) {
        cancelRequest(c);
        return;
    }
    respondJson(c, 404, message(QStringLiteral("Not found")));
}

int Server::pinStatus(const QString &ip, const QString &given)
{
    if (m_pin.isEmpty()) {
        return 0;
    }
    const int attempts = m_pinAttempts.value(ip);
    if (attempts >= 3) {
        return 429;
    }
    if (given.isNull()) {
        return 401;
    }
    if (given != m_pin) {
        m_pinAttempts.insert(ip, attempts + 1);
        return 401;
    }
    m_pinAttempts.remove(ip);
    return 0;
}

void Server::prepareUpload(Connection *c)
{
    const QString pin = c->query.hasQueryItem(QStringLiteral("pin")) ? c->query.queryItemValue(QStringLiteral("pin"), QUrl::FullyDecoded) : QString();
    const QJsonObject o = QJsonDocument::fromJson(c->body).object();
    const QJsonObject info = o.value(QLatin1String("info")).toObject();
    const QJsonObject files = o.value(QLatin1String("files")).toObject();
    if (info.isEmpty() || files.isEmpty()) {
        respondJson(c, 400, message(QStringLiteral("Invalid body")));
        return;
    }
    Device sender = Device::fromJson(info, c->ip);
    if (!c->certFingerprint.isEmpty()) {
        sender.fingerprint = c->certFingerprint;
    }
    if (allowUpload) {
        const int status = allowUpload(sender, c->certFingerprint);
        if (status != 0) {
            respondJson(c, status, message(QStringLiteral("Rejected")));
            return;
        }
    }
    const int pinCheck = pinStatus(c->ip, pin);
    if (pinCheck != 0) {
        respondJson(c, pinCheck, message(pinCheck == 429 ? QStringLiteral("Too many requests") : pin.isNull() ? QStringLiteral("PIN required") : QStringLiteral("Invalid PIN")));
        return;
    }
    if (m_session) {
        respondJson(c, 409, message(QStringLiteral("Blocked by another session")));
        return;
    }
    auto session = std::make_unique<IncomingSession>();
    session->id = Util::randomToken();
    session->ip = c->ip;
    session->sender = sender;
    session->certFingerprint = c->certFingerprint;
    QJsonArray list;
    for (auto it = files.constBegin(); it != files.constEnd(); ++it) {
        const QJsonObject f = it.value().toObject();
        IncomingFile file;
        file.id = f.value(QLatin1String("id")).toString(it.key());
        if (file.id.isEmpty() || file.id.size() > 128) {
            continue;
        }
        file.name = Util::sanitizeRelative(f.value(QLatin1String("fileName")).toString());
        file.size = static_cast<qint64>(f.value(QLatin1String("size")).toDouble());
        if (file.size < 0) {
            file.size = 0;
        }
        file.type = f.value(QLatin1String("fileType")).toString();
        file.sha256 = f.value(QLatin1String("sha256")).toString().toLower();
        const QJsonValue preview = f.value(QLatin1String("preview"));
        file.preview = preview.isString() ? preview.toString() : QString();
        const QString modified = f.value(QLatin1String("metadata")).toObject().value(QLatin1String("modified")).toString();
        if (!modified.isEmpty()) {
            const QDateTime dt = QDateTime::fromString(modified, Qt::ISODateWithMs);
            file.modified = dt.isValid() ? dt.toMSecsSinceEpoch() : 0;
        }
        file.token = Util::randomToken();
        session->total += file.size;
        session->files.insert(file.id, file);
        session->order.append(file.id);
        QJsonObject entry;
        entry.insert(QLatin1String("id"), file.id);
        entry.insert(QLatin1String("name"), file.name);
        entry.insert(QLatin1String("size"), static_cast<double>(file.size));
        entry.insert(QLatin1String("type"), file.type);
        entry.insert(QLatin1String("preview"), file.preview.left(int(Protocol::MessageLimit)));
        list.append(entry);
        if (session->files.size() >= 10000) {
            break;
        }
    }
    if (session->files.isEmpty()) {
        respondJson(c, 400, message(QStringLiteral("No files provided")));
        return;
    }
    const IncomingFile first = session->files.value(session->order.first());
    const bool isMessage = Util::isMessage(first.type, first.preview, first.size, session->files.size());
    c->waiting = true;
    session->pending = c;
    const QString id = session->id;
    m_session = std::move(session);
    m_promptTimer.start();
    Q_EMIT request(id, m_session->sender, m_session->certFingerprint, list, m_session->total, isMessage);
}

void Server::accept(const QString &sessionId, const QString &folder)
{
    if (!m_session || m_session->id != sessionId || m_session->active) {
        return;
    }
    m_promptTimer.stop();
    Connection *c = m_session->pending;
    if (!c) {
        clearSession(false);
        Q_EMIT cancelled(sessionId);
        return;
    }
    QDir().mkpath(folder);
    const QStorageInfo storage(folder);
    if (storage.isValid() && storage.bytesAvailable() >= 0 && storage.bytesAvailable() < m_session->total + 64 * 1024 * 1024) {
        respondJson(c, 403, message(QStringLiteral("Not enough space on the receiver")));
        clearSession(false);
        Q_EMIT finished(sessionId, false, {});
        return;
    }
    m_session->folder = folder;
    m_session->active = true;
    m_session->pending = nullptr;
    QJsonObject tokens;
    for (const QString &id : std::as_const(m_session->order)) {
        tokens.insert(id, m_session->files.value(id).token);
    }
    QJsonObject body;
    body.insert(QLatin1String("sessionId"), m_session->id);
    body.insert(QLatin1String("files"), tokens);
    respondJson(c, 200, body);
    m_progressClock.start();
    emitProgress(true);
}

void Server::decline(const QString &sessionId, int status)
{
    if (!m_session || m_session->id != sessionId) {
        return;
    }
    m_promptTimer.stop();
    if (m_session->pending) {
        respondJson(m_session->pending, status, status == 204 ? QJsonObject() : message(QStringLiteral("Rejected")));
    }
    clearSession(true);
}

void Server::finishMessage(const QString &sessionId)
{
    decline(sessionId, 204);
}

void Server::cancelIncoming(const QString &sessionId)
{
    if (!m_session || m_session->id != sessionId) {
        return;
    }
    if (!m_session->active) {
        decline(sessionId, 403);
        return;
    }
    const QList<Connection *> uploads = uploadConnections();
    for (Connection *c : uploads) {
        abortUpload(c);
        c->close();
    }
    clearSession(true);
}

void Server::cancelRequest(Connection *c)
{
    const QString id = c->query.queryItemValue(QStringLiteral("sessionId"));
    if (m_session && m_session->ip == c->ip && (m_session->id == id || !m_session->active)) {
        const QString sid = m_session->id;
        if (m_session->pending && m_session->pending != c) {
            m_session->pending->respond(403, QJsonDocument(message(QStringLiteral("Cancelled by sender"))).toJson(QJsonDocument::Compact));
        }
        const QList<Connection *> uploads = uploadConnections();
        for (Connection *u : uploads) {
            abortUpload(u);
            u->close();
        }
        m_promptTimer.stop();
        clearSession(true);
        Q_EMIT cancelled(sid);
    }
    respondJson(c, 200, {});
}

QString Server::targetPath(IncomingFile &file)
{
    const QString &dir = m_session->folder;
    if (!file.name.contains(QLatin1Char('/'))) {
        return Util::uniquePath(dir, file.name);
    }
    const QString top = file.name.section(QLatin1Char('/'), 0, 0);
    QString mapped = m_session->tops.value(top);
    if (mapped.isEmpty()) {
        mapped = Util::uniquePath(dir, top);
        m_session->tops.insert(top, mapped);
        m_session->saved.append(mapped);
    }
    const QString rest = file.name.section(QLatin1Char('/'), 1);
    QString target = QDir(mapped).filePath(rest);
    if (QFileInfo::exists(target)) {
        const QFileInfo info(target);
        target = Util::uniquePath(info.absolutePath(), info.fileName());
    }
    return target;
}

int Server::beginUpload(Connection *c)
{
    if (!m_session || !m_session->active) {
        return 409;
    }
    const QString sessionId = c->query.queryItemValue(QStringLiteral("sessionId"));
    const QString fileId = c->query.queryItemValue(QStringLiteral("fileId"), QUrl::FullyDecoded);
    const QString token = c->query.queryItemValue(QStringLiteral("token"), QUrl::FullyDecoded);
    if (sessionId.isEmpty() || fileId.isEmpty() || token.isEmpty()) {
        return 400;
    }
    if (sessionId != m_session->id || c->ip != m_session->ip) {
        return 403;
    }
    auto it = m_session->files.find(fileId);
    if (it == m_session->files.end() || it->token != token) {
        return 403;
    }
    if (it->state == 1 || it->state == 2) {
        return 409;
    }
    for (const auto &entry : m_uploads) {
        if (entry.second.fileId == fileId) {
            return 409;
        }
    }
    it->path = targetPath(*it);
    const QFileInfo target(it->path);
    QDir().mkpath(target.absolutePath());
    Upload upload;
    upload.fileId = fileId;
    upload.partPath = target.absolutePath() + QStringLiteral("/.") + target.fileName() + QStringLiteral(".nearby-part");
    upload.file = std::make_unique<QFile>(upload.partPath);
    if (!upload.file->open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return 500;
    }
    if (!it->sha256.isEmpty()) {
        upload.hash = std::make_unique<QCryptographicHash>(QCryptographicHash::Sha256);
    }
    it->state = 1;
    it->received = 0;
    m_uploads.emplace(c, std::move(upload));
    return 0;
}

bool Server::uploadData(Connection *c, const char *data, qint64 size)
{
    auto u = m_uploads.find(c);
    if (u == m_uploads.end() || !m_session) {
        return false;
    }
    Upload &up = u->second;
    auto it = m_session->files.find(up.fileId);
    if (it == m_session->files.end()) {
        return false;
    }
    if (it->received + size > it->size + 1024 * 1024 && it->size > 0) {
        return false;
    }
    if (up.file->write(data, size) != size) {
        return false;
    }
    if (up.hash) {
        up.hash->addData(QByteArrayView(data, size));
    }
    it->received += size;
    emitProgress(false);
    return true;
}

int Server::finishUpload(Connection *c)
{
    auto u = m_uploads.find(c);
    if (u == m_uploads.end() || !m_session) {
        return 500;
    }
    Upload upload = std::move(u->second);
    m_uploads.erase(u);
    auto it = m_session->files.find(upload.fileId);
    if (it == m_session->files.end()) {
        upload.file->remove();
        return 500;
    }
    upload.file->flush();
    if (it->modified > 0) {
        upload.file->setFileTime(QDateTime::fromMSecsSinceEpoch(it->modified), QFileDevice::FileModificationTime);
    }
    upload.file->close();
    if (upload.hash && QString::fromLatin1(upload.hash->result().toHex()) != it->sha256) {
        upload.file->remove();
        it->state = 3;
        checkFinished();
        return 422;
    }
    if (QFileInfo::exists(it->path)) {
        const QFileInfo info(it->path);
        it->path = Util::uniquePath(info.absolutePath(), info.fileName());
    }
    if (!QFile::rename(upload.partPath, it->path)) {
        upload.file->remove();
        it->state = 3;
        checkFinished();
        return 500;
    }
    it->state = 2;
    if (!it->name.contains(QLatin1Char('/'))) {
        m_session->saved.append(it->path);
    }
    emitProgress(true);
    checkFinished();
    return 200;
}

void Server::abortUpload(Connection *c)
{
    auto u = m_uploads.find(c);
    if (u == m_uploads.end()) {
        return;
    }
    Upload upload = std::move(u->second);
    m_uploads.erase(u);
    upload.file->close();
    upload.file->remove();
    if (m_session) {
        auto it = m_session->files.find(upload.fileId);
        if (it != m_session->files.end()) {
            it->state = 3;
            it->received = 0;
        }
    }
}

QList<Connection *> Server::uploadConnections() const
{
    QList<Connection *> list;
    for (const auto &entry : m_uploads) {
        list.append(entry.first);
    }
    return list;
}

void Server::connectionGone(Connection *c)
{
    if (m_uploads.count(c)) {
        abortUpload(c);
        checkFinished();
    }
    if (m_session && !m_session->active && m_session->pending == c) {
        const QString id = m_session->id;
        m_promptTimer.stop();
        clearSession(true);
        Q_EMIT cancelled(id);
    }
}

void Server::emitProgress(bool force)
{
    if (!m_session || !m_session->active) {
        return;
    }
    if (!force && m_progressClock.isValid() && m_progressClock.elapsed() < 120) {
        return;
    }
    m_progressClock.restart();
    qint64 received = 0;
    int done = 0;
    for (const IncomingFile &f : std::as_const(m_session->files)) {
        received += f.state == 2 ? f.size : f.received;
        if (f.state == 2) {
            ++done;
        }
    }
    Q_EMIT progress(m_session->id, received, m_session->total, done, m_session->files.size());
}

void Server::checkFinished()
{
    if (!m_session || !m_session->active) {
        return;
    }
    bool ok = true;
    for (const IncomingFile &f : std::as_const(m_session->files)) {
        if (f.state == 0 || f.state == 1) {
            return;
        }
        ok = ok && f.state == 2;
    }
    const QString id = m_session->id;
    const QStringList saved = m_session->saved;
    clearSession(false);
    Q_EMIT finished(id, ok, saved);
}

void Server::clearSession(bool removeParts)
{
    if (!m_session) {
        return;
    }
    if (removeParts) {
        const QList<Connection *> uploads = uploadConnections();
        for (Connection *c : uploads) {
            abortUpload(c);
        }
    }
    m_session.reset();
}
