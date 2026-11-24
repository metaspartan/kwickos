#include "spotlight.h"

#include <KConfigGroup>
#include <KGlobalAccel>
#include <KRunner/AbstractRunner>
#include <KRunner/RunnerManager>
#include <KSharedConfig>
#include <KWindowEffects>
#include <LayerShellQt/Window>

#include <QAction>
#include <QCommandLineParser>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QGuiApplication>
#include <QIcon>
#include <QKeyEvent>
#include <QLocalSocket>
#include <QPainterPath>
#include <QProcess>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickView>
#include <QStandardPaths>
#include <QTimer>
#include <qpa/qplatformnativeinterface.h>

#include <wayland-client.h>

#include <algorithm>
#include <cstring>
#include <memory>

namespace
{
const QChar ModeMark = QChar(0x1);

QString configDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation);
}

QString kwickFile(const QString &name)
{
    return configDir() + QStringLiteral("/kwick/") + name;
}

QString readKwick(const QString &name)
{
    QFile file(kwickFile(name));
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
    return current.isEmpty() ? QStringLiteral("other") : current;
}

bool hasLayerShell()
{
    if (!QGuiApplication::platformName().startsWith(QLatin1String("wayland"))) {
        return false;
    }
    auto *display = static_cast<wl_display *>(QGuiApplication::platformNativeInterface()->nativeResourceForIntegration("wl_display"));
    if (!display) {
        return false;
    }
    wl_event_queue *queue = wl_display_create_queue(display);
    auto *wrapper = static_cast<wl_display *>(wl_proxy_create_wrapper(display));
    wl_proxy_set_queue(reinterpret_cast<wl_proxy *>(wrapper), queue);
    wl_registry *registry = wl_display_get_registry(wrapper);
    bool found = false;
    static const wl_registry_listener listener = {
        [](void *data, wl_registry *, uint32_t, const char *interface, uint32_t) {
            if (std::strcmp(interface, "zwlr_layer_shell_v1") == 0) {
                *static_cast<bool *>(data) = true;
            }
        },
        [](void *, wl_registry *, uint32_t) {},
    };
    wl_registry_add_listener(registry, &listener, &found);
    wl_display_roundtrip_queue(display, queue);
    wl_registry_destroy(registry);
    wl_proxy_wrapper_destroy(wrapper);
    wl_event_queue_destroy(queue);
    return found;
}

QList<QKeySequence> shortcutsFor(const QString &layout)
{
    if (layout == QLatin1String("windows")) {
        return {QKeySequence(Qt::META | Qt::Key_S), QKeySequence(Qt::META | Qt::Key_Space)};
    }
    return {QKeySequence(Qt::META | Qt::Key_Space)};
}

QStringList defaultRunners(const QString &desktop)
{
    if (desktop == QLatin1String("kde")) {
        return {
            QStringLiteral("krunner_kwick"),
            QStringLiteral("krunner_services"),
            QStringLiteral("krunner_systemsettings"),
            QStringLiteral("calculator"),
            QStringLiteral("windows"),
            QStringLiteral("locations"),
            QStringLiteral("krunner_shell"),
        };
    }
    return {
        QStringLiteral("krunner_kwick"),
        QStringLiteral("calculator"),
        QStringLiteral("locations"),
        QStringLiteral("krunner_shell"),
    };
}

QString iconThemeFor(const QString &layout)
{
    if (layout == QLatin1String("windows")) {
        return QStringLiteral("KwickOS-Fluent");
    }
    if (layout == QLatin1String("linux")) {
        return QStringLiteral("KwickOS-Linux");
    }
    return QStringLiteral("KwickOS");
}

QDBusMessage effectLoaded(const QString &effect)
{
    QDBusMessage msg = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"),
                                                      QStringLiteral("/Effects"),
                                                      QStringLiteral("org.kde.kwin.Effects"),
                                                      QStringLiteral("isEffectLoaded"));
    msg.setArguments({effect});
    return msg;
}
}

Spotlight::Spotlight(QObject *parent)
    : QObject(parent)
    , m_desktop(detectDesktop())
    , m_tracing(qEnvironmentVariableIsSet("KWICK_SPOTLIGHT_TRACE"))
{
    QElapsedTimer clock;
    clock.start();
    m_layered = hasLayerShell();
    if (m_tracing) {
        qInfo("kwick-spotlight: desktop %s, %s", qPrintable(m_desktop), m_layered ? "layer shell" : "toplevel window");
    }

    KSharedConfig::Ptr config = KSharedConfig::openConfig(QStringLiteral("kwickspotlightrc"));
    KSharedConfig::Ptr state = KSharedConfig::openStateConfig(QStringLiteral("kwickspotlightstaterc"));
    m_manager = new KRunner::RunnerManager(KConfigGroup(config, QStringLiteral("Plugins")), KConfigGroup(state, QStringLiteral("History")), this);
    m_manager->setAllowedRunners(KConfigGroup(config, QStringLiteral("General")).readEntry("Runners", defaultRunners(m_desktop)));
    m_manager->setHistoryEnabled(false);

    connect(m_manager, &KRunner::RunnerManager::matchesChanged, this, [this](const QList<KRunner::QueryMatch> &matches) {
        QElapsedTimer model;
        model.start();
        m_results.setMatches(matches, !m_mode.isEmpty());
        setCurrent(true);
        if (model.elapsed() > 20) {
            trace("result rows built", model.elapsed());
        }
        if (m_tracing) {
            qInfo("kwick-spotlight: %lld matches for \"%s\" after %lld ms", static_cast<long long>(matches.size()), qPrintable(m_query), static_cast<long long>(m_keyClock.elapsed()));
        }
        if (m_waitResults) {
            m_waitResults = false;
            m_waitFrame = true;
        }
    });
    connect(m_manager, &KRunner::RunnerManager::queryingChanged, this, &Spotlight::queryingChanged);
    connect(m_manager, &KRunner::RunnerManager::queryFinished, this, [this]() {
        if (m_keyClock.isValid()) {
            trace("query finished", m_keyClock.elapsed());
        }
    });
    connect(m_manager, &KRunner::RunnerManager::requestUpdateQueryString, this, &Spotlight::queryReplaced);

    QDir().mkpath(configDir() + QStringLiteral("/kwick"));
    refreshFiles();
    m_watcher = new QFileSystemWatcher(this);
    watchFiles();
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, [this]() {
        watchFiles();
        refreshFiles();
    });
    connect(m_watcher, &QFileSystemWatcher::fileChanged, this, [this]() {
        watchFiles();
        refreshFiles();
    });

    if (m_desktop == QLatin1String("kde")) {
        m_action = new QAction(this);
        m_action->setObjectName(QStringLiteral("toggle"));
        m_action->setText(QStringLiteral("Search"));
        connect(m_action, &QAction::triggered, this, [this]() {
            m_openClock.start();
            toggle();
        });
        applyShortcuts();
        auto *clip = new QAction(this);
        clip->setObjectName(QStringLiteral("clipboard"));
        clip->setText(QStringLiteral("Clipboard History"));
        connect(clip, &QAction::triggered, this, [this]() {
            if (m_shown && m_mode == QLatin1String("clipboard")) {
                hide();
                return;
            }
            setMode(QStringLiteral("clipboard"));
            setQuery(QString());
            show();
            Q_EMIT queryReplaced(QString(), 0);
        });
        const QKeySequence clipKey(Qt::META | Qt::Key_V);
        KConfigGroup clipGroup(KSharedConfig::openConfig(QStringLiteral("kwickspotlightrc")), QStringLiteral("Shortcuts"));
        if (!clipGroup.readEntry("Clipboard", false)) {
            if (!KGlobalAccel::isGlobalShortcutAvailable(clipKey, QCoreApplication::applicationName())) {
                KGlobalAccel::stealShortcutSystemwide(clipKey);
            }
            KGlobalAccel::self()->setDefaultShortcut(clip, {clipKey}, KGlobalAccel::NoAutoloading);
            KGlobalAccel::self()->setShortcut(clip, {clipKey}, KGlobalAccel::NoAutoloading);
            clipGroup.writeEntry("Clipboard", true);
            clipGroup.sync();
        } else {
            KGlobalAccel::self()->setDefaultShortcut(clip, {clipKey}, KGlobalAccel::NoAutoloading);
            KGlobalAccel::self()->setShortcut(clip, {clipKey}, KGlobalAccel::Autoloading);
        }
    }

    trace("started", clock.elapsed());
    if (m_tracing) {
        auto *beat = new QTimer(this);
        auto last = std::make_shared<QElapsedTimer>();
        last->start();
        connect(beat, &QTimer::timeout, this, [this, last]() {
            const qint64 gap = last->restart();
            if (gap > 60) {
                trace("main thread stalled", gap);
            }
        });
        beat->start(10);
    }
    QTimer::singleShot(0, this, [this]() {
        createView();
        queueRunners();
    });
}

Spotlight::~Spotlight()
{
    delete m_view;
}

void Spotlight::watchFiles()
{
    const QStringList paths = {configDir() + QStringLiteral("/kwick"), kwickFile(QStringLiteral("layout")), kwickFile(QStringLiteral("appearance"))};
    for (const QString &path : paths) {
        if (QFile::exists(path) && !m_watcher->files().contains(path) && !m_watcher->directories().contains(path)) {
            m_watcher->addPath(path);
        }
    }
}

void Spotlight::refreshFiles()
{
    QString layout = readKwick(QStringLiteral("layout"));
    if (layout.isEmpty()) {
        layout = QStringLiteral("macos");
    }
    const bool dark = readKwick(QStringLiteral("appearance")) != QLatin1String("light");
    if (dark != m_dark) {
        m_dark = dark;
        Q_EMIT darkChanged();
    }
    if (layout == m_layout) {
        return;
    }
    m_layout = layout;
    Q_EMIT layoutChanged();
    if (m_desktop != QLatin1String("kde")) {
        QIcon::setThemeName(iconThemeFor(layout));
    }
    if (m_action) {
        applyShortcuts();
    }
}

void Spotlight::applyShortcuts()
{
    KConfigGroup group(KSharedConfig::openConfig(QStringLiteral("kwickspotlightrc")), QStringLiteral("Shortcuts"));
    const QList<QKeySequence> keys = shortcutsFor(m_layout);
    const bool changed = !group.readEntry("Managed", false) && group.readEntry("Layout", QString()) != m_layout;
    if (changed) {
        for (const QKeySequence &key : keys) {
            if (!KGlobalAccel::isGlobalShortcutAvailable(key, QCoreApplication::applicationName())) {
                KGlobalAccel::stealShortcutSystemwide(key);
            }
        }
    }
    KGlobalAccel::self()->setDefaultShortcut(m_action, keys, KGlobalAccel::NoAutoloading);
    KGlobalAccel::self()->setShortcut(m_action, keys, changed ? KGlobalAccel::NoAutoloading : KGlobalAccel::Autoloading);
    if (changed) {
        group.writeEntry("Layout", m_layout);
        group.sync();
    }
}

void Spotlight::queueRunners()
{
    KSharedConfig::Ptr config = KSharedConfig::openConfig(QStringLiteral("kwickspotlightrc"));
    const KConfigGroup plugins(config, QStringLiteral("Plugins"));
    const QStringList allowed = KConfigGroup(config, QStringLiteral("General")).readEntry("Runners", defaultRunners(m_desktop));
    QList<KPluginMetaData> offers = KRunner::RunnerManager::runnerMetaDataList();
    offers.erase(std::remove_if(offers.begin(),
                                offers.end(),
                                [&](const KPluginMetaData &data) {
                                    return !allowed.contains(data.pluginId()) || !data.isEnabled(plugins);
                                }),
                 offers.end());
    std::stable_sort(offers.begin(), offers.end(), [&allowed](const KPluginMetaData &a, const KPluginMetaData &b) {
        return allowed.indexOf(a.pluginId()) < allowed.indexOf(b.pluginId());
    });
    m_pendingRunners = offers;
    loadNextRunner();
}

void Spotlight::loadNextRunner()
{
    if (m_pendingRunners.isEmpty()) {
        return;
    }
    const KPluginMetaData data = m_pendingRunners.takeFirst();
    QElapsedTimer clock;
    clock.start();
    const bool loaded = m_manager->loadRunner(data);
    if (loaded) {
        m_loaded.insert(data.pluginId());
    }
    if (m_tracing) {
        qInfo("kwick-spotlight: runner %s %s in %lld ms", qPrintable(data.pluginId()), loaded ? "loaded" : "failed", static_cast<long long>(clock.elapsed()));
    }
    if (loaded && m_shown && !m_launched.isEmpty() && m_mode.isEmpty()) {
        relaunch();
    }
    if (!m_pendingRunners.isEmpty()) {
        QTimer::singleShot(0, this, &Spotlight::loadNextRunner);
    }
}

bool Spotlight::ensureRunner(const QString &id)
{
    for (int i = 0; i < m_pendingRunners.size(); ++i) {
        if (m_pendingRunners.at(i).pluginId() == id) {
            const KPluginMetaData data = m_pendingRunners.takeAt(i);
            if (m_manager->loadRunner(data)) {
                m_loaded.insert(id);
            }
            break;
        }
    }
    return m_loaded.contains(id);
}

void Spotlight::createView()
{
    if (m_view) {
        return;
    }
    QElapsedTimer clock;
    clock.start();
    m_view = new QQuickView();
    m_view->setColor(Qt::transparent);
    m_view->setTitle(QStringLiteral("Search"));
    m_view->setResizeMode(QQuickView::SizeRootObjectToView);

    if (m_layered) {
        m_view->setFlags(m_shown ? Qt::FramelessWindowHint : Qt::FramelessWindowHint | Qt::WindowTransparentForInput);
        m_layer = LayerShellQt::Window::get(m_view);
        m_layer->setScope(QStringLiteral("kwick-spotlight"));
        if (m_shown) {
            m_layer->setAnchors({LayerShellQt::Window::AnchorTop, LayerShellQt::Window::AnchorBottom, LayerShellQt::Window::AnchorLeft, LayerShellQt::Window::AnchorRight});
        } else {
            m_layer->setAnchors(LayerShellQt::Window::AnchorTop);
            m_view->resize(1, 1);
        }
        m_layer->setExclusiveZone(-1);
        m_layer->setScreenConfiguration(LayerShellQt::Window::ScreenFromCompositor);
        m_layer->setLayer(m_shown ? LayerShellQt::Window::LayerOverlay : LayerShellQt::Window::LayerBackground);
        m_layer->setKeyboardInteractivity(m_shown ? LayerShellQt::Window::KeyboardInteractivityExclusive : LayerShellQt::Window::KeyboardInteractivityNone);
    } else {
        m_view->setFlags(Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint);
        connect(m_view, &QWindow::activeChanged, this, [this]() {
            if (m_view->isActive()) {
                m_wasActive = true;
            } else if (m_shown && m_wasActive) {
                hide();
            }
        });
    }

    m_view->installEventFilter(this);
    m_view->rootContext()->setContextProperty(QStringLiteral("spotlight"), this);
    m_view->rootContext()->setContextProperty(QStringLiteral("results"), &m_results);
    const QString qml = qEnvironmentVariable("KWICK_SPOTLIGHT_QML", QStringLiteral("/usr/share/kwick/spotlight/Spotlight.qml"));
    m_view->setSource(QUrl::fromLocalFile(qml));

    auto fit = [this]() {
        if (QQuickItem *root = m_view->rootObject()) {
            root->setSize(m_view->size());
        }
    };
    connect(m_view, &QWindow::widthChanged, this, fit);
    connect(m_view, &QWindow::heightChanged, this, fit);
    connect(m_view, &QQuickWindow::frameSwapped, this, [this]() {
        if (m_openClock.isValid() && m_shown && m_view->width() > 1) {
            trace("open to first frame", m_openClock.elapsed());
            m_openClock.invalidate();
        }
        if (m_waitFrame) {
            m_waitFrame = false;
            trace("keystroke to results frame", m_keyClock.elapsed());
        }
    });
    if (m_layered) {
        if (!m_shown) {
            m_view->resize(1, 1);
        }
        m_view->show();
    }
    trace("view created", clock.elapsed());
}

bool Spotlight::eventFilter(QObject *object, QEvent *event)
{
    if (object != m_view || event->type() != QEvent::KeyPress || !m_shown || m_view->activeFocusItem()) {
        return QObject::eventFilter(object, event);
    }
    auto *key = static_cast<QKeyEvent *>(event);
    if (key->key() == Qt::Key_Escape) {
        hide();
        return true;
    }
    if (key->key() == Qt::Key_Return || key->key() == Qt::Key_Enter) {
        Q_EMIT submitted();
        return true;
    }
    const QString text = key->text();
    if (!text.isEmpty() && text.at(0).isPrint() && !(key->modifiers() & (Qt::ControlModifier | Qt::AltModifier | Qt::MetaModifier))) {
        Q_EMIT typed(text);
        return true;
    }
    return QObject::eventFilter(object, event);
}

void Spotlight::commit()
{
    QPlatformNativeInterface *native = QGuiApplication::platformNativeInterface();
    auto *surface = static_cast<wl_surface *>(native->nativeResourceForWindow("surface", m_view));
    auto *display = static_cast<wl_display *>(native->nativeResourceForIntegration("wl_display"));
    if (surface && display) {
        wl_surface_commit(surface);
        wl_display_flush(display);
    }
}

void Spotlight::trace(const char *what, qint64 ms) const
{
    if (m_tracing) {
        qInfo("kwick-spotlight: %s %lld ms", what, static_cast<long long>(ms));
    }
}

QString Spotlight::query() const
{
    return m_query;
}

void Spotlight::setQuery(const QString &query)
{
    if (query == m_query) {
        return;
    }
    m_query = query;
    Q_EMIT queryChanged();
    launch();
}

QString Spotlight::mode() const
{
    return m_mode;
}

void Spotlight::setMode(const QString &mode)
{
    if (mode == m_mode) {
        return;
    }
    m_mode = mode;
    Q_EMIT modeChanged();
    launch();
}

QString Spotlight::material() const
{
    return m_material;
}

int Spotlight::cornerRadius() const
{
    return m_cornerRadius;
}

QColor Spotlight::accent() const
{
    return m_accent;
}

bool Spotlight::querying() const
{
    return m_manager->querying();
}

bool Spotlight::clipboard() const
{
    return m_clipboard;
}

bool Spotlight::dark() const
{
    return m_dark;
}

bool Spotlight::current() const
{
    return m_current;
}

void Spotlight::setCurrent(bool current)
{
    if (current != m_current) {
        m_current = current;
        Q_EMIT currentChanged();
    }
}

void Spotlight::launch()
{
    const QString text = m_query.trimmed();
    const QString key = m_mode + QChar(0x1f) + text;
    if (key == m_launched) {
        return;
    }
    m_keyClock.start();
    m_waitResults = true;
    if (m_mode.isEmpty()) {
        if (text.isEmpty()) {
            m_launched.clear();
            m_waitResults = false;
            m_manager->reset();
            m_results.clear();
            setCurrent(true);
            return;
        }
        m_launched = key;
        setCurrent(false);
        if (m_loaded.isEmpty() && !m_pendingRunners.isEmpty()) {
            loadNextRunner();
        }
        m_manager->launchQuery(m_query);
        return;
    }
    m_launched = key;
    setCurrent(false);
    if (m_mode == QLatin1String("apps") && !text.isEmpty() && m_desktop == QLatin1String("kde")) {
        if (ensureRunner(QStringLiteral("krunner_services"))) {
            m_manager->launchQuery(m_query, QStringLiteral("krunner_services"));
        }
        return;
    }
    const QChar letter = m_mode == QLatin1String("apps") ? QLatin1Char('a')
        : m_mode == QLatin1String("files")               ? QLatin1Char('f')
        : m_mode == QLatin1String("actions")             ? QLatin1Char('x')
                                                         : QLatin1Char('c');
    if (ensureRunner(QStringLiteral("krunner_kwick"))) {
        m_manager->launchQuery(QString(ModeMark) + letter + text, QStringLiteral("krunner_kwick"));
    }
}

void Spotlight::relaunch()
{
    if (m_relaunchQueued) {
        return;
    }
    m_relaunchQueued = true;
    QTimer::singleShot(0, this, [this]() {
        m_relaunchQueued = false;
        if (m_launched.isEmpty()) {
            return;
        }
        m_launched.clear();
        m_manager->reset();
        launch();
    });
}

void Spotlight::setMaterial(const QString &material)
{
    if (material != m_material) {
        m_material = material;
        Q_EMIT materialChanged();
    }
}

void Spotlight::probeHyprland()
{
    const QString signature = qEnvironmentVariable("HYPRLAND_INSTANCE_SIGNATURE");
    QString path = qEnvironmentVariable("XDG_RUNTIME_DIR") + QStringLiteral("/hypr/") + signature + QStringLiteral("/.socket.sock");
    if (!QFile::exists(path)) {
        path = QStringLiteral("/tmp/hypr/") + signature + QStringLiteral("/.socket.sock");
    }
    auto *socket = new QLocalSocket(this);
    auto finish = [this, socket]() {
        if (socket->property("done").toBool()) {
            return;
        }
        socket->setProperty("done", true);
        const QByteArray reply = socket->readAll();
        setMaterial(reply.contains("int: 1") ? QStringLiteral("blur") : QStringLiteral("solid"));
        socket->deleteLater();
    };
    connect(socket, &QLocalSocket::connected, socket, [socket]() {
        socket->write("getoption decoration:blur:enabled");
        socket->flush();
    });
    connect(socket, &QLocalSocket::disconnected, this, finish);
    connect(socket, &QLocalSocket::errorOccurred, this, finish);
    socket->connectToServer(path);
}

void Spotlight::refreshEnvironment()
{
    int radius = 10;
    const QString kwickRadius = readKwick(QStringLiteral("radius"));
    bool numeric = false;
    const int fileRadius = kwickRadius.toInt(&numeric);
    if (numeric) {
        radius = fileRadius;
    }
    if (m_desktop == QLatin1String("kde")) {
        KSharedConfig::Ptr kwinrc = KSharedConfig::openConfig(QStringLiteral("kwinrc"));
        kwinrc->reparseConfiguration();
        radius = KConfigGroup(kwinrc, QStringLiteral("Round-Corners")).readEntry("Size", radius);
        radius = KConfigGroup(kwinrc, QStringLiteral("Effect-kwick_liquidglass")).readEntry("Radius", radius);
    }
    if (radius != m_cornerRadius) {
        m_cornerRadius = radius;
        Q_EMIT cornerRadiusChanged();
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
    if (accent != m_accent) {
        m_accent = accent;
        Q_EMIT accentChanged();
    }

    if (m_desktop == QLatin1String("hyprland")) {
        probeHyprland();
    } else if (m_desktop == QLatin1String("kde") && m_layered) {
        auto *glass = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(effectLoaded(QStringLiteral("kwick_liquidglass"))), this);
        connect(glass, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
            call->deleteLater();
            const QDBusPendingReply<bool> reply = *call;
            if (reply.isValid() && reply.value()) {
                setMaterial(QStringLiteral("glass"));
                return;
            }
            auto *blur = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(effectLoaded(QStringLiteral("blur"))), this);
            connect(blur, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
                call->deleteLater();
                const QDBusPendingReply<bool> reply = *call;
                setMaterial(reply.isValid() && reply.value() ? QStringLiteral("blur") : QStringLiteral("solid"));
            });
        });
    } else {
        setMaterial(QStringLiteral("solid"));
    }

    auto *klipper = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().interface()->asyncCall(QStringLiteral("NameHasOwner"), QStringLiteral("org.kde.klipper")), this);
    connect(klipper, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
        call->deleteLater();
        const QDBusPendingReply<bool> reply = *call;
        const QString store = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/kwick/clipboard/");
        const bool available = (reply.isValid() && reply.value()) || QFileInfo::exists(store + QStringLiteral("history")) || QFileInfo::exists(store + QStringLiteral("pinned"));
        if (available != m_clipboard) {
            m_clipboard = available;
            Q_EMIT clipboardChanged();
        }
    });
}

void Spotlight::toggle()
{
    if (m_shown) {
        hide();
    } else {
        show();
    }
}

bool Spotlight::shown() const
{
    return m_shown;
}

QString Spotlight::layout() const
{
    return m_layout;
}

void Spotlight::show()
{
    if (m_shown) {
        return;
    }
    if (!m_openClock.isValid()) {
        m_openClock.start();
    }
    const bool created = m_view;
    m_shown = true;
    createView();
    if (m_layered && created) {
        m_layer->setLayer(LayerShellQt::Window::LayerOverlay);
        m_layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityExclusive);
        m_layer->setAnchors({LayerShellQt::Window::AnchorTop, LayerShellQt::Window::AnchorBottom, LayerShellQt::Window::AnchorLeft, LayerShellQt::Window::AnchorRight});
        m_view->setFlag(Qt::WindowTransparentForInput, false);
        commit();
    } else if (!m_layered) {
        m_wasActive = false;
        m_view->showMaximized();
        if (qEnvironmentVariableIsSet("XDG_ACTIVATION_TOKEN")) {
            m_view->requestActivate();
        }
    }
    trace("shown", m_openClock.elapsed());
    refreshFiles();
    Q_EMIT shownChanged();
    Q_EMIT activated();
    m_view->update();
    QTimer::singleShot(0, this, [this]() {
        if (!m_shown) {
            return;
        }
        m_manager->setupMatchSession();
        refreshEnvironment();
        if (!m_query.trimmed().isEmpty() || !m_mode.isEmpty()) {
            m_launched.clear();
            m_manager->reset();
            launch();
        }
    });
}

void Spotlight::hide()
{
    if (!m_shown) {
        return;
    }
    m_shown = false;
    if (m_layered) {
        if (m_desktop == QLatin1String("kde")) {
            KWindowEffects::enableBlurBehind(m_view, false);
        }
        m_layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
        m_layer->setLayer(LayerShellQt::Window::LayerBackground);
        m_layer->setAnchors(LayerShellQt::Window::AnchorTop);
        m_view->resize(1, 1);
        m_view->setFlag(Qt::WindowTransparentForInput, true);
        commit();
    } else {
        m_view->hide();
    }
    Q_EMIT shownChanged();
    m_view->update();
    m_manager->matchSessionComplete();
    if (!m_mode.isEmpty()) {
        m_mode.clear();
        Q_EMIT modeChanged();
        if (m_query.trimmed().isEmpty()) {
            m_launched.clear();
            m_manager->reset();
            m_results.clear();
            setCurrent(true);
        }
    }
}

void Spotlight::run(int row, bool alternate)
{
    const KRunner::QueryMatch match = m_results.match(row);
    if (!match.isValid() || !match.isEnabled()) {
        return;
    }
    const KRunner::Action action = alternate && !match.actions().isEmpty() ? match.actions().constFirst() : KRunner::Action();
    if (m_manager->run(match, action)) {
        hide();
    }
}

bool Spotlight::preview(int row)
{
    const KRunner::QueryMatch match = m_results.match(row);
    if (!match.isValid()) {
        return false;
    }
    QString path;
    const QVariantList data = match.data().toList();
    if (data.value(0).toString() == QLatin1String("file")) {
        path = data.value(1).toString();
    } else if (!match.urls().isEmpty() && match.urls().constFirst().isLocalFile()) {
        path = match.urls().constFirst().toLocalFile();
    }
    if (path.isEmpty() || QStandardPaths::findExecutable(QStringLiteral("kwick-quicklook")).isEmpty()) {
        return false;
    }
    hide();
    QProcess::startDetached(QStringLiteral("kwick-quicklook"), {QStringLiteral("--toggle"), path});
    return true;
}

void Spotlight::setPanel(qreal x, qreal y, qreal width, qreal height, qreal radius)
{
    if (!m_shown || !m_layered || m_desktop != QLatin1String("kde")) {
        return;
    }
    QPainterPath path;
    path.addRoundedRect(QRectF(QRectF(x, y, width, height).toAlignedRect()), radius, radius);
    KWindowEffects::enableBlurBehind(m_view, true, QRegion(path.toFillPolygon().toPolygon()));
}

void Spotlight::handle(const QStringList &arguments)
{
    QCommandLineParser parser;
    parser.addOption({QStringLiteral("daemon"), QStringLiteral("Start in the background without showing the search.")});
    parser.addOption({QStringLiteral("hide"), QStringLiteral("Close the search.")});
    parser.addOption({QStringLiteral("show"), QStringLiteral("Show the search, do not toggle it.")});
    parser.addOption({QStringLiteral("query"), QStringLiteral("Show the search with this text."), QStringLiteral("text")});
    parser.addOption({QStringLiteral("mode"), QStringLiteral("Browse apps, files, actions or clipboard."), QStringLiteral("mode")});
    parser.addOption({QStringLiteral("append"), QStringLiteral("Show the search and type this text into it."), QStringLiteral("text")});
    parser.addOption({QStringLiteral("submit"), QStringLiteral("Show the search and open the selected result.")});
    parser.parse(arguments);
    if (parser.isSet(QStringLiteral("daemon"))) {
        return;
    }
    if (parser.isSet(QStringLiteral("hide"))) {
        hide();
        return;
    }
    if (parser.isSet(QStringLiteral("append")) || parser.isSet(QStringLiteral("submit"))) {
        show();
        if (parser.isSet(QStringLiteral("append"))) {
            Q_EMIT typed(parser.value(QStringLiteral("append")));
        }
        if (parser.isSet(QStringLiteral("submit"))) {
            Q_EMIT submitted();
        }
        return;
    }
    m_openClock.start();
    if (parser.isSet(QStringLiteral("query")) || parser.isSet(QStringLiteral("mode"))) {
        setMode(parser.value(QStringLiteral("mode")));
        setQuery(parser.value(QStringLiteral("query")));
        show();
        Q_EMIT queryReplaced(m_query, int(m_query.size()));
        return;
    }
    if (parser.isSet(QStringLiteral("show"))) {
        show();
        return;
    }
    toggle();
}
