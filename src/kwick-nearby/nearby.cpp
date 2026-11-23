#include "nearby.h"

#include "images.h"
#include "portal.h"

#include <KConfigGroup>
#include <KSharedConfig>
#include <LayerShellQt/Window>

#include <QClipboard>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QIcon>
#include <QJsonArray>
#include <QJsonObject>
#include <QLocale>
#include <QMimeData>
#include <QMimeDatabase>
#include <QNetworkAccessManager>
#include <QProcess>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickView>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QUrl>

#include <algorithm>

#include <malloc.h>

namespace
{
QString readKwick(const QString &name)
{
    QFile file(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/kwick/") + name);
    return file.open(QIODevice::ReadOnly) ? QString::fromUtf8(file.readAll()).trimmed() : QString();
}

QString detectDesktop()
{
    const QString current = qEnvironmentVariable("XDG_CURRENT_DESKTOP").toLower();
    if (current.contains(QLatin1String("kde"))) {
        return QStringLiteral("kde");
    }
    if (current.contains(QLatin1String("gnome"))) {
        return QStringLiteral("gnome");
    }
    if (current.contains(QLatin1String("hyprland")) || qEnvironmentVariableIsSet("HYPRLAND_INSTANCE_SIGNATURE")) {
        return QStringLiteral("hyprland");
    }
    if (current.contains(QLatin1String("sway")) || qEnvironmentVariableIsSet("SWAYSOCK")) {
        return QStringLiteral("sway");
    }
    return current;
}

QString kindOf(const QString &mime, bool dir)
{
    if (dir) {
        return QStringLiteral("folder");
    }
    if (mime.startsWith(QLatin1String("image/"))) {
        return QStringLiteral("image");
    }
    if (mime.startsWith(QLatin1String("video/"))) {
        return QStringLiteral("film");
    }
    if (mime.startsWith(QLatin1String("audio/"))) {
        return QStringLiteral("music");
    }
    if (mime.contains(QLatin1String("zip")) || mime.contains(QLatin1String("tar")) || mime.contains(QLatin1String("compressed")) || mime.contains(QLatin1String("7z")) || mime.contains(QLatin1String("rar"))) {
        return QStringLiteral("archive");
    }
    return QStringLiteral("doc");
}

const QRegularExpression &linkPattern()
{
    static const QRegularExpression re(QStringLiteral("^(https?://|www\\.)\\S+$"), QRegularExpression::CaseInsensitiveOption);
    return re;
}
}

Nearby::Nearby(QObject *parent)
    : QObject(parent)
{
    m_desktop = detectDesktop();
    const QString layer = qEnvironmentVariable("KWICK_NEARBY_LAYER");
    m_layered = QGuiApplication::platformName().startsWith(QLatin1String("wayland")) && (layer.isEmpty() ? m_desktop != QLatin1String("gnome") : layer == QLatin1String("1"));
    m_nam = new QNetworkAccessManager(this);
    m_nam->setAutoDeleteReplies(false);
    m_server = new Server(this);
    m_discovery = new Discovery(m_nam, this);

    m_server->allowRegister = [this](const QString &fp) { return visibleTo(fp); };
    m_server->refuseUpload = [this](const QString &cert) { return uploadRefusal(cert); };
    m_discovery->shouldAnswer = [this](const Device &d) { return m_sheet || effectiveVisibility() == QLatin1String("everyone") || (d.protocol == QLatin1String("https") && visibleTo(d.fingerprint)); };

    connect(m_server, &Server::registered, this, &Nearby::addDevice);
    connect(m_discovery, &Discovery::found, this, &Nearby::addDevice);
    connect(m_server, &Server::request, this, &Nearby::onRequest);
    connect(m_server, &Server::progress, this, [this](const QString &id, qint64 received, qint64 total, int done, int count) {
        if (m_incoming.value(QStringLiteral("sessionId")).toString() != id) {
            return;
        }
        patchIncoming({{QStringLiteral("state"), QStringLiteral("receiving")},
                       {QStringLiteral("progress"), total > 0 ? double(received) / double(total) : (count > 0 ? double(done) / count : 0.0)},
                       {QStringLiteral("detail"), (count > 1 ? QStringLiteral("%1 of %2  ·  ").arg(qMin(done + 1, count)).arg(count) : QString()) + QStringLiteral("%1 of %2").arg(formatSize(double(received)), formatSize(double(total)))}});
    });
    connect(m_server, &Server::finished, this, [this](const QString &id, bool ok, const QStringList &saved) {
        if (m_incoming.value(QStringLiteral("sessionId")).toString() != id) {
            return;
        }
        QVariantList paths;
        for (const QString &p : saved) {
            paths.append(p);
        }
        const int count = m_incoming.value(QStringLiteral("count")).toInt();
        const QString folderName = QFileInfo(m_settings.folder).fileName();
        patchIncoming({{QStringLiteral("state"), ok ? QStringLiteral("done") : QStringLiteral("failed")},
                       {QStringLiteral("progress"), 1.0},
                       {QStringLiteral("saved"), paths},
                       {QStringLiteral("detail"), ok ? (count == 1 ? QStringLiteral("Saved to %1").arg(folderName) : QStringLiteral("%1 items saved to %2").arg(count).arg(folderName))
                                                     : QStringLiteral("Some items could not be received")}});
        m_incomingTimer.start(ok ? 12000 : 20000);
        updateNetwork();
    });
    connect(m_server, &Server::cancelled, this, [this](const QString &id) {
        if (m_incoming.value(QStringLiteral("sessionId")).toString() != id) {
            return;
        }
        patchIncoming({{QStringLiteral("state"), QStringLiteral("cancelled")}, {QStringLiteral("detail"), QStringLiteral("The transfer was cancelled")}});
        m_incomingTimer.start(5000);
        updateNetwork();
    });

    m_reload.setSingleShot(true);
    m_reload.setInterval(150);
    connect(&m_reload, &QTimer::timeout, this, &Nearby::reloadSettings);
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, &m_reload, qOverload<>(&QTimer::start));
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, &m_reload, qOverload<>(&QTimer::start));

    m_expiry.setInterval(10000);
    connect(&m_expiry, &QTimer::timeout, this, [this]() {
        const qint64 now = QDateTime::currentMSecsSinceEpoch();
        if (m_settings.visibility == QLatin1String("everyone") && m_settings.everyoneUntil > 0 && now >= m_settings.everyoneUntil) {
            m_settings.visibility = QStringLiteral("contacts");
            m_settings.everyoneUntil = 0;
            m_settings.save();
            updateNetwork();
        }
        Q_EMIT configChanged();
    });
    m_expiry.start();

    m_idle.setSingleShot(true);
    m_idle.setInterval(20000);
    connect(&m_idle, &QTimer::timeout, this, [this]() {
        if (!wantNetwork() && !m_sheet && !m_incomingView) {
            QCoreApplication::quit();
        }
    });

    m_reannounce.setInterval(5000);
    connect(&m_reannounce, &QTimer::timeout, this, [this]() {
        m_discovery->announce();
        pruneDevices();
    });

    m_searchTimer.setSingleShot(true);
    m_searchTimer.setInterval(3500);
    connect(&m_searchTimer, &QTimer::timeout, this, [this]() {
        if (m_sheet && m_devices.isEmpty()) {
            m_discovery->scan();
            QTimer::singleShot(4500, this, [this]() {
                m_searching = false;
                Q_EMIT searchingChanged();
            });
        } else {
            m_searching = false;
            Q_EMIT searchingChanged();
        }
    });

    m_devicesTimer.setSingleShot(true);
    m_devicesTimer.setInterval(200);
    connect(&m_devicesTimer, &QTimer::timeout, this, &Nearby::devicesChanged);

    m_incomingTimer.setSingleShot(true);
    connect(&m_incomingTimer, &QTimer::timeout, this, [this]() {
        if (m_incomingHeld) {
            m_incomingTimer.start(3000);
            return;
        }
        const QString state = m_incoming.value(QStringLiteral("state")).toString();
        if (state == QLatin1String("done") || state == QLatin1String("failed") || state == QLatin1String("cancelled")) {
            closeIncoming();
        }
    });

    reloadSettings();
    refreshTheme();
}

Nearby::~Nearby()
{
    delete m_sheet;
    delete m_incomingView;
}

void Nearby::reloadSettings()
{
    const QString file = Settings::path();
    QDir().mkpath(QFileInfo(file).absolutePath());
    m_settings.load();
    if (!m_watcher.directories().contains(QFileInfo(file).absolutePath())) {
        m_watcher.addPath(QFileInfo(file).absolutePath());
    }
    if (QFileInfo::exists(file) && !m_watcher.files().contains(file)) {
        m_watcher.addPath(file);
    }
    m_server->setPin(m_settings.requirePin ? m_settings.pin : QString());
    if (m_identityLoaded) {
        m_server->setSelf(selfInfo());
        m_discovery->setSelf(selfInfo(), m_identity.clientConfiguration());
    }
    Q_EMIT configChanged();
    updateNetwork();
}

void Nearby::refreshTheme()
{
    const bool dark = readKwick(QStringLiteral("appearance")) != QLatin1String("light");
    int radius = 10;
    bool numeric = false;
    const int fileRadius = readKwick(QStringLiteral("radius")).toInt(&numeric);
    if (numeric) {
        radius = fileRadius;
    }
    KSharedConfig::Ptr globals = KSharedConfig::openConfig(QStringLiteral("kdeglobals"));
    globals->reparseConfiguration();
    const QString raw = KConfigGroup(globals, QStringLiteral("General")).readEntry("AccentColor", QString()).trimmed();
    const QStringList channels = raw.split(QLatin1Char(','));
    QColor accent;
    if (channels.size() >= 3) {
        accent = QColor(channels.at(0).trimmed().toInt(), channels.at(1).trimmed().toInt(), channels.at(2).trimmed().toInt());
    } else if (QColor::isValidColorName(raw)) {
        accent = QColor::fromString(raw);
    }
    if (!accent.isValid()) {
        accent = dark ? QColor(QStringLiteral("#0a84ff")) : QColor(QStringLiteral("#007aff"));
    }
    if (dark != m_dark || radius != m_radius || accent != m_accent) {
        m_dark = dark;
        m_radius = radius;
        m_accent = accent;
        Q_EMIT themeChanged();
    }
}

QString Nearby::effectiveVisibility() const
{
    return m_settings.effectiveVisibility(QDateTime::currentMSecsSinceEpoch());
}

QString Nearby::visibility() const
{
    return effectiveVisibility();
}

QString Nearby::visibilityText() const
{
    const QString v = effectiveVisibility();
    if (v == QLatin1String("contacts")) {
        return QStringLiteral("Known Devices Only");
    }
    if (v == QLatin1String("everyone")) {
        if (m_settings.everyoneUntil > 0) {
            const qint64 left = (m_settings.everyoneUntil - QDateTime::currentMSecsSinceEpoch() + 59999) / 60000;
            return QStringLiteral("Everyone for %1 Minute%2").arg(qMax<qint64>(1, left)).arg(left == 1 ? QString() : QStringLiteral("s"));
        }
        return QStringLiteral("Everyone");
    }
    return QStringLiteral("Receiving Off");
}

bool Nearby::visibleTo(const QString &fingerprint) const
{
    if (m_sheet) {
        return true;
    }
    const QString v = effectiveVisibility();
    if (v == QLatin1String("everyone")) {
        return true;
    }
    if (v == QLatin1String("contacts")) {
        return !fingerprint.isEmpty() && m_settings.isKnown(fingerprint);
    }
    return false;
}

QString Nearby::uploadRefusal(const QString &certFingerprint) const
{
    const QString v = effectiveVisibility();
    if (v == QLatin1String("everyone")) {
        return {};
    }
    if (v == QLatin1String("contacts")) {
        if (certFingerprint.isEmpty()) {
            return QStringLiteral("Known devices only: the sender presented no TLS client certificate");
        }
        return m_settings.isKnown(certFingerprint) ? QString() : QStringLiteral("Known devices only: the sender's certificate is not a known device");
    }
    return QStringLiteral("Not receiving");
}

bool Nearby::wantNetwork() const
{
    if (m_sheet || m_server->busy()) {
        return true;
    }
    for (const auto &t : m_transfers) {
        if (t && !t->finished()) {
            return true;
        }
    }
    const QString v = effectiveVisibility();
    if (v == QLatin1String("everyone")) {
        return true;
    }
    return v == QLatin1String("contacts") && !m_settings.known.isEmpty();
}

bool Nearby::ensureIdentity()
{
    if (m_identityLoaded) {
        return true;
    }
    if (!m_identity.load(Settings::dataDir())) {
        qWarning("kwick-nearby: could not create the TLS identity");
        return false;
    }
    m_identityLoaded = true;
    return true;
}

SelfInfo Nearby::selfInfo() const
{
    SelfInfo s;
    s.alias = m_settings.alias;
    s.fingerprint = m_identity.fingerprint;
    s.port = m_server->running() ? m_server->port() : Protocol::Port;
    return s;
}

void Nearby::updateNetwork()
{
    const bool want = wantNetwork();
    const QString v = effectiveVisibility();
    const bool visible = v == QLatin1String("everyone") || (v == QLatin1String("contacts") && !m_settings.known.isEmpty());
    if (want) {
        m_idle.stop();
        if (!ensureIdentity()) {
            return;
        }
        if (!m_server->running()) {
            bool ok = false;
            for (quint16 port = Protocol::Port; port < Protocol::Port + 4 && !ok; ++port) {
                ok = m_server->start(m_identity.serverConfiguration(), port);
            }
            m_networkProblem = ok ? QString() : QStringLiteral("Nearby Share could not open its network port.");
            Q_EMIT searchingChanged();
        }
        m_server->setSelf(selfInfo());
        m_discovery->setSelf(selfInfo(), m_identity.clientConfiguration());
        const bool fresh = !m_discovery->running();
        if (fresh && !m_discovery->start()) {
            m_networkProblem = QStringLiteral("Another app is using port %1. Close LocalSend on this computer.").arg(Protocol::Port);
            Q_EMIT searchingChanged();
        }
        if ((fresh || visible != m_visibleBefore) && visible) {
            m_discovery->announce();
        }
    } else {
        if (m_discovery->running()) {
            m_discovery->stop();
        }
        if (m_server->running()) {
            m_server->stop();
        }
        scheduleIdle();
    }
    m_visibleBefore = want && visible;
}

void Nearby::scheduleIdle()
{
    if (!m_sheet && !m_incomingView && m_engine) {
        QTimer::singleShot(0, this, [this]() {
            if (!m_sheet && !m_incomingView && m_engine) {
                m_engine->deleteLater();
                m_engine = nullptr;
                QTimer::singleShot(500, this, []() { malloc_trim(0); });
            }
        });
    }
    if (!wantNetwork() && !m_sheet && !m_incomingView) {
        m_idle.start();
    }
}

void Nearby::handle(const QStringList &arguments, const QString &workingDirectory)
{
    QStringList paths;
    QString text;
    bool share = false;
    bool background = false;
    bool compose = false;
    for (int i = 1; i < arguments.size(); ++i) {
        const QString a = arguments.at(i);
        if (a == QLatin1String("--daemon") || a == QLatin1String("--autostart")) {
            background = true;
            m_daemon = true;
        } else if (a == QLatin1String("--share")) {
            share = true;
        } else if (a == QLatin1String("--text") && i + 1 < arguments.size()) {
            text = arguments.at(++i);
            share = true;
        } else if (a == QLatin1String("--choose")) {
            share = true;
            compose = true;
        } else if (a.startsWith(QLatin1String("--"))) {
            continue;
        } else {
            QString p = a;
            if (p.startsWith(QLatin1String("file:"))) {
                p = QUrl(p).toLocalFile();
            } else if (QFileInfo(p).isRelative()) {
                p = QDir(workingDirectory).absoluteFilePath(p);
            }
            if (QFileInfo::exists(p)) {
                paths.append(QFileInfo(p).absoluteFilePath());
            }
            share = true;
        }
    }
    if (background && !share) {
        updateNetwork();
        return;
    }
    openSheet(paths, text, compose || (paths.isEmpty() && text.isEmpty()));
}

void Nearby::setItems(const QStringList &paths)
{
    static QMimeDatabase db;
    m_paths = paths;
    m_itemList.clear();
    for (const QString &p : paths) {
        const QFileInfo info(p);
        const QMimeType mime = db.mimeTypeForFile(info);
        QVariantMap m;
        m.insert(QStringLiteral("name"), info.fileName());
        m.insert(QStringLiteral("path"), info.absoluteFilePath());
        m.insert(QStringLiteral("dir"), info.isDir());
        m.insert(QStringLiteral("size"), info.isDir() ? 0.0 : double(info.size()));
        m.insert(QStringLiteral("kind"), kindOf(mime.name(), info.isDir()));
        m.insert(QStringLiteral("comment"), info.isDir() ? QStringLiteral("Folder") : mime.isDefault() ? QStringLiteral("File") : mime.comment());
        m.insert(QStringLiteral("thumb"), mime.name().startsWith(QLatin1String("image/")) && info.size() < 80 * 1024 * 1024 ? QStringLiteral("image://nearby/thumb/") + QString::fromUtf8(QUrl::toPercentEncoding(info.absoluteFilePath())) : QString());
        m_itemList.append(m);
    }
    Q_EMIT itemsChanged();
}

QString Nearby::itemsTitle() const
{
    if (m_paths.isEmpty()) {
        return m_draft.trimmed().isEmpty() ? QStringLiteral("Nearby Share") : QStringLiteral("Text");
    }
    if (m_paths.size() == 1) {
        return m_itemList.value(0).toMap().value(QStringLiteral("name")).toString();
    }
    return QStringLiteral("%1 Items").arg(m_paths.size());
}

QString Nearby::itemsSubtitle() const
{
    if (m_paths.isEmpty()) {
        if (!m_draft.trimmed().isEmpty()) {
            const int n = m_draft.trimmed().size();
            return QStringLiteral("%1 character%2").arg(n).arg(n == 1 ? QString() : QStringLiteral("s"));
        }
        return QStringLiteral("Send files or text to devices near you");
    }
    double size = 0;
    int folders = 0;
    for (const QVariant &v : m_itemList) {
        const QVariantMap m = v.toMap();
        size += m.value(QStringLiteral("size")).toDouble();
        folders += m.value(QStringLiteral("dir")).toBool() ? 1 : 0;
    }
    if (m_paths.size() == 1) {
        const QVariantMap m = m_itemList.value(0).toMap();
        return m.value(QStringLiteral("dir")).toBool() ? QStringLiteral("Folder") : m.value(QStringLiteral("comment")).toString() + QStringLiteral("  ·  ") + formatSize(size);
    }
    if (folders == m_paths.size()) {
        return QStringLiteral("%1 folders").arg(folders);
    }
    return formatSize(size) + (folders ? QStringLiteral("  ·  %1 folder%2").arg(folders).arg(folders == 1 ? QString() : QStringLiteral("s")) : QString());
}

void Nearby::setDraft(const QString &text)
{
    if (text == m_draft) {
        return;
    }
    m_draft = text;
    Q_EMIT itemsChanged();
}

void Nearby::openSheet(const QStringList &paths, const QString &text, bool compose)
{
    refreshTheme();
    if (m_sheet) {
        bool idle = true;
        for (const auto &t : m_transfers) {
            idle = idle && (!t || t->finished());
        }
        if (idle) {
            m_transfers.clear();
            m_composing = compose;
            m_draft = text;
            setItems(paths);
            Q_EMIT devicesChanged();
        }
        m_sheet->show();
        m_sheet->raise();
        m_sheet->requestActivate();
        return;
    }
    m_transfers.clear();
    m_composing = compose;
    m_draft = text;
    setItems(paths);
    ensureEngine();
    m_sheet = createView(QStringLiteral("ShareSheet"));
    if (!m_sheet) {
        return;
    }
    m_sheet->setTitle(QStringLiteral("Nearby Share"));
    m_sheet->setIcon(QIcon::fromTheme(QStringLiteral("kwick-nearby")));
    m_sheet->setColor(m_dark ? QColor(30, 30, 30) : QColor(246, 246, 246));
    m_sheet->setResizeMode(QQuickView::SizeRootObjectToView);
    const QSize size(600, 452);
    m_sheet->setMinimumSize(QSize(520, 400));
    m_sheet->resize(size);
    connect(m_sheet, &QWindow::visibleChanged, this, [this](bool visible) {
        if (!visible) {
            QTimer::singleShot(0, this, &Nearby::closeSheet);
        }
    });
    m_sheet->show();
    m_sheet->requestActivate();
    pruneDevices();
    m_searching = true;
    Q_EMIT searchingChanged();
    updateNetwork();
    m_discovery->announce();
    for (const Device &d : std::as_const(m_devices)) {
        m_discovery->registerWith(d.ip, d.port, d.protocol, d.protocol == QLatin1String("https") ? d.fingerprint : QString(), false);
    }
    m_reannounce.start();
    m_searchTimer.start();
    Q_EMIT devicesChanged();
}

void Nearby::closeSheet()
{
    if (!m_sheet) {
        return;
    }
    QQuickView *view = m_sheet;
    m_sheet = nullptr;
    view->hide();
    view->deleteLater();
    m_reannounce.stop();
    m_searchTimer.stop();
    m_searching = false;
    updateNetwork();
    scheduleIdle();
}

void Nearby::ensureEngine()
{
    if (m_engine) {
        return;
    }
    m_engine = new QQmlEngine(this);
    m_engine->addImageProvider(QStringLiteral("nearby"), new Images());
    m_engine->rootContext()->setContextProperty(QStringLiteral("Nearby"), this);
}

QQuickView *Nearby::createView(const QString &type)
{
    auto *view = new QQuickView(m_engine, nullptr);
    view->loadFromModule(QStringLiteral("KwickNearby"), type);
    if (view->status() == QQuickView::Error) {
        for (const QQmlError &error : view->errors()) {
            qWarning("kwick-nearby: %s", qPrintable(error.toString()));
        }
        delete view;
        return nullptr;
    }
    return view;
}

void Nearby::pruneDevices()
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    bool changed = false;
    for (auto it = m_devices.begin(); it != m_devices.end();) {
        const bool busy = m_transfers.value(it.key()) && !m_transfers.value(it.key())->finished();
        if (!busy && now - it->seen > 900000) {
            it = m_devices.erase(it);
            changed = true;
        } else {
            ++it;
        }
    }
    if (changed) {
        Q_EMIT devicesChanged();
    }
}

void Nearby::addDevice(const Device &device)
{
    if (!device.valid() || device.fingerprint.compare(m_identity.fingerprint, Qt::CaseInsensitive) == 0) {
        return;
    }
    const QString key = device.fingerprint.toUpper();
    Device d = device;
    d.seen = QDateTime::currentMSecsSinceEpoch();
    const bool fresh = !m_devices.contains(key);
    const Device old = m_devices.value(key);
    if (!d.verified) {
        const bool moved = old.ip != d.ip || old.port != d.port || old.protocol != d.protocol;
        if (d.protocol == QLatin1String("https") && m_settings.isKnown(key) && (fresh || !old.verified || moved)) {
            m_discovery->registerWith(d.ip, d.port, d.protocol, key, false);
        }
        if (!fresh && old.verified) {
            if (moved) {
                return;
            }
            d.verified = true;
        }
    }
    m_devices.insert(key, d);
    if (fresh || old.alias != d.alias || old.ip != d.ip || old.model != d.model) {
        Q_EMIT devicesChanged();
    }
    if (m_searching && fresh) {
        m_searching = false;
        Q_EMIT searchingChanged();
    }
}

QVariantList Nearby::devices() const
{
    QList<Device> list = m_devices.values();
    std::sort(list.begin(), list.end(), [](const Device &a, const Device &b) {
        return a.alias.localeAwareCompare(b.alias) < 0;
    });
    QVariantList out;
    for (const Device &d : std::as_const(list)) {
        QVariantMap m;
        const QString key = d.fingerprint.toUpper();
        m.insert(QStringLiteral("id"), key);
        m.insert(QStringLiteral("alias"), d.alias);
        QString model = d.model;
        if (model.isEmpty()) {
            model = d.type == QLatin1String("mobile") ? QStringLiteral("Phone") : d.type == QLatin1String("web") ? QStringLiteral("Browser") : QStringLiteral("Computer");
        }
        m.insert(QStringLiteral("model"), model);
        m.insert(QStringLiteral("type"), d.type);
        m.insert(QStringLiteral("ip"), d.ip);
        m.insert(QStringLiteral("known"), d.verified && d.protocol == QLatin1String("https") && m_settings.isKnown(key));
        const Transfer *t = m_transfers.value(key);
        QString state = QStringLiteral("idle");
        QString detail;
        double progress = 0;
        if (t) {
            state = t->state;
            detail = t->detail;
            progress = t->total > 0 ? double(t->sent) / double(t->total) : 0;
            if (state == QLatin1String("sending") && t->filesTotal > 1) {
                detail = QStringLiteral("%1 of %2").arg(qMin(t->filesDone + 1, t->filesTotal)).arg(t->filesTotal);
            } else if (state == QLatin1String("sending")) {
                detail = QStringLiteral("%1%").arg(int(progress * 100));
            }
        }
        m.insert(QStringLiteral("state"), state);
        m.insert(QStringLiteral("detail"), detail);
        m.insert(QStringLiteral("progress"), progress);
        out.append(m);
    }
    return out;
}

void Nearby::send(const QString &id)
{
    if (!m_devices.contains(id) || !canSend()) {
        return;
    }
    if (Transfer *t = m_transfers.value(id); t && !t->finished() && t->state != QLatin1String("pin")) {
        return;
    }
    if (Transfer *old = m_transfers.value(id)) {
        old->deleteLater();
    }
    if (!ensureIdentity()) {
        return;
    }
    const QList<ShareItem> items = collectItems(m_paths, m_paths.isEmpty() ? m_draft.trimmed() : QString());
    if (items.isEmpty()) {
        return;
    }
    auto *t = new Transfer(m_nam, m_identity.clientConfiguration(), selfInfo(), m_devices.value(id), items, this);
    t->contact = m_settings.isKnown(id);
    m_transfers.insert(id, t);
    QPointer<Transfer> guard(t);
    connect(t, &Transfer::changed, this, [this, guard]() {
        Q_EMIT devicesChanged();
        if (guard && guard->finished()) {
            updateNetwork();
        }
    });
    connect(t, &Transfer::progressed, this, [this]() {
        if (!m_devicesTimer.isActive()) {
            m_devicesTimer.start();
        }
    });
    t->start();
    Q_EMIT devicesChanged();
}

void Nearby::submitPin(const QString &id, const QString &pin)
{
    Transfer *t = m_transfers.value(id);
    if (t && t->state == QLatin1String("pin") && !pin.trimmed().isEmpty()) {
        t->start(pin.trimmed());
    }
}

void Nearby::cancelSend(const QString &id)
{
    if (Transfer *t = m_transfers.value(id)) {
        if (t->state == QLatin1String("pin")) {
            m_transfers.remove(id);
            t->deleteLater();
        } else {
            t->cancel();
        }
        Q_EMIT devicesChanged();
    }
}

void Nearby::chooseFiles()
{
    auto apply = [this](const QStringList &chosen) {
        if (chosen.isEmpty()) {
            return;
        }
        QStringList paths = m_paths;
        for (const QString &p : chosen) {
            if (!paths.contains(p)) {
                paths.append(p);
            }
        }
        m_composing = false;
        setItems(paths);
        if (m_sheet) {
            m_sheet->requestActivate();
        }
    };
    QVariantMap options;
    options.insert(QStringLiteral("multiple"), true);
    options.insert(QStringLiteral("modal"), true);
    Portal::call(QStringLiteral("org.freedesktop.portal.FileChooser"), QStringLiteral("OpenFile"), {QString(), QStringLiteral("Choose Files to Share")}, options,
                 [this, apply](uint code, const QVariantMap &results) {
                     if (code == 0) {
                         QStringList paths;
                         for (const QString &uri : results.value(QStringLiteral("uris")).toStringList()) {
                             const QString p = QUrl(uri).toLocalFile();
                             if (!p.isEmpty()) {
                                 paths.append(p);
                             }
                         }
                         apply(paths);
                         return;
                     }
                     if (code != 2) {
                         return;
                     }
                     auto *proc = new QProcess(this);
                     connect(proc, &QProcess::finished, this, [proc, apply](int exitCode) {
                         proc->deleteLater();
                         if (exitCode == 0) {
                             apply(QString::fromUtf8(proc->readAllStandardOutput()).trimmed().split(QLatin1Char('\n'), Qt::SkipEmptyParts));
                         }
                     });
                     proc->start(QStringLiteral("zenity"), {QStringLiteral("--file-selection"), QStringLiteral("--multiple"), QStringLiteral("--separator=\n"), QStringLiteral("--title=Choose Files to Share")});
                 },
                 this);
}

void Nearby::removeItem(int index)
{
    if (index < 0 || index >= m_paths.size()) {
        return;
    }
    QStringList paths = m_paths;
    paths.removeAt(index);
    if (paths.isEmpty()) {
        m_composing = true;
    }
    setItems(paths);
}

void Nearby::setVisibility(const QString &mode)
{
    m_settings.load();
    if (mode == QLatin1String("everyone")) {
        m_settings.visibility = mode;
        m_settings.everyoneUntil = QDateTime::currentMSecsSinceEpoch() + EveryoneWindowMs;
    } else if (mode == QLatin1String("contacts") || mode == QLatin1String("off")) {
        m_settings.visibility = mode;
        m_settings.everyoneUntil = 0;
    } else {
        return;
    }
    m_settings.save();
    Q_EMIT configChanged();
    updateNetwork();
}

void Nearby::openSettings()
{
    QProcess::startDetached(QStringLiteral("sh"), {QStringLiteral("-c"), QStringLiteral("KWICK_SETTINGS_PAGE=nearby exec kwick-settings")});
}

void Nearby::onRequest(const QString &sessionId, const Device &sender, const QString &certFingerprint, const QJsonArray &files, qint64 total, bool message)
{
    refreshTheme();
    const QString fp = certFingerprint;
    QVariantList names;
    QStringList kinds;
    static QMimeDatabase db;
    for (const QJsonValue &v : files) {
        const QJsonObject f = v.toObject();
        if (names.size() < 4) {
            names.append(f.value(QLatin1String("name")).toString());
        }
        QString mime = f.value(QLatin1String("type")).toString();
        if (!mime.contains(QLatin1Char('/'))) {
            mime = db.mimeTypeForFile(f.value(QLatin1String("name")).toString(), QMimeDatabase::MatchExtension).name();
        }
        kinds.append(kindOf(mime, false));
    }
    kinds.removeDuplicates();
    const int count = files.size();
    QString title;
    QString text;
    if (message) {
        text = files.at(0).toObject().value(QLatin1String("preview")).toString();
        title = linkPattern().match(text.trimmed()).hasMatch() ? QStringLiteral("%1 would like to share a link.").arg(sender.alias) : QStringLiteral("%1 would like to share a note.").arg(sender.alias);
    } else if (count == 1) {
        const QString k = kinds.value(0);
        const QString noun = k == QLatin1String("image") ? QStringLiteral("a photo") : k == QLatin1String("film") ? QStringLiteral("a video") : k == QLatin1String("music") ? QStringLiteral("an audio file") : QStringLiteral("a file");
        title = QStringLiteral("%1 would like to share %2.").arg(sender.alias, noun);
    } else {
        const QString noun = kinds.size() == 1 && kinds.first() == QLatin1String("image") ? QStringLiteral("photos") : kinds.size() == 1 && kinds.first() == QLatin1String("film") ? QStringLiteral("videos") : QStringLiteral("items");
        title = QStringLiteral("%1 would like to share %2 %3.").arg(sender.alias).arg(count).arg(noun);
    }
    QString subtitle;
    if (!message) {
        const QString first = names.value(0).toString().section(QLatin1Char('/'), -1);
        subtitle = count == 1 ? first + QStringLiteral("  ·  ") + formatSize(double(total)) : QStringLiteral("%1 and %2 more  ·  %3").arg(first).arg(count - 1).arg(formatSize(double(total)));
    }
    QVariantMap map;
    map.insert(QStringLiteral("sessionId"), sessionId);
    map.insert(QStringLiteral("state"), message ? QStringLiteral("message") : QStringLiteral("ask"));
    map.insert(QStringLiteral("alias"), sender.alias);
    map.insert(QStringLiteral("model"), sender.model.isEmpty() ? (sender.type == QLatin1String("mobile") ? QStringLiteral("Phone") : QStringLiteral("Computer")) : sender.model);
    map.insert(QStringLiteral("type"), sender.type);
    map.insert(QStringLiteral("fingerprint"), fp);
    map.insert(QStringLiteral("ip"), sender.ip);
    map.insert(QStringLiteral("known"), !fp.isEmpty() && m_settings.isKnown(fp));
    map.insert(QStringLiteral("count"), count);
    map.insert(QStringLiteral("total"), double(total));
    map.insert(QStringLiteral("title"), title);
    map.insert(QStringLiteral("subtitle"), subtitle);
    map.insert(QStringLiteral("names"), names);
    map.insert(QStringLiteral("kind"), kinds.size() == 1 ? kinds.first() : QStringLiteral("doc"));
    map.insert(QStringLiteral("text"), text);
    map.insert(QStringLiteral("link"), message && linkPattern().match(text.trimmed()).hasMatch());
    map.insert(QStringLiteral("progress"), 0.0);
    map.insert(QStringLiteral("detail"), QString());
    m_incomingTimer.stop();
    setIncoming(map);
    showIncoming();
}

void Nearby::setIncoming(const QVariantMap &map)
{
    m_incoming = map;
    Q_EMIT incomingChanged();
}

void Nearby::patchIncoming(const QVariantMap &changes)
{
    for (auto it = changes.constBegin(); it != changes.constEnd(); ++it) {
        m_incoming.insert(it.key(), it.value());
    }
    Q_EMIT incomingChanged();
}

void Nearby::showIncoming()
{
    ensureEngine();
    if (!m_incomingView) {
        m_incomingView = createView(QStringLiteral("Incoming"));
        if (!m_incomingView) {
            return;
        }
        m_incomingView->setTitle(QStringLiteral("Nearby Share"));
        m_incomingView->setIcon(QIcon::fromTheme(QStringLiteral("kwick-nearby")));
        m_incomingView->setColor(Qt::transparent);
        m_incomingView->setResizeMode(QQuickView::SizeViewToRootObject);
        placeIncoming();
    }
    m_incomingView->show();
    m_incomingView->raise();
    if (!m_layered) {
        m_incomingView->requestActivate();
    }
}

void Nearby::placeIncoming()
{
    QQuickView *view = m_incomingView;
    if (!view) {
        return;
    }
    view->setFlags(Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint | Qt::Dialog);
    if (m_layered) {
        auto *layer = LayerShellQt::Window::get(view);
        layer->setScope(QStringLiteral("kwick-nearby"));
        layer->setLayer(LayerShellQt::Window::LayerOverlay);
        layer->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop | LayerShellQt::Window::AnchorRight));
        layer->setMargins(QMargins(0, 6, 6, 0));
        layer->setExclusiveZone(0);
        layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityOnDemand);
        layer->setScreenConfiguration(LayerShellQt::Window::ScreenFromCompositor);
    }
}

void Nearby::closeIncoming()
{
    m_incomingTimer.stop();
    m_incomingHeld = false;
    if (m_incomingView) {
        QQuickView *view = m_incomingView;
        m_incomingView = nullptr;
        view->hide();
        view->deleteLater();
    }
    m_incoming.clear();
    Q_EMIT incomingChanged();
    updateNetwork();
    scheduleIdle();
}

void Nearby::accept()
{
    const QString id = m_incoming.value(QStringLiteral("sessionId")).toString();
    if (id.isEmpty()) {
        return;
    }
    const QString fp = m_incoming.value(QStringLiteral("fingerprint")).toString();
    KnownDevice k;
    k.fingerprint = fp;
    k.alias = m_incoming.value(QStringLiteral("alias")).toString();
    k.model = m_incoming.value(QStringLiteral("model")).toString();
    k.type = m_incoming.value(QStringLiteral("type")).toString();
    k.seen = QDateTime::currentMSecsSinceEpoch();
    m_settings.load();
    if (!fp.isEmpty()) {
        m_settings.remember(k);
        m_settings.save();
    }
    patchIncoming({{QStringLiteral("state"), QStringLiteral("receiving")}, {QStringLiteral("detail"), QStringLiteral("Waiting for %1…").arg(k.alias)}, {QStringLiteral("known"), !fp.isEmpty()}});
    m_server->accept(id, m_settings.folder);
}

void Nearby::decline()
{
    const QString id = m_incoming.value(QStringLiteral("sessionId")).toString();
    m_server->decline(id, 403);
    closeIncoming();
}

void Nearby::cancelIncoming()
{
    const QString id = m_incoming.value(QStringLiteral("sessionId")).toString();
    m_server->cancelIncoming(id);
    patchIncoming({{QStringLiteral("state"), QStringLiteral("cancelled")}, {QStringLiteral("detail"), QStringLiteral("You stopped the transfer")}});
    m_incomingTimer.start(4000);
}

void Nearby::copyMessage()
{
    const QString text = m_incoming.value(QStringLiteral("text")).toString();
    QGuiApplication::clipboard()->setText(text);
    m_server->finishMessage(m_incoming.value(QStringLiteral("sessionId")).toString());
    patchIncoming({{QStringLiteral("state"), QStringLiteral("copied")}, {QStringLiteral("detail"), QStringLiteral("Copied to Clipboard")}});
    m_incomingTimer.start(1800);
    QTimer::singleShot(1800, this, [this]() {
        if (m_incoming.value(QStringLiteral("state")).toString() == QLatin1String("copied")) {
            closeIncoming();
        }
    });
}

void Nearby::openMessageLink()
{
    QString text = m_incoming.value(QStringLiteral("text")).toString().trimmed();
    if (text.startsWith(QLatin1String("www."), Qt::CaseInsensitive)) {
        text.prepend(QStringLiteral("https://"));
    }
    m_server->finishMessage(m_incoming.value(QStringLiteral("sessionId")).toString());
    QDesktopServices::openUrl(QUrl(text));
    closeIncoming();
}

void Nearby::openReceived()
{
    const QVariantList saved = m_incoming.value(QStringLiteral("saved")).toList();
    if (saved.size() == 1) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(saved.first().toString()));
    } else {
        QDesktopServices::openUrl(QUrl::fromLocalFile(m_settings.folder));
    }
    closeIncoming();
}

void Nearby::revealReceived()
{
    const QVariantList saved = m_incoming.value(QStringLiteral("saved")).toList();
    QStringList uris;
    for (const QVariant &v : saved) {
        uris.append(QUrl::fromLocalFile(v.toString()).toString());
    }
    if (uris.isEmpty()) {
        uris.append(QUrl::fromLocalFile(m_settings.folder).toString());
    }
    QDBusMessage message = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.FileManager1"), QStringLiteral("/org/freedesktop/FileManager1"), QStringLiteral("org.freedesktop.FileManager1"), QStringLiteral("ShowItems"));
    message << uris << QString();
    const QDBusMessage reply = QDBusConnection::sessionBus().call(message, QDBus::Block, 3000);
    if (reply.type() != QDBusMessage::ReplyMessage) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(m_settings.folder));
    }
    closeIncoming();
}

void Nearby::holdIncoming(bool hold)
{
    m_incomingHeld = hold;
}

QString Nearby::formatSize(double bytes) const
{
    if (bytes < 1000) {
        return QStringLiteral("%1 bytes").arg(qint64(bytes));
    }
    const char *units[] = {"KB", "MB", "GB", "TB"};
    double v = bytes / 1000.0;
    int u = 0;
    while (v >= 1000.0 && u < 3) {
        v /= 1000.0;
        ++u;
    }
    return QStringLiteral("%1 %2").arg(QLocale(QLocale::English).toString(v, 'f', v < 10 ? 1 : 0), QLatin1String(units[u]));
}

QString Nearby::icon(const QString &name, const QColor &tint) const
{
    return QStringLiteral("image://nearby/icon/") + name + QLatin1Char('/') + tint.name(QColor::HexArgb).mid(1);
}
