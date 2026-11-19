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
#include <QFile>
#include <QFileSystemWatcher>
#include <QGuiApplication>
#include <QPainterPath>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickView>
#include <QStandardPaths>
#include <QTimer>
#include <qpa/qplatformnativeinterface.h>

#include <wayland-client-protocol.h>

namespace
{
const QChar ModeMark = QChar(0x1);

QString configDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation);
}

QString currentLayout()
{
    QFile file(configDir() + QStringLiteral("/kwick/layout"));
    return file.open(QIODevice::ReadOnly) ? QString::fromUtf8(file.readAll()).trimmed() : QStringLiteral("macos");
}

QList<QKeySequence> shortcutsFor(const QString &layout)
{
    if (layout == QLatin1String("windows")) {
        return {QKeySequence(Qt::META | Qt::Key_S), QKeySequence(Qt::META | Qt::Key_Space)};
    }
    return {QKeySequence(Qt::META | Qt::Key_Space)};
}

QStringList defaultRunners()
{
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
    , m_tracing(qEnvironmentVariableIsSet("KWICK_SPOTLIGHT_TRACE"))
{
    KSharedConfig::Ptr config = KSharedConfig::openConfig(QStringLiteral("kwickspotlightrc"));
    KSharedConfig::Ptr state = KSharedConfig::openStateConfig(QStringLiteral("kwickspotlightstaterc"));
    m_manager = new KRunner::RunnerManager(KConfigGroup(config, QStringLiteral("Plugins")), KConfigGroup(state, QStringLiteral("History")), this);
    m_manager->setAllowedRunners(KConfigGroup(config, QStringLiteral("General")).readEntry("Runners", defaultRunners()));
    m_manager->setHistoryEnabled(false);

    connect(m_manager, &KRunner::RunnerManager::matchesChanged, this, [this](const QList<KRunner::QueryMatch> &matches) {
        m_results.setMatches(matches, !m_mode.isEmpty());
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

    m_action = new QAction(this);
    m_action->setObjectName(QStringLiteral("toggle"));
    m_action->setText(QStringLiteral("Spotlight Search"));
    connect(m_action, &QAction::triggered, this, [this]() {
        m_openClock.start();
        toggle();
    });
    applyShortcuts();
    m_watcher = new QFileSystemWatcher({configDir() + QStringLiteral("/kwick")}, this);
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, &Spotlight::applyShortcuts);

    QTimer::singleShot(3000, this, [this]() {
        createView();
        m_manager->runners();
    });
}

Spotlight::~Spotlight()
{
    delete m_view;
}

void Spotlight::applyShortcuts()
{
    const QString layout = currentLayout();
    if (layout != m_layout) {
        m_layout = layout;
        Q_EMIT layoutChanged();
    }
    KConfigGroup group(KSharedConfig::openConfig(QStringLiteral("kwickspotlightrc")), QStringLiteral("Shortcuts"));
    const QList<QKeySequence> keys = shortcutsFor(layout);
    const bool changed = group.readEntry("Layout", QString()) != layout;
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
        group.writeEntry("Layout", layout);
        group.sync();
    }
}

void Spotlight::createView()
{
    if (m_view) {
        return;
    }
    m_view = new QQuickView();
    m_view->setColor(Qt::transparent);
    m_view->setFlags(Qt::FramelessWindowHint | Qt::WindowTransparentForInput);
    m_view->setResizeMode(QQuickView::SizeRootObjectToView);
    m_view->resize(1, 1);

    m_layer = LayerShellQt::Window::get(m_view);
    m_layer->setScope(QStringLiteral("kwick-spotlight"));
    m_layer->setAnchors(LayerShellQt::Window::AnchorTop);
    m_layer->setExclusiveZone(-1);
    m_layer->setScreenConfiguration(LayerShellQt::Window::ScreenFromCompositor);
    m_layer->setLayer(LayerShellQt::Window::LayerBackground);
    m_layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);

    m_view->rootContext()->setContextProperty(QStringLiteral("spotlight"), this);
    m_view->rootContext()->setContextProperty(QStringLiteral("results"), &m_results);
    const QString qml = qEnvironmentVariable("KWICK_SPOTLIGHT_QML", QStringLiteral("/usr/share/kwick/spotlight/Spotlight.qml"));
    m_view->setSource(QUrl::fromLocalFile(qml));
    m_view->resize(1, 1);

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
    }, Qt::DirectConnection);
    m_view->show();
}

void Spotlight::commit()
{
    QPlatformNativeInterface *native = QGuiApplication::platformNativeInterface();
    auto *surface = static_cast<wl_surface *>(native->nativeResourceForWindow("surface", m_view));
    auto *display = static_cast<wl_display *>(native->nativeResourceForIntegration("wl_display"));
    if (surface && display) {
        wl_surface_damage(surface, 0, 0, INT32_MAX, INT32_MAX);
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

void Spotlight::launch()
{
    m_keyClock.start();
    m_waitResults = true;
    const QString text = m_query.trimmed();
    if (m_mode.isEmpty()) {
        if (text.isEmpty()) {
            m_waitResults = false;
            m_manager->reset();
            m_results.clear();
            return;
        }
        m_manager->launchQuery(m_query);
        return;
    }
    if (m_mode == QLatin1String("apps") && !text.isEmpty()) {
        m_manager->launchQuery(m_query, QStringLiteral("krunner_services"));
        return;
    }
    const QChar letter = m_mode == QLatin1String("apps") ? QLatin1Char('a')
        : m_mode == QLatin1String("files")               ? QLatin1Char('f')
        : m_mode == QLatin1String("actions")             ? QLatin1Char('x')
                                                         : QLatin1Char('c');
    m_manager->launchQuery(QString(ModeMark) + letter + text, QStringLiteral("krunner_kwick"));
}

void Spotlight::refreshEnvironment()
{
    KSharedConfig::Ptr kwinrc = KSharedConfig::openConfig(QStringLiteral("kwinrc"));
    kwinrc->reparseConfiguration();
    int radius = KConfigGroup(kwinrc, QStringLiteral("Round-Corners")).readEntry("Size", 10);
    radius = KConfigGroup(kwinrc, QStringLiteral("Effect-kwick_liquidglass")).readEntry("Radius", radius);
    if (radius != m_cornerRadius) {
        m_cornerRadius = radius;
        Q_EMIT cornerRadiusChanged();
    }
    KSharedConfig::Ptr globals = KSharedConfig::openConfig(QStringLiteral("kdeglobals"));
    globals->reparseConfiguration();
    const QColor accent = KConfigGroup(globals, QStringLiteral("General")).readEntry("AccentColor", QColor());
    if (accent != m_accent) {
        m_accent = accent;
        Q_EMIT accentChanged();
    }

    auto *glass = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(effectLoaded(QStringLiteral("kwick_liquidglass"))), this);
    connect(glass, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
        call->deleteLater();
        const QDBusPendingReply<bool> reply = *call;
        if (reply.isValid() && reply.value()) {
            if (m_material != QLatin1String("glass")) {
                m_material = QStringLiteral("glass");
                Q_EMIT materialChanged();
            }
            return;
        }
        auto *blur = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(effectLoaded(QStringLiteral("blur"))), this);
        connect(blur, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
            call->deleteLater();
            const QDBusPendingReply<bool> reply = *call;
            const QString material = reply.isValid() && reply.value() ? QStringLiteral("blur") : QStringLiteral("solid");
            if (material != m_material) {
                m_material = material;
                Q_EMIT materialChanged();
            }
        });
    });

    auto *klipper = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().interface()->asyncCall(QStringLiteral("NameHasOwner"), QStringLiteral("org.kde.klipper")), this);
    connect(klipper, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
        call->deleteLater();
        const QDBusPendingReply<bool> reply = *call;
        const bool available = reply.isValid() && reply.value();
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
    createView();
    m_shown = true;
    m_layer->setAnchors({LayerShellQt::Window::AnchorTop, LayerShellQt::Window::AnchorBottom, LayerShellQt::Window::AnchorLeft, LayerShellQt::Window::AnchorRight});
    m_layer->setLayer(LayerShellQt::Window::LayerOverlay);
    m_layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityExclusive);
    m_view->setFlag(Qt::WindowTransparentForInput, false);
    Q_EMIT shownChanged();
    Q_EMIT activated();
    commit();
    m_view->requestActivate();
    m_view->update();
    trace("shown", m_openClock.elapsed());
    QTimer::singleShot(0, this, [this]() {
        if (!m_shown) {
            return;
        }
        m_manager->setupMatchSession();
        refreshEnvironment();
        if (!m_query.trimmed().isEmpty()) {
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
    KWindowEffects::enableBlurBehind(m_view, false);
    m_layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityNone);
    m_layer->setLayer(LayerShellQt::Window::LayerBackground);
    m_view->resize(1, 1);
    m_layer->setAnchors(LayerShellQt::Window::AnchorTop);
    m_view->setFlag(Qt::WindowTransparentForInput, true);
    Q_EMIT shownChanged();
    m_view->update();
    m_manager->matchSessionComplete();
    if (!m_mode.isEmpty()) {
        m_mode.clear();
        Q_EMIT modeChanged();
        if (m_query.trimmed().isEmpty()) {
            m_results.clear();
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

void Spotlight::setPanel(qreal x, qreal y, qreal width, qreal height, qreal radius)
{
    if (!m_shown) {
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
    parser.addOption({QStringLiteral("query"), QStringLiteral("Show the search with this text."), QStringLiteral("text")});
    parser.addOption({QStringLiteral("mode"), QStringLiteral("Browse apps, files, actions or clipboard."), QStringLiteral("mode")});
    parser.parse(arguments);
    if (parser.isSet(QStringLiteral("daemon"))) {
        return;
    }
    if (parser.isSet(QStringLiteral("hide"))) {
        hide();
        return;
    }
    if (parser.isSet(QStringLiteral("query")) || parser.isSet(QStringLiteral("mode"))) {
        m_openClock.start();
        setMode(parser.value(QStringLiteral("mode")));
        setQuery(parser.value(QStringLiteral("query")));
        show();
        Q_EMIT queryReplaced(m_query, int(m_query.size()));
        return;
    }
    m_openClock.start();
    toggle();
}
