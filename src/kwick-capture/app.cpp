#include "app.h"

#include "canvas.h"
#include "images.h"
#include "portal.h"
#include "recorder.h"

#include <KConfigGroup>
#include <LayerShellQt/Window>

#include <QBuffer>
#include <QClipboard>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QIcon>
#include <QMimeData>
#include <QProcess>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickView>
#include <QRegion>
#include <QRegularExpression>
#include <QSaveFile>
#include <QScreen>
#include <QStandardPaths>
#include <QThreadPool>
#include <QUrl>

#include <array>
#include <memory>

App *App::s_instance = nullptr;

namespace
{
QString configDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation);
}

QString readKwick(const QString &name)
{
    QFile file(configDir() + QStringLiteral("/kwick/") + name);
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

QByteArray encodePng(const QImage &image)
{
    QByteArray bytes;
    QBuffer buffer(&bytes);
    buffer.open(QIODevice::WriteOnly);
    image.save(&buffer, "PNG", 70);
    return bytes;
}

QString cacheDir()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + QStringLiteral("/kwick-capture");
    QDir().mkpath(dir);
    return dir;
}
}

App::App(const QString &desktop, QObject *parent)
    : QObject(parent)
    , m_desktop(desktop.isEmpty() ? detectDesktop() : desktop)
{
    s_instance = this;
    const QString layer = qEnvironmentVariable("KWICK_CAPTURE_LAYER");
    m_layered = QGuiApplication::platformName().startsWith(QLatin1String("wayland")) && (layer.isEmpty() ? m_desktop != QLatin1String("gnome") : layer == QLatin1String("1"));
    QDir().mkpath(configDir() + QStringLiteral("/kwick"));
    m_config = KSharedConfig::openConfig(configDir() + QStringLiteral("/kwick/capturerc"), KConfig::SimpleConfig);
    readOptions();
    refreshTheme();

    m_grabber = new Grabber(m_desktop, this);
    m_recorder = new Recorder(m_desktop, this);
    m_recorder->setRestoreToken(KConfigGroup(m_config, QStringLiteral("Recording")).readEntry("RestoreToken", QString()));
    connect(m_recorder, &Recorder::tokenChanged, this, [this](const QString &token) {
        KConfigGroup(m_config, QStringLiteral("Recording")).writeEntry("RestoreToken", token);
        m_config->sync();
    });
    connect(m_recorder, &Recorder::started, this, [this]() {
        Q_EMIT recordingChanged();
        m_tickTimer.start();
        showPill();
        updateIdle();
    });
    connect(m_recorder, &Recorder::finished, this, [this](const QString &path) {
        m_tickTimer.stop();
        Q_EMIT recordingChanged();
        dismiss(m_pill);
        if (!path.isEmpty()) {
            m_lastPath = path;
            m_lastVideo = true;
            m_lastTemporary = false;
            m_last = QImage();
            showThumb();
        }
        updateIdle();
    });
    connect(m_recorder, &Recorder::failed, this, [this](const Failure &failure) {
        m_tickTimer.stop();
        Q_EMIT recordingChanged();
        dismiss(m_pill);
        showFailure(failure);
        updateIdle();
    });

    m_engine = new QQmlEngine(this);
    m_engine->addImageProvider(QStringLiteral("capture"), new Images([this](const QString &id) {
        return provide(id);
    }));

    m_countdownTimer.setInterval(1000);
    connect(&m_countdownTimer, &QTimer::timeout, this, [this]() {
        --m_countdown;
        Q_EMIT countdownChanged();
        if (m_countdown <= 0) {
            m_countdownTimer.stop();
            dismiss(m_pill);
            const QString mode = m_pendingMode;
            QTimer::singleShot(180, this, [this, mode]() {
                run(mode);
            });
        }
    });
    m_tickTimer.setInterval(1000);
    connect(&m_tickTimer, &QTimer::timeout, this, &App::tick);
    m_thumbTimer.setSingleShot(true);
    connect(&m_thumbTimer, &QTimer::timeout, this, [this]() {
        dismiss(m_thumb);
        updateIdle();
    });
    m_toastTimer.setSingleShot(true);
    connect(&m_toastTimer, &QTimer::timeout, this, [this]() {
        if (!m_installer) {
            dismiss(m_toast);
            m_toastCallback = nullptr;
            updateIdle();
        }
    });
    m_idleTimer.setSingleShot(true);
    m_idleTimer.setInterval(qEnvironmentVariableIntValue("KWICK_CAPTURE_IDLE") > 0 ? qEnvironmentVariableIntValue("KWICK_CAPTURE_IDLE") * 1000 : 180000);
    connect(&m_idleTimer, &QTimer::timeout, qApp, &QCoreApplication::quit);
}

App::~App()
{
    s_instance = nullptr;
}

App *App::create(QQmlEngine *, QJSEngine *)
{
    QJSEngine::setObjectOwnership(s_instance, QJSEngine::CppOwnership);
    return s_instance;
}

App *App::instance()
{
    return s_instance;
}

bool App::dark() const
{
    return m_dark;
}

QColor App::accent() const
{
    return m_accent.isValid() ? m_accent : (m_dark ? QColor(0xff, 0x9f, 0x0a) : QColor(0xff, 0x95, 0x00));
}

int App::radius() const
{
    return m_radius;
}

bool App::layered() const
{
    return m_layered;
}

QString App::desktop() const
{
    return m_desktop;
}

QString App::mode() const
{
    return m_mode;
}

void App::setMode(const QString &mode)
{
    if (mode == m_mode) {
        return;
    }
    m_mode = mode;
    writeOption("Mode", mode);
    Q_EMIT optionsChanged();
}

QString App::saveTo() const
{
    return m_saveTo;
}

void App::setSaveTo(const QString &saveTo)
{
    if (saveTo == m_saveTo) {
        return;
    }
    m_saveTo = saveTo;
    writeOption("SaveTo", saveTo);
    Q_EMIT optionsChanged();
}

int App::timer() const
{
    return m_timer;
}

void App::setTimer(int timer)
{
    if (timer == m_timer) {
        return;
    }
    m_timer = timer;
    writeOption("Timer", timer);
    Q_EMIT optionsChanged();
}

bool App::microphone() const
{
    return m_microphone;
}

void App::setMicrophone(bool on)
{
    if (on == m_microphone) {
        return;
    }
    m_microphone = on;
    writeOption("Microphone", on);
    Q_EMIT optionsChanged();
}

bool App::pointer() const
{
    return m_pointer;
}

void App::setPointer(bool on)
{
    if (on == m_pointer) {
        return;
    }
    m_pointer = on;
    writeOption("ShowPointer", on);
    Q_EMIT optionsChanged();
}

bool App::recording() const
{
    return m_recorder->active();
}

int App::recordSeconds() const
{
    return int(m_recorder->elapsed() / 1000);
}

int App::countdown() const
{
    return m_countdown;
}

QString App::thumbSource() const
{
    return m_lastVideo ? QString() : QStringLiteral("image://capture/thumb/%1").arg(m_serial);
}

QString App::thumbPath() const
{
    return m_lastPath;
}

QSize App::thumbSize() const
{
    return m_lastVideo ? QSize(16, 10) : m_last.size();
}

bool App::thumbVideo() const
{
    return m_lastVideo;
}

QString App::toastTitle() const
{
    return m_toastTitle;
}

QString App::toastBody() const
{
    return m_toastBody;
}

QString App::toastAction() const
{
    return m_toastAction;
}

QString App::toastIcon() const
{
    return m_toastIcon;
}

qreal App::toastProgress() const
{
    return m_toastProgress;
}

QColor App::picked() const
{
    return m_picked;
}

QStringList App::recent() const
{
    return m_recent;
}

void App::readOptions()
{
    const KConfigGroup group(m_config, QStringLiteral("Capture"));
    m_mode = group.readEntry("Mode", QStringLiteral("selection"));
    static const QStringList modes{QStringLiteral("screen"), QStringLiteral("window"), QStringLiteral("selection"), QStringLiteral("recordScreen"), QStringLiteral("recordSelection"), QStringLiteral("text"), QStringLiteral("color")};
    if (!modes.contains(m_mode)) {
        m_mode = QStringLiteral("selection");
    }
    m_saveTo = group.readEntry("SaveTo", QStringLiteral("desktop"));
    m_timer = group.readEntry("Timer", 0);
    m_microphone = group.readEntry("Microphone", false);
    m_pointer = group.readEntry("ShowPointer", false);
    m_recent = KConfigGroup(m_config, QStringLiteral("Colors")).readEntry("Recent", QStringList());
}

void App::writeOption(const char *key, const QVariant &value)
{
    KConfigGroup group(m_config, QStringLiteral("Capture"));
    group.writeEntry(key, value);
    m_config->sync();
}

void App::refreshTheme()
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
    if (dark != m_dark || radius != m_radius || accent != m_accent) {
        m_dark = dark;
        m_radius = radius;
        m_accent = accent;
        Q_EMIT themeChanged();
    }
}

QImage App::provide(const QString &id) const
{
    const QStringList parts = id.split(QLatin1Char('/'));
    if (parts.value(0) == QLatin1String("last") || parts.value(0) == QLatin1String("thumb")) {
        return m_last;
    }
    if (parts.value(0) == QLatin1String("frozen")) {
        const QList<QScreen *> screens = QGuiApplication::screens();
        const int index = parts.value(1).toInt();
        if (index < 0 || index >= screens.size() || m_frozen.image.isNull()) {
            return {};
        }
        return m_frozen.image.copy(pixelRect(screens.at(index)->geometry()));
    }
    return {};
}

QRect App::pixelRect(const QRectF &global) const
{
    if (m_frozen.geometry.isEmpty()) {
        return {};
    }
    const qreal sx = qreal(m_frozen.image.width()) / m_frozen.geometry.width();
    const qreal sy = qreal(m_frozen.image.height()) / m_frozen.geometry.height();
    const QRectF local = global.translated(-m_frozen.geometry.topLeft());
    const int x = qRound(local.x() * sx);
    const int y = qRound(local.y() * sy);
    return QRect(x, y, qMax(1, qRound((local.x() + local.width()) * sx) - x), qMax(1, qRound((local.y() + local.height()) * sy) - y)).intersected(m_frozen.image.rect());
}

QQuickView *App::makeView(const QString &type, const QVariantMap &properties)
{
    auto *view = new QQuickView(m_engine, nullptr);
    view->setColor(Qt::transparent);
    view->setResizeMode(QQuickView::SizeRootObjectToView);
    view->setInitialProperties(properties);
    view->loadFromModule(QStringLiteral("KwickCapture"), type);
    if (view->status() == QQuickView::Error) {
        for (const QQmlError &error : view->errors()) {
            qWarning("kwick-capture: %s", qPrintable(error.toString()));
        }
    }
    return view;
}

void App::present(QQuickView *view, const Surface &surface)
{
    if (surface.screen) {
        view->setScreen(surface.screen);
    }
    if (m_layered) {
        view->setFlags(Qt::FramelessWindowHint);
        auto *layer = LayerShellQt::Window::get(view);
        layer->setScope(surface.scope);
        layer->setLayer(surface.overlay ? LayerShellQt::Window::LayerOverlay : LayerShellQt::Window::LayerTop);
        layer->setAnchors(LayerShellQt::Window::Anchors(surface.anchors));
        layer->setMargins(surface.margins);
        layer->setExclusiveZone(-1);
        layer->setKeyboardInteractivity(!surface.keyboard ? LayerShellQt::Window::KeyboardInteractivityNone
                                            : surface.exclusive ? LayerShellQt::Window::KeyboardInteractivityExclusive
                                                                : LayerShellQt::Window::KeyboardInteractivityOnDemand);
        layer->setScreenConfiguration(surface.screen ? LayerShellQt::Window::ScreenFromQWindow : LayerShellQt::Window::ScreenFromCompositor);
        if (surface.fill && surface.screen) {
            view->resize(surface.screen->geometry().size());
        } else {
            view->resize(surface.size);
        }
        view->show();
    } else {
        view->setFlags(Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint);
        if (surface.fill) {
            view->showFullScreen();
        } else {
            view->showMaximized();
        }
    }
    if (surface.keyboard) {
        view->requestActivate();
    }
    m_idleTimer.stop();
}

void App::dismiss(QPointer<QQuickView> &view)
{
    if (view) {
        view->hide();
        view->deleteLater();
    }
    view = nullptr;
}

void App::setMask(QWindow *window, const QVariantList &rects)
{
    if (!window) {
        return;
    }
    QRegion region;
    for (const QVariant &value : rects) {
        region += value.toRectF().toAlignedRect();
    }
    window->setMask(region);
}

void App::updateIdle()
{
    const bool visible = m_bar || m_thumb || m_toast || m_pill || m_color || !m_overlays.isEmpty();
    bool markups = false;
    for (const auto &view : std::as_const(m_markups)) {
        markups = markups || view;
    }
    if (visible || markups || recording() || m_countdown > 0 || m_installer || m_busy) {
        m_idleTimer.stop();
    } else {
        m_idleTimer.start();
    }
}

void App::handle(const QStringList &arguments, const QString &workingDirectory)
{
    const QStringList args = arguments.mid(1);
    auto value = [&args](const QString &flag) {
        const int i = args.indexOf(flag);
        return i >= 0 && i + 1 < args.size() && !args.at(i + 1).startsWith(QLatin1String("--")) ? args.at(i + 1) : QString();
    };
    refreshTheme();
    if (args.contains(QStringLiteral("--stop"))) {
        stopRecording();
    } else if (args.contains(QStringLiteral("--markup"))) {
        QString file = value(QStringLiteral("--markup"));
        if (!file.isEmpty() && QFileInfo(file).isRelative()) {
            file = QDir(workingDirectory).absoluteFilePath(file);
        }
        if (file.startsWith(QLatin1String("file:"))) {
            file = QUrl(file).toLocalFile();
        }
        if (file.isEmpty() || !QFileInfo::exists(file)) {
            showToast(QStringLiteral("Markup"), QStringLiteral("The image could not be found."), QStringLiteral("markup"));
        } else {
            openMarkup(file, QImage());
        }
    } else if (args.contains(QStringLiteral("--record"))) {
        if (recording()) {
            stopRecording();
        } else {
            const QString what = value(QStringLiteral("--record"));
            trigger(what == QLatin1String("screen") ? QStringLiteral("recordScreen") : QStringLiteral("recordSelection"));
        }
    } else if (args.contains(QStringLiteral("--area"))) {
        trigger(QStringLiteral("selection"));
    } else if (args.contains(QStringLiteral("--window"))) {
        trigger(QStringLiteral("window"));
    } else if (args.contains(QStringLiteral("--screen"))) {
        trigger(QStringLiteral("screen"));
    } else if (args.contains(QStringLiteral("--text"))) {
        trigger(QStringLiteral("text"));
    } else if (args.contains(QStringLiteral("--color"))) {
        trigger(QStringLiteral("color"));
    } else if (recording()) {
        stopRecording();
    } else if (m_bar) {
        closeBar();
    } else {
        showBar();
    }
    updateIdle();
}

void App::showBar()
{
    if (!m_overlays.isEmpty() || m_countdown > 0) {
        return;
    }
    if (m_bar) {
        m_bar->requestActivate();
        return;
    }
    const int edge = m_layered ? 0 : 56;
    m_bar = makeView(QStringLiteral("Bar"), {{QStringLiteral("edge"), edge}});
    m_bar->setTitle(QStringLiteral("Capture"));
    Surface surface;
    surface.scope = QStringLiteral("kwick-capture-bar");
    surface.anchors = LayerShellQt::Window::AnchorBottom;
    surface.margins = QMargins(0, 0, 0, 84);
    surface.size = QSize(980, 440);
    surface.keyboard = true;
    surface.exclusive = true;
    if (qEnvironmentVariableIsSet("KWICK_CAPTURE_TRACE")) {
        auto *once = new QObject(m_bar);
        connect(m_bar, &QQuickWindow::frameSwapped, once, [this, once]() {
            qInfo("kwick-capture: bar frame after %lld ms in main, at %lld", static_cast<long long>(QDateTime::currentMSecsSinceEpoch() - QCoreApplication::instance()->property("started").toLongLong()), static_cast<long long>(QDateTime::currentMSecsSinceEpoch()));
            once->deleteLater();
        });
    }
    if (qEnvironmentVariableIsSet("KWICK_CAPTURE_TRACE")) {
        qInfo("kwick-capture: bar loaded at %lld ms", static_cast<long long>(QDateTime::currentMSecsSinceEpoch() - QCoreApplication::instance()->property("started").toLongLong()));
    }
    present(m_bar, surface);
    if (qEnvironmentVariableIsSet("KWICK_CAPTURE_TRACE")) {
        qInfo("kwick-capture: bar presented at %lld ms", static_cast<long long>(QDateTime::currentMSecsSinceEpoch() - QCoreApplication::instance()->property("started").toLongLong()));
    }
    Q_EMIT barShown();
}

void App::closeBar()
{
    dismiss(m_bar);
    updateIdle();
}

void App::capture()
{
    const QString mode = m_mode;
    dismiss(m_bar);
    const bool timed = m_timer > 0 && mode != QLatin1String("text") && mode != QLatin1String("color");
    if (timed) {
        m_pendingMode = mode;
        m_countdown = m_timer;
        Q_EMIT countdownChanged();
        showPill();
        m_countdownTimer.start();
        return;
    }
    QTimer::singleShot(m_layered ? 120 : 260, this, [this, mode]() {
        run(mode);
    });
}

void App::trigger(const QString &mode)
{
    const bool hadBar = m_bar;
    dismiss(m_bar);
    if (!m_overlays.isEmpty() || m_countdown > 0) {
        return;
    }
    QTimer::singleShot(hadBar ? 140 : 0, this, [this, mode]() {
        run(mode);
    });
}

void App::cancelCountdown()
{
    m_countdownTimer.stop();
    m_countdown = 0;
    Q_EMIT countdownChanged();
    dismiss(m_pill);
    updateIdle();
}

void App::withDesktop(std::function<void(const Shot &)> next)
{
    m_busy = true;
    m_grabber->desktop(m_pointer, [this, next](const Shot &shot) {
        m_busy = false;
        next(shot);
        updateIdle();
    }, [this](const Failure &failure) {
        m_busy = false;
        showFailure(failure);
        updateIdle();
    });
}

void App::run(const QString &mode)
{
    m_idleTimer.stop();
    if (mode == QLatin1String("screen")) {
        withDesktop([this](const Shot &shot) {
            finishShot(shot.image);
        });
    } else if (mode == QLatin1String("window")) {
        if (m_grabber->ownWindowPicker()) {
            withDesktop([this](const Shot &shot) {
                m_frozen = shot;
                showOverlay(QStringLiteral("window"));
            });
        } else {
            m_busy = true;
            m_grabber->window(m_pointer, [this](const Shot &shot) {
                m_busy = false;
                finishShot(shot.image);
            }, [this](const Failure &failure) {
                m_busy = false;
                showFailure(failure);
                updateIdle();
            });
        }
    } else if (mode == QLatin1String("selection") || mode == QLatin1String("text") || mode == QLatin1String("recordSelection")) {
        const QString purpose = mode == QLatin1String("selection") ? QStringLiteral("select") : mode == QLatin1String("text") ? QStringLiteral("text") : QStringLiteral("record");
        withDesktop([this, purpose](const Shot &shot) {
            m_frozen = shot;
            showOverlay(purpose);
        });
    } else if (mode == QLatin1String("recordScreen")) {
        QScreen *screen = QGuiApplication::primaryScreen();
        startRecording(false, screen ? screen->geometry() : QRect());
    } else if (mode == QLatin1String("color")) {
        pickColor();
    }
}

void App::pickColor()
{
    const bool portal = m_desktop == QLatin1String("kde") || m_desktop == QLatin1String("gnome");
    if (!portal) {
        withDesktop([this](const Shot &shot) {
            m_frozen = shot;
            showOverlay(QStringLiteral("color"));
        });
        return;
    }
    m_busy = true;
    Portal::call(QStringLiteral("org.freedesktop.portal.Screenshot"), QStringLiteral("PickColor"), {QString()}, {}, [this](uint code, const QVariantMap &results) {
        m_busy = false;
        if (code == 0) {
            const QDBusArgument argument = results.value(QStringLiteral("color")).value<QDBusArgument>();
            double r = 0;
            double g = 0;
            double b = 0;
            argument.beginStructure();
            argument >> r >> g >> b;
            argument.endStructure();
            showColor(QColor::fromRgbF(float(r), float(g), float(b)));
        } else if (results.contains(QStringLiteral("error"))) {
            withDesktop([this](const Shot &shot) {
                m_frozen = shot;
                showOverlay(QStringLiteral("color"));
            });
        }
        updateIdle();
    }, this);
}

void App::showOverlay(const QString &purpose)
{
    closeOverlays();
    m_purpose = purpose;
    ++m_serial;
    const QList<QScreen *> screens = QGuiApplication::screens();
    const QVariantList windows = purpose == QLatin1String("window") ? m_grabber->windows(m_frozen.geometry) : QVariantList();
    for (int i = 0; i < screens.size(); ++i) {
        QScreen *screen = screens.at(i);
        QVariantList local;
        for (const QVariant &value : windows) {
            QVariantMap window = value.toMap();
            const QRect rect(window.value(QStringLiteral("x")).toInt() + m_frozen.geometry.x() - screen->geometry().x(), window.value(QStringLiteral("y")).toInt() + m_frozen.geometry.y() - screen->geometry().y(), window.value(QStringLiteral("w")).toInt(), window.value(QStringLiteral("h")).toInt());
            if (!rect.intersects(QRect(QPoint(0, 0), screen->geometry().size()))) {
                continue;
            }
            window[QStringLiteral("x")] = rect.x();
            window[QStringLiteral("y")] = rect.y();
            local.append(window);
        }
        const QRect pixels = pixelRect(screen->geometry());
        const QVariantMap properties{
            {QStringLiteral("screenIndex"), i},
            {QStringLiteral("purpose"), purpose},
            {QStringLiteral("source"), QStringLiteral("image://capture/frozen/%1/%2").arg(i).arg(m_serial)},
            {QStringLiteral("pixelRatio"), screen->geometry().width() > 0 ? qreal(pixels.width()) / screen->geometry().width() : 1.0},
            {QStringLiteral("windows"), local},
        };
        QPointer<QQuickView> view = makeView(QStringLiteral("Overlay"), properties);
        view->setTitle(QStringLiteral("Capture Selection"));
        Surface surface;
        surface.scope = QStringLiteral("kwick-capture-overlay");
        surface.anchors = LayerShellQt::Window::AnchorTop | LayerShellQt::Window::AnchorBottom | LayerShellQt::Window::AnchorLeft | LayerShellQt::Window::AnchorRight;
        surface.keyboard = true;
        surface.exclusive = true;
        surface.fill = true;
        surface.screen = screen;
        present(view, surface);
        m_overlays.append(view);
    }
}

void App::releaseFrozen()
{
    QTimer::singleShot(1500, this, [this]() {
        if (m_overlays.isEmpty()) {
            m_frozen = Shot();
        }
    });
}

void App::closeOverlays()
{
    for (QPointer<QQuickView> &view : m_overlays) {
        dismiss(view);
    }
    m_overlays.clear();
}

void App::overlayCancel()
{
    closeOverlays();
    releaseFrozen();
    updateIdle();
}

void App::overlayDone(int screenIndex, qreal x, qreal y, qreal w, qreal h)
{
    const QList<QScreen *> screens = QGuiApplication::screens();
    if (screenIndex < 0 || screenIndex >= screens.size()) {
        overlayCancel();
        return;
    }
    const QRectF global = QRectF(x, y, w, h).translated(screens.at(screenIndex)->geometry().topLeft());
    const QRect pixels = pixelRect(global);
    const QString purpose = m_purpose;
    const QImage image = pixels.isEmpty() ? QImage() : m_frozen.image.copy(pixels);
    closeOverlays();
    releaseFrozen();
    if (purpose == QLatin1String("record")) {
        QTimer::singleShot(m_layered ? 60 : 200, this, [this, global]() {
            startRecording(true, global.toAlignedRect());
        });
    } else if (!image.isNull() && purpose == QLatin1String("text")) {
        recognize(image);
    } else if (!image.isNull()) {
        finishShot(image);
    }
    updateIdle();
}

QColor App::colorAt(int screenIndex, qreal x, qreal y) const
{
    const QList<QScreen *> screens = QGuiApplication::screens();
    if (screenIndex < 0 || screenIndex >= screens.size() || m_frozen.image.isNull()) {
        return {};
    }
    const QRect pixel = pixelRect(QRectF(QPointF(x, y) + screens.at(screenIndex)->geometry().topLeft(), QSizeF(0.01, 0.01)));
    if (!m_frozen.image.rect().contains(pixel.topLeft())) {
        return {};
    }
    return m_frozen.image.pixelColor(pixel.topLeft());
}

void App::overlayPoint(int screenIndex, qreal x, qreal y)
{
    const QColor color = colorAt(screenIndex, x, y);
    closeOverlays();
    releaseFrozen();
    if (color.isValid()) {
        showColor(color);
    }
    updateIdle();
}

QString App::folder(bool video) const
{
    QString path;
    if (m_saveTo == QLatin1String("desktop")) {
        path = QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
    } else if (video) {
        path = QStandardPaths::writableLocation(QStandardPaths::MoviesLocation);
    } else {
        path = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation) + QStringLiteral("/Screenshots");
    }
    QDir().mkpath(path);
    return path;
}

QString App::stamp(const QString &kind) const
{
    const QDateTime now = QDateTime::currentDateTime();
    return QStringLiteral("%1 %2 at %3").arg(kind, now.toString(QStringLiteral("yyyy-MM-dd")), now.toString(QStringLiteral("HH.mm.ss")));
}

QString App::uniquePath(const QString &directory, const QString &stem, const QString &extension) const
{
    QString path = QStringLiteral("%1/%2.%3").arg(directory, stem, extension);
    for (int i = 2; QFileInfo::exists(path); ++i) {
        path = QStringLiteral("%1/%2 (%3).%4").arg(directory, stem).arg(i).arg(extension);
    }
    return path;
}

void App::finishShot(const QImage &image)
{
    if (image.isNull()) {
        return;
    }
    m_last = image;
    m_lastVideo = false;
    m_lastTemporary = m_saveTo == QLatin1String("clipboard");
    const QString path = m_lastTemporary ? uniquePath(cacheDir(), stamp(QStringLiteral("Screenshot")), QStringLiteral("png")) : uniquePath(folder(false), stamp(QStringLiteral("Screenshot")), QStringLiteral("png"));
    m_lastPath = path;
    QFile placeholder(path);
    placeholder.open(QIODevice::WriteOnly);
    placeholder.close();
    m_busy = true;
    QPointer<App> self(this);
    QThreadPool::globalInstance()->start([self, image, path]() {
        const QByteArray png = encodePng(image);
        QSaveFile file(path);
        if (file.open(QIODevice::WriteOnly)) {
            file.write(png);
            file.commit();
        }
        QMetaObject::invokeMethod(qApp, [self, png, image]() {
            if (!self) {
                return;
            }
            self->m_busy = false;
            self->copyImage(png, image);
            self->updateIdle();
        }, Qt::QueuedConnection);
    });
    showThumb();
}

void App::copyImage(const QByteArray &png, const QImage &image)
{
    if (Grabber::hasTool(QStringLiteral("wl-copy")) && QGuiApplication::platformName().startsWith(QLatin1String("wayland"))) {
        auto *process = new QProcess(this);
        process->setStandardOutputFile(QProcess::nullDevice());
        process->setStandardErrorFile(QProcess::nullDevice());
        connect(process, &QProcess::finished, process, &QObject::deleteLater);
        process->start(QStringLiteral("wl-copy"), {QStringLiteral("-t"), QStringLiteral("image/png")});
        process->write(png);
        process->closeWriteChannel();
    } else {
        QGuiApplication::clipboard()->setImage(image);
    }
}

void App::copyText(const QString &text)
{
    if (Grabber::hasTool(QStringLiteral("wl-copy")) && QGuiApplication::platformName().startsWith(QLatin1String("wayland"))) {
        auto *process = new QProcess(this);
        process->setStandardOutputFile(QProcess::nullDevice());
        process->setStandardErrorFile(QProcess::nullDevice());
        connect(process, &QProcess::finished, process, &QObject::deleteLater);
        process->start(QStringLiteral("wl-copy"), {QStringLiteral("-t"), QStringLiteral("text/plain;charset=utf-8")});
        process->write(text.toUtf8());
        process->closeWriteChannel();
    } else {
        QGuiApplication::clipboard()->setText(text);
    }
}

void App::copyString(const QString &text)
{
    copyText(text);
    Q_EMIT flashCopied(text);
}

void App::showThumb()
{
    ++m_serial;
    Q_EMIT thumbChanged();
    dismiss(m_toast);
    if (!m_thumb) {
        m_thumb = makeView(QStringLiteral("Thumb"), {{QStringLiteral("edge"), m_layered ? 0 : 20}});
        m_thumb->setTitle(QStringLiteral("Capture Thumbnail"));
        Surface surface;
        surface.scope = QStringLiteral("kwick-capture-thumbnail");
        surface.anchors = LayerShellQt::Window::AnchorBottom | LayerShellQt::Window::AnchorRight;
        surface.margins = QMargins(0, 0, 4, 4);
        surface.size = QSize(300, 240);
        surface.overlay = true;
        present(m_thumb, surface);
    }
    m_thumbTimer.start(5000);
}

void App::thumbHold(bool hold)
{
    if (hold) {
        m_thumbTimer.stop();
    } else if (m_thumb) {
        m_thumbTimer.start(2500);
    }
}

void App::thumbDismiss()
{
    m_thumbTimer.stop();
    dismiss(m_thumb);
    updateIdle();
}

void App::thumbShare()
{
    m_thumbTimer.stop();
    dismiss(m_thumb);
    if (!m_lastPath.isEmpty()) {
        QProcess::startDetached(QStringLiteral("kwick-nearby"), {QStringLiteral("--share"), m_lastPath});
    }
    updateIdle();
}

void App::thumbOpen()
{
    m_thumbTimer.stop();
    dismiss(m_thumb);
    if (m_lastVideo) {
        openFile(m_lastPath);
    } else {
        openMarkup(m_lastPath, m_last);
    }
    updateIdle();
}

void App::openFile(const QString &path)
{
    if (Grabber::hasTool(QStringLiteral("xdg-open"))) {
        QProcess::startDetached(QStringLiteral("xdg-open"), {path});
    } else if (Grabber::hasTool(QStringLiteral("kde-open"))) {
        QProcess::startDetached(QStringLiteral("kde-open"), {path});
    } else if (Grabber::hasTool(QStringLiteral("gio"))) {
        QProcess::startDetached(QStringLiteral("gio"), {QStringLiteral("open"), path});
    }
}

void App::showToast(const QString &title, const QString &body, const QString &icon, const QString &action, qreal progress, int timeout)
{
    m_toastTitle = title;
    m_toastBody = body;
    m_toastIcon = icon;
    m_toastAction = action;
    m_toastProgress = progress;
    Q_EMIT toastChanged();
    if (!m_toast) {
        m_toast = makeView(QStringLiteral("Toast"), {{QStringLiteral("edge"), m_layered ? 0 : 20}});
        m_toast->setTitle(QStringLiteral("Capture"));
        Surface surface;
        surface.scope = QStringLiteral("kwick-capture-toast");
        surface.anchors = LayerShellQt::Window::AnchorBottom | LayerShellQt::Window::AnchorRight;
        surface.margins = QMargins(0, 0, 4, 4);
        surface.size = QSize(420, 200);
        surface.keyboard = !action.isEmpty();
        present(m_toast, surface);
    }
    if (timeout > 0) {
        m_toastTimer.start(timeout);
    } else {
        m_toastTimer.stop();
    }
}

void App::toastHold(bool hold)
{
    if (hold) {
        if (m_toastTimer.isActive()) {
            m_toastTimer.stop();
        }
    } else if (m_toast && m_toastAction.isEmpty() && m_toastProgress < 0) {
        m_toastTimer.start(2000);
    }
}

void App::toastAccept()
{
    std::function<void()> callback = std::move(m_toastCallback);
    m_toastCallback = nullptr;
    if (callback) {
        callback();
    } else {
        toastDismiss();
    }
}

void App::toastDismiss()
{
    if (m_installer) {
        return;
    }
    m_toastCallback = nullptr;
    m_toastTimer.stop();
    dismiss(m_toast);
    updateIdle();
}

void App::showFailure(const Failure &failure)
{
    if (failure.cancelled || failure.message.isEmpty()) {
        return;
    }
    QString body = failure.message;
    if (!failure.package.isEmpty()) {
        body += QStringLiteral("\nInstall it with: sudo apt install %1").arg(failure.package);
    }
    showToast(QStringLiteral("Capture"), body, QStringLiteral("close"), QString(), -1, 9000);
}

void App::recognize(const QImage &image)
{
    if (!Grabber::hasTool(QStringLiteral("tesseract"))) {
        m_pendingOcr = image;
        m_toastCallback = [this]() {
            installOcr();
        };
        showToast(QStringLiteral("Copy Text needs Tesseract"), QStringLiteral("Install the on-device text recognizer? It is about 10 MB and runs offline."), QStringLiteral("text"), QStringLiteral("Install"), -1, 0);
        return;
    }
    QImage prepared = image.convertToFormat(QImage::Format_Grayscale8);
    qint64 sum = 0;
    for (int y = 0; y < prepared.height(); y += 2) {
        const uchar *line = prepared.constScanLine(y);
        for (int x = 0; x < prepared.width(); x += 2) {
            sum += line[x];
        }
    }
    const qint64 samples = qMax<qint64>(1, qint64((prepared.height() + 1) / 2) * ((prepared.width() + 1) / 2));
    if (sum / samples < 110) {
        prepared.invertPixels();
    }
    if (prepared.width() < 2400 && prepared.height() < 2400) {
        prepared = prepared.scaled(prepared.size() * 2, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
    }
    QStringList languages{QStringLiteral("eng")};
    const QString extra = qEnvironmentVariable("KWICK_CAPTURE_OCR_LANGS");
    if (!extra.isEmpty()) {
        languages = extra.split(QLatin1Char('+'), Qt::SkipEmptyParts);
    }
    auto *process = new QProcess(this);
    m_busy = true;
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            process->deleteLater();
            m_busy = false;
            showToast(QStringLiteral("Copy Text"), QStringLiteral("Tesseract could not be started."), QStringLiteral("close"));
        }
    });
    connect(process, &QProcess::finished, this, [this, process](int code) {
        process->deleteLater();
        m_busy = false;
        const QString raw = QString::fromUtf8(process->readAllStandardOutput());
        QStringList lines;
        for (QString line : raw.split(QLatin1Char('\n'))) {
            line = line.trimmed();
            if (!line.isEmpty() || (!lines.isEmpty() && !lines.last().isEmpty())) {
                lines.append(line);
            }
        }
        while (!lines.isEmpty() && lines.last().isEmpty()) {
            lines.removeLast();
        }
        const QString text = lines.join(QLatin1Char('\n'));
        if (code != 0 && text.isEmpty()) {
            showToast(QStringLiteral("Copy Text"), QString::fromUtf8(process->readAllStandardError()).trimmed().section(QLatin1Char('\n'), 0, 0), QStringLiteral("close"));
        } else if (text.isEmpty()) {
            showToast(QStringLiteral("No text found"), QStringLiteral("Try selecting a larger area around the text."), QStringLiteral("text"));
        } else {
            copyText(text);
            int count = 0;
            for (const QString &line : std::as_const(lines)) {
                count += line.isEmpty() ? 0 : 1;
            }
            showToast(count == 1 ? QStringLiteral("Copied 1 line of text") : QStringLiteral("Copied %1 lines of text").arg(count), lines.first(), QStringLiteral("text"));
        }
        updateIdle();
    });
    process->start(QStringLiteral("tesseract"), {QStringLiteral("stdin"), QStringLiteral("stdout"), QStringLiteral("-l"), languages.join(QLatin1Char('+')), QStringLiteral("--psm"), QStringLiteral("3")});
    process->write(encodePng(prepared));
    process->closeWriteChannel();
}

void App::installOcr()
{
    if (m_installer) {
        return;
    }
    if (!Grabber::hasTool(QStringLiteral("pkexec"))) {
        showFailure({QStringLiteral("Administrator access is needed to install Tesseract."), QStringLiteral("tesseract-ocr tesseract-ocr-eng")});
        return;
    }
    auto *process = new QProcess(this);
    m_installer = process;
    showToast(QStringLiteral("Installing Tesseract"), QStringLiteral("Waiting for permission"), QStringLiteral("text"), QString(), 0.02, 0);
    connect(process, &QProcess::errorOccurred, this, [this, process](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            process->deleteLater();
            m_installer = nullptr;
            m_pendingOcr = QImage();
            showFailure({QStringLiteral("The installer could not be started."), QStringLiteral("tesseract-ocr tesseract-ocr-eng")});
        }
    });
    auto counts = std::make_shared<std::array<int, 4>>(std::array<int, 4>{0, 0, 0, 0});
    connect(process, &QProcess::readyReadStandardOutput, this, [this, process, counts]() {
        static const QRegularExpression totals(QStringLiteral("(Upgrading|Installing): (\\d+)"));
        while (process->canReadLine()) {
            const QString line = QString::fromUtf8(process->readLine()).trimmed();
            if (qEnvironmentVariableIsSet("KWICK_CAPTURE_TRACE")) {
                qInfo("kwick-capture: apt %lld %s", static_cast<long long>(QDateTime::currentMSecsSinceEpoch() % 100000), qPrintable(line.left(80)));
            }
            auto &[total, fetched, unpacked, configured] = *counts;
            if (line.startsWith(QLatin1String("Summary:")) || line.contains(QLatin1String("Upgrading:"))) {
                int sum = 0;
                for (auto match = totals.globalMatch(line); match.hasNext();) {
                    sum += match.next().captured(2).toInt();
                }
                if (sum > 0) {
                    total = sum;
                }
                continue;
            }
            if (line.startsWith(QLatin1String("Get:"))) {
                ++fetched;
                m_toastBody = QStringLiteral("Downloading");
            } else if (line.startsWith(QLatin1String("Unpacking "))) {
                ++unpacked;
                m_toastBody = QStringLiteral("Installing");
            } else if (line.startsWith(QLatin1String("Setting up "))) {
                ++configured;
                m_toastBody = QStringLiteral("Setting up");
            } else if (line.startsWith(QLatin1String("Hit:")) || line.startsWith(QLatin1String("Reading package lists"))) {
                m_toastBody = QStringLiteral("Checking for packages");
            } else {
                continue;
            }
            const qreal all = qMax(1, total > 0 ? total : qMax(fetched, qMax(unpacked, configured)) + 1);
            m_toastProgress = qBound(0.04, 0.5 * fetched / all + 0.25 * unpacked / all + 0.25 * configured / all, 0.98);
            Q_EMIT toastChanged();
        }
    });
    connect(process, &QProcess::finished, this, [this, process](int code) {
        process->deleteLater();
        m_installer = nullptr;
        if (qEnvironmentVariableIsSet("KWICK_CAPTURE_TRACE")) {
            qInfo("kwick-capture: installer exited %d: %s", code, process->readAllStandardError().right(400).constData());
        }
        if (code == 0 && Grabber::hasTool(QStringLiteral("tesseract"))) {
            const QImage pending = m_pendingOcr;
            m_pendingOcr = QImage();
            if (!pending.isNull()) {
                recognize(pending);
            } else {
                showToast(QStringLiteral("Tesseract is installed"), QStringLiteral("Copy Text is ready."), QStringLiteral("text"));
            }
        } else if (code == 126 || code == 127) {
            m_pendingOcr = QImage();
            showToast(QStringLiteral("Installation cancelled"), QStringLiteral("Copy Text needs tesseract-ocr."), QStringLiteral("close"));
        } else {
            m_pendingOcr = QImage();
            showToast(QStringLiteral("Installation failed"), QStringLiteral("Try: sudo apt install tesseract-ocr tesseract-ocr-eng"), QStringLiteral("close"), QString(), -1, 9000);
        }
        updateIdle();
    });
    const QString packages = QStringLiteral("tesseract-ocr tesseract-ocr-eng");
    const QString script = QStringLiteral("export DEBIAN_FRONTEND=noninteractive LC_ALL=C; B=; command -v stdbuf >/dev/null && B='stdbuf -oL'; $B apt-get install -y %1 || { $B apt-get update && $B apt-get install -y %1; }").arg(packages);
    process->start(QStringLiteral("pkexec"), {QStringLiteral("/bin/sh"), QStringLiteral("-c"), script});
}

void App::showColor(const QColor &color)
{
    m_picked = color;
    const QString hex = color.name(QColor::HexRgb).toUpper();
    m_recent.removeAll(hex);
    m_recent.prepend(hex);
    while (m_recent.size() > 8) {
        m_recent.removeLast();
    }
    KConfigGroup(m_config, QStringLiteral("Colors")).writeEntry("Recent", m_recent);
    m_config->sync();
    Q_EMIT pickedChanged();
    copyText(hex);
    if (!m_color) {
        m_color = makeView(QStringLiteral("ColorPanel"), {});
        m_color->setTitle(QStringLiteral("Color"));
        m_color->setColor(m_dark ? QColor(0x1e, 0x1e, 0x1e) : QColor(0xf5, 0xf5, 0xf5));
        m_color->resize(320, 384);
        m_color->setMinimumSize(QSize(300, 360));
        connect(m_color, &QWindow::visibleChanged, this, [this](bool visible) {
            if (!visible) {
                m_color->deleteLater();
                m_color = nullptr;
                updateIdle();
            }
        });
        m_color->show();
    }
    m_color->raise();
    m_color->requestActivate();
}

void App::choose(const QString &hex)
{
    const QColor color = QColor::fromString(hex);
    if (!color.isValid()) {
        return;
    }
    m_picked = color;
    Q_EMIT pickedChanged();
    copyText(color.name(QColor::HexRgb).toUpper());
}

void App::showPill()
{
    if (m_pill) {
        return;
    }
    m_pill = makeView(QStringLiteral("Pill"), {{QStringLiteral("edge"), m_layered ? 0 : 10}});
    m_pill->setTitle(QStringLiteral("Capture"));
    Surface surface;
    surface.scope = QStringLiteral("kwick-capture-status");
    surface.anchors = LayerShellQt::Window::AnchorTop;
    surface.margins = QMargins(0, 6, 0, 0);
    surface.size = QSize(380, 84);
    present(m_pill, surface);
}

void App::startRecording(bool region, const QRect &area)
{
    if (recording()) {
        return;
    }
    Recorder::Request request;
    request.region = region;
    request.area = area;
    QScreen *screen = QGuiApplication::screenAt(area.center());
    if (!screen) {
        screen = QGuiApplication::primaryScreen();
    }
    request.screen = screen ? screen->geometry() : area;
    request.scale = screen ? screen->devicePixelRatio() : 1;
    request.microphone = m_microphone;
    request.pointer = true;
    request.folder = folder(true);
    request.stem = stamp(QStringLiteral("Screen Recording"));
    m_recorder->start(request);
}

void App::stopRecording()
{
    m_recorder->stop();
}

void App::openMarkup(const QString &path, const QImage &image)
{
    QImage source = image.isNull() ? QImage(path) : image;
    if (source.isNull()) {
        showToast(QStringLiteral("Markup"), QStringLiteral("The image could not be opened."), QStringLiteral("close"));
        return;
    }
    const bool temporary = path.startsWith(cacheDir());
    const qint64 begin = QDateTime::currentMSecsSinceEpoch();
    const bool trace = qEnvironmentVariableIsSet("KWICK_CAPTURE_TRACE");
    QPointer<QQuickView> view = makeView(QStringLiteral("Markup"), {{QStringLiteral("path"), path}, {QStringLiteral("temporary"), temporary}});
    if (trace) {
        qInfo("kwick-capture: markup loaded in %lld ms", static_cast<long long>(QDateTime::currentMSecsSinceEpoch() - begin));
    }
    view->setTitle(QFileInfo(path).completeBaseName());
    view->setColor(m_dark ? QColor(0x1e, 0x1e, 0x1e) : QColor(0xf5, 0xf5, 0xf5));
    if (auto *canvas = view->rootObject() ? view->rootObject()->findChild<MarkupCanvas *>(QStringLiteral("canvas")) : nullptr) {
        canvas->setImage(source);
    }
    QScreen *screen = QGuiApplication::primaryScreen();
    const QSize room = screen ? screen->availableGeometry().size() * 0.86 : QSize(1200, 800);
    QSize size = source.size() / (screen ? screen->devicePixelRatio() : 1.0);
    size = size.grownBy(QMargins(24, 76, 24, 24));
    size = size.boundedTo(room).expandedTo(QSize(860, 520));
    view->resize(size);
    view->setMinimumSize(QSize(760, 420));
    m_markups.append(view);
    if (trace) {
        auto *once = new QObject(view);
        connect(view, &QQuickWindow::frameSwapped, once, [once, begin]() {
            qInfo("kwick-capture: markup frame after %lld ms", static_cast<long long>(QDateTime::currentMSecsSinceEpoch() - begin));
            once->deleteLater();
        });
    }
    connect(view, &QWindow::visibleChanged, this, [this, view](bool visible) {
        if (!visible && view) {
            view->deleteLater();
            m_markups.removeAll(view);
            updateIdle();
        }
    });
    view->show();
    if (trace) {
        qInfo("kwick-capture: markup shown in %lld ms", static_cast<long long>(QDateTime::currentMSecsSinceEpoch() - begin));
    }
    view->requestActivate();
}

void App::markupClose(QWindow *window)
{
    if (window) {
        window->close();
    }
}

void App::markupCopy(QQuickItem *item)
{
    auto *canvas = qobject_cast<MarkupCanvas *>(item);
    if (!canvas) {
        return;
    }
    const QImage image = canvas->render();
    copyImage(encodePng(image), image);
    Q_EMIT flashCopied(QStringLiteral("image"));
}

void App::markupSave(QQuickItem *item, const QString &path)
{
    auto *canvas = qobject_cast<MarkupCanvas *>(item);
    if (!canvas) {
        return;
    }
    if (path.isEmpty() || path.startsWith(cacheDir())) {
        markupSaveAs(item, path);
        return;
    }
    if (!canvas->saveTo(path)) {
        showToast(QStringLiteral("Markup"), QStringLiteral("The image could not be saved."), QStringLiteral("close"));
    }
}

void App::saveDialog(const QString &suggested, std::function<void(const QString &)> done)
{
    QString directory = folder(false);
    QByteArray folderBytes = directory.toUtf8();
    folderBytes.append('\0');
    const QVariantMap options{
        {QStringLiteral("current_name"), suggested},
        {QStringLiteral("current_folder"), folderBytes},
        {QStringLiteral("modal"), true},
    };
    Portal::call(QStringLiteral("org.freedesktop.portal.FileChooser"), QStringLiteral("SaveFile"), {QString(), QStringLiteral("Save Image")}, options, [this, done, directory, suggested](uint code, const QVariantMap &results) {
        if (code == 0) {
            const QStringList uris = results.value(QStringLiteral("uris")).toStringList();
            if (!uris.isEmpty()) {
                done(QUrl(uris.first()).toLocalFile());
            }
        } else if (results.contains(QStringLiteral("error"))) {
            done(uniquePath(directory, QFileInfo(suggested).completeBaseName(), QStringLiteral("png")));
        }
    }, this);
}

void App::markupSaveAs(QQuickItem *item, const QString &path)
{
    QPointer<MarkupCanvas> canvas = qobject_cast<MarkupCanvas *>(item);
    if (!canvas) {
        return;
    }
    const QString name = path.isEmpty() ? stamp(QStringLiteral("Screenshot")) + QStringLiteral(".png") : QFileInfo(path).fileName();
    saveDialog(name, [this, canvas](const QString &target) {
        if (!canvas || target.isEmpty()) {
            return;
        }
        if (!canvas->saveTo(target)) {
            showToast(QStringLiteral("Markup"), QStringLiteral("The image could not be saved."), QStringLiteral("close"));
            return;
        }
        if (auto *window = canvas->window()) {
            window->setTitle(QFileInfo(target).completeBaseName());
            if (auto *view = qobject_cast<QQuickView *>(window); view && view->rootObject()) {
                view->rootObject()->setProperty("path", target);
                view->rootObject()->setProperty("temporary", false);
            }
        }
    });
}

void App::markupShare(QQuickItem *item, const QString &path)
{
    auto *canvas = qobject_cast<MarkupCanvas *>(item);
    if (canvas && canvas->modified() && !path.isEmpty() && !path.startsWith(cacheDir())) {
        canvas->saveTo(path);
    } else if (canvas && path.startsWith(cacheDir())) {
        canvas->saveTo(path);
    }
    QDBusMessage message = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.FileManager1"), QStringLiteral("/org/freedesktop/FileManager1"), QStringLiteral("org.freedesktop.FileManager1"), QStringLiteral("ShowItems"));
    message << QStringList{QUrl::fromLocalFile(path).toString()} << QString();
    const QDBusMessage reply = QDBusConnection::sessionBus().call(message, QDBus::Block, 3000);
    if (reply.type() != QDBusMessage::ReplyMessage) {
        openFile(QFileInfo(path).absolutePath());
    }
}
