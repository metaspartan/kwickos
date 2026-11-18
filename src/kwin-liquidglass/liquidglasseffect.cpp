#include "liquidglasseffect.h"

#include "core/output.h"
#include "core/pixelgrid.h"
#include "core/rendertarget.h"
#include "core/renderviewport.h"
#include "effect/effecthandler.h"
#include "opengl/glframebuffer.h"
#include "opengl/glshader.h"
#include "opengl/glshadermanager.h"
#include "opengl/gltexture.h"
#include "opengl/glvertexbuffer.h"
#include "opengl/openglcontext.h"
#include "scene/windowitem.h"
#include "wayland/blur.h"
#include "wayland/surface.h"

#include <KConfigGroup>
#include <KSharedConfig>

#include <QDynamicPropertyChangeEvent>
#include <QFile>
#include <QMatrix4x4>
#include <QVector2D>
#include <QVector3D>
#include <QVector4D>
#include <QWindow>
#include <QtMath>

#include <algorithm>
#include <array>
#include <cmath>

using namespace std::chrono_literals;

namespace KWin
{

static QByteArray readShader(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return QByteArray();
    }
    QByteArray source = file.readAll();
    source.replace('\r', QByteArray());
    return source;
}

LiquidGlassEffect::LiquidGlassEffect()
{
    reconfigure(ReconfigureAll);

    connect(effects, &EffectsHandler::windowAdded, this, &LiquidGlassEffect::slotWindowAdded);
    connect(effects, &EffectsHandler::windowDeleted, this, &LiquidGlassEffect::slotWindowDeleted);
    connect(effects, &EffectsHandler::screenRemoved, this, &LiquidGlassEffect::slotScreenRemoved);
    connect(effects, &EffectsHandler::mouseChanged, this, [this](const QPointF &pos) {
        slotMouseChanged(pos);
    });
    connect(effects, &EffectsHandler::windowActivated, this, [this](EffectWindow *w) {
        if (m_lastActive && m_windows.count(m_lastActive)) {
            effects->addRepaint(m_lastActive->expandedGeometry().toAlignedRect());
        }
        if (w) {
            effects->addRepaint(w->expandedGeometry().toAlignedRect());
        }
        m_lastActive = w;
    });

    const auto stackingOrder = effects->stackingOrder();
    for (EffectWindow *window : stackingOrder) {
        slotWindowAdded(window);
    }
}

LiquidGlassEffect::~LiquidGlassEffect()
{
    effects->makeOpenGLContextCurrent();
    if (m_timerQueries > 0) {
        glDeleteQueries(int(m_queries.size()), m_queries.data());
    }
    m_windows.clear();
    m_downShader.reset();
    m_upShader.reset();
    m_glassShader.reset();
    m_clipShader.reset();
}

bool LiquidGlassEffect::supported()
{
    const auto context = effects->openglContext();
    if (!context || context->isSoftwareRenderer()) {
        return false;
    }
    return effects->isOpenGLCompositing() && (context->supportsBlits() || effects->waylandDisplay());
}

bool LiquidGlassEffect::enabledByDefault()
{
    return false;
}

void LiquidGlassEffect::reconfigure(ReconfigureFlags flags)
{
    Q_UNUSED(flags)
    KSharedConfigPtr config = effects->config();
    config->reparseConfiguration();
    const KConfigGroup group = config->group(QStringLiteral("Effect-kwick_liquidglass"));
    m_refraction = std::clamp(group.readEntry("Refraction", 60), 0, 100) / 100.0;
    m_blur = std::clamp(group.readEntry("Blur", 50), 0, 100) / 100.0;
    m_dispersion = std::clamp(group.readEntry("Dispersion", 35), 0, 100) / 100.0;
    m_specular = std::clamp(group.readEntry("Specular", 70), 0, 100) / 100.0;
    m_tint = std::clamp(group.readEntry("Tint", 100), 0, 200) / 100.0;
    m_style = std::clamp(group.readEntry("Style", 0), 0, 2);
    m_titleBars = group.readEntry("TitleBars", false);
    m_menuBar = group.readEntry("MenuBar", false);
    m_interactive = group.readEntry("Interactive", true);
    m_roundWindows = group.readEntry("Windows", true);
    const int profile = group.readEntry("Profile", 0);
    m_profile = profile > 0;
    m_bypass = profile == 2;
    const KConfigGroup corners = config->group(QStringLiteral("Round-Corners"));
    m_radius = std::clamp(corners.readEntry("Size", 12), 0, 48);
    if (group.hasKey("Radius")) {
        m_radius = std::clamp(group.readEntry("Radius", m_radius), 0, 48);
    }

    for (EffectWindow *w : effects->stackingOrder()) {
        updateWindow(w);
    }
    for (auto &[w, glass] : m_windows) {
        for (auto &[output, render] : glass.render) {
            render.dirty = true;
        }
    }
    effects->addRepaintFull();
}

int LiquidGlassEffect::requestedEffectChainPosition() const
{
    return 19;
}

bool LiquidGlassEffect::blocksDirectScanout() const
{
    return false;
}

bool LiquidGlassEffect::isActive() const
{
    return !m_windows.empty() && !effects->isScreenLocked();
}

LiquidGlassEffect::Kind LiquidGlassEffect::classify(EffectWindow *w) const
{
    if (w->isDesktop() || w->isLockScreen() || w->isOutline() || w->isInputMethod() || w->isDNDIcon()) {
        return Kind::None;
    }
    if (w->isDock()) {
        return Kind::Dock;
    }
    if (w->isOnScreenDisplay()) {
        return Kind::Osd;
    }
    if (w->isTooltip()) {
        return Kind::Tooltip;
    }
    if (w->isNotification() || w->isCriticalNotification()) {
        return Kind::Notification;
    }
    if (w->isAppletPopup()) {
        return Kind::Popup;
    }
    if (w->isPopupMenu() || w->isDropdownMenu() || w->isMenu() || w->isComboBox() || w->isPopupWindow()) {
        return Kind::Menu;
    }
    if (m_titleBars && w->hasDecoration() && w->decorationHasAlpha() && !w->isFullScreen()) {
        return Kind::Frame;
    }
    const bool csd = !w->hasDecoration() && w->expandedGeometry().width() > w->frameGeometry().width() + 4.0;
    if (m_roundWindows && (w->hasDecoration() || csd) && (w->isNormalWindow() || w->isDialog()) && !w->isFullScreen()) {
        return Kind::Window;
    }
    return Kind::None;
}

void LiquidGlassEffect::slotWindowAdded(EffectWindow *w)
{
    if (SurfaceInterface *surface = w->surface()) {
        m_connections[w] = connect(surface, &SurfaceInterface::blurChanged, this, [this, w]() {
            updateWindow(w);
        });
    }
    if (QWindow *internal = w->internalWindow()) {
        internal->installEventFilter(this);
    }
    connect(w, &EffectWindow::windowDecorationChanged, this, [this, w]() {
        updateWindow(w);
    });
    connect(w, &EffectWindow::windowFrameGeometryChanged, this, [this, w]() {
        auto it = m_windows.find(w);
        if (it == m_windows.end() && m_roundWindows && !w->hasDecoration() && (w->isNormalWindow() || w->isDialog())) {
            updateWindow(w);
            it = m_windows.find(w);
        }
        if (it != m_windows.end()) {
            for (auto &[output, render] : it->second.render) {
                render.dirty = true;
            }
            effects->addRepaint(it->second.lastArea);
            if (it->second.kind == Kind::Frame) {
                updateWindow(w);
            }
        }
    });
    updateWindow(w);
}

void LiquidGlassEffect::slotWindowDeleted(EffectWindow *w)
{
    if (m_lastActive == w) {
        m_lastActive = nullptr;
    }
    if (auto it = m_windows.find(w); it != m_windows.end()) {
        effects->makeOpenGLContextCurrent();
        m_windows.erase(it);
    }
    if (auto it = m_connections.find(w); it != m_connections.end()) {
        disconnect(it->second);
        m_connections.erase(it);
    }
}

void LiquidGlassEffect::slotScreenRemoved(Output *output)
{
    for (auto &[w, glass] : m_windows) {
        if (auto it = glass.render.find(output); it != glass.render.end()) {
            effects->makeOpenGLContextCurrent();
            glass.render.erase(it);
        }
    }
}

bool LiquidGlassEffect::eventFilter(QObject *watched, QEvent *event)
{
    auto internal = qobject_cast<QWindow *>(watched);
    if (internal && event->type() == QEvent::DynamicPropertyChange) {
        auto pe = static_cast<QDynamicPropertyChangeEvent *>(event);
        if (pe->propertyName() == "kwin_blur") {
            if (EffectWindow *w = effects->findWindow(internal)) {
                updateWindow(w);
            }
        }
    }
    return false;
}

void LiquidGlassEffect::updateWindow(EffectWindow *w)
{
    if (w->isDeleted()) {
        return;
    }
    const Kind kind = classify(w);
    std::optional<QRegion> content;
    std::optional<QRegion> frame;
    if (kind != Kind::None && kind != Kind::Frame) {
        SurfaceInterface *surface = w->surface();
        if (surface && surface->blur()) {
            content = surface->blur()->region();
        }
        if (QWindow *internal = w->internalWindow()) {
            const QVariant property = internal->property("kwin_blur");
            if (property.isValid()) {
                content = property.value<QRegion>();
            }
        }
    }
    if (kind == Kind::Frame) {
        const QRectF frameRect = w->frameGeometry();
        const QRectF contents = w->contentsRect();
        if (contents.top() > 0.5) {
            frame = QRegion(QRect(0, 0, int(std::round(frameRect.width())), int(std::round(contents.top()))));
        }
    }

    if (content.has_value() || frame.has_value() || kind == Kind::Window) {
        Glass &glass = m_windows[w];
        const bool changed = glass.kind != kind || glass.content != content || glass.frame != frame;
        glass.kind = kind;
        glass.content = content;
        glass.frame = frame;
        if (changed) {
            glass.itemEffect = ItemEffect(w->windowItem());
            for (auto &[output, render] : glass.render) {
                render.dirty = true;
            }
        }
        effects->addRepaint(w->expandedGeometry().toAlignedRect());
    } else if (auto it = m_windows.find(w); it != m_windows.end()) {
        effects->makeOpenGLContextCurrent();
        effects->addRepaint(it->second.lastArea);
        m_windows.erase(it);
    }
}

QRegion LiquidGlassEffect::glassRegion(EffectWindow *w, const Glass &glass) const
{
    QRegion region;
    const QPoint origin = w->contentsRect().topLeft().toPoint();
    if (glass.content.has_value()) {
        if (glass.content->isEmpty()) {
            region = w->contentsRect().toRect();
        } else {
            region = glass.content->translated(origin) & w->contentsRect().toRect();
        }
    }
    if (glass.frame.has_value()) {
        region += glass.frame.value();
    }
    return region.translated(w->pos().toPoint());
}

QRectF LiquidGlassEffect::shapeRect(EffectWindow *w, const Glass &glass) const
{
    return QRectF(glassRegion(w, glass).boundingRect());
}

QRect LiquidGlassEffect::area(EffectWindow *w, const Glass &glass) const
{
    const QRect shape = shapeRect(w, glass).toAlignedRect();
    if (shape.isEmpty()) {
        return QRect();
    }
    const QRect expanded = w->expandedGeometry().toAlignedRect() | w->frameGeometry().toAlignedRect();
    QRect result = shape.adjusted(-10, -10, 10, 10) & expanded;
    const QRect screen = m_currentScreen ? m_currentScreen->geometry() : effects->virtualScreenGeometry();
    if (result.intersects(screen)) {
        result &= screen;
    }
    return result | shape;
}

double LiquidGlassEffect::radiusFor(EffectWindow *w, const Glass &glass, const QRectF &shape) const
{
    Q_UNUSED(w)
    const double cross = std::min(shape.width(), shape.height());
    const double s = std::clamp(m_radius / 10.0, 0.5, 1.3);
    double radius = 0.0;
    switch (glass.kind) {
    case Kind::Dock:
        radius = cross * 0.36 * std::clamp(s, 0.7, 1.2);
        break;
    case Kind::Bar:
        radius = 0.0;
        break;
    case Kind::Menu:
        radius = 10.5 * std::clamp(s, 0.8, 1.2);
        break;
    case Kind::Popup:
        radius = 16.0 * std::clamp(s, 0.8, 1.2);
        break;
    case Kind::Notification:
        radius = 20.0 * std::clamp(s, 0.8, 1.2);
        break;
    case Kind::Osd:
        radius = cross / 2.0;
        break;
    case Kind::Tooltip:
        radius = std::min(cross / 2.0, 11.0);
        break;
    case Kind::Frame:
    case Kind::Window:
    case Kind::None:
        radius = m_radius;
        break;
    }
    return std::clamp(radius, 0.0, cross / 2.0);
}
LiquidGlassEffect::Look LiquidGlassEffect::lookFor(Kind kind) const
{
    Look look;
    switch (kind) {
    case Kind::Dock:
        look = {0.8f, 0.9f, 14.0f, 3, 1.7f, 1.0f, 1.3f, 0.0f, 0.1f, 0.0f, 0.05f};
        break;
    case Kind::Bar:
        look = {0.5f, 0.8f, 8.0f, 3, 2.4f, 1.0f, 1.15f, 0.0f, 0.18f};
        break;
    case Kind::Menu:
        look = {0.5f, 1.0f, 7.0f, 4, 3.4f, 1.0f, 0.06f, 0.64f, 0.74f, 0.0f};
        break;
    case Kind::Popup:
        look = {0.55f, 1.0f, 9.0f, 4, 3.4f, 1.0f, 0.3f, 0.56f, 0.68f, 0.0f};
        break;
    case Kind::Notification:
        look = {0.55f, 0.9f, 10.0f, 4, 3.2f, 1.0f, 1.4f, 0.27f, 0.38f, 1.0f, 0.15f};
        break;
    case Kind::Tooltip:
        look = {0.5f, 0.95f, 6.0f, 3, 2.5f, 1.0f, 0.4f, 0.5f, 0.62f};
        break;
    case Kind::Osd:
        look = {0.7f, 0.85f, 10.0f, 3, 3.0f, 1.0f, 0.45f, 0.46f, 0.6f};
        break;
    case Kind::Frame:
        look = {0.5f, 0.7f, 10.0f, 3, 3.0f, 1.0f};
        break;
    case Kind::Window:
        look = {0.0f, 1.0f, 1.0f, 4, 3.2f, 0.0f, 1.0f, 0.0f, 0.0f};
        break;
    case Kind::None:
        break;
    }
    look.refract *= float(m_refraction / 0.6);
    look.frost = std::clamp(float(look.frost * m_blur / 0.5), 0.0f, 1.0f);
    look.tint *= float(m_tint);
    return look;
}

void LiquidGlassEffect::slotMouseChanged(const QPointF &pos)
{
    if (!m_interactive) {
        return;
    }
    for (auto &[w, glass] : m_windows) {
        const QRectF shape = shapeRect(w, glass);
        const bool inside = shape.adjusted(-24, -24, 24, 24).contains(pos);
        const double target = inside && !glass.lastArea.isEmpty() ? 1.0 : 0.0;
        if (inside || glass.hoverTarget != target) {
            glass.pointer = pos;
            glass.hoverTarget = target;
            effects->addRepaint(glass.lastArea);
        }
    }
}

void LiquidGlassEffect::prePaintScreen(ScreenPrePaintData &data, std::chrono::milliseconds presentTime)
{
    m_paintedArea = QRegion();
    m_currentGlass = QRegion();
    m_currentScreen = effects->waylandDisplay() ? data.screen : nullptr;

    const auto delta = m_lastPresent < 0ms ? 16ms : std::clamp(presentTime - m_lastPresent, 0ms, 100ms);
    m_lastPresent = presentTime;
    m_animating = false;
    for (auto &[w, glass] : m_windows) {
        if (glass.hover != glass.hoverTarget) {
            const double step = delta.count() / 180.0;
            if (glass.hover < glass.hoverTarget) {
                glass.hover = std::min(glass.hoverTarget, glass.hover + step);
            } else {
                glass.hover = std::max(glass.hoverTarget, glass.hover - step);
            }
            m_animating = true;
        }
    }

    if (m_profile) {
        if (m_profileLast >= 0ms) {
            const auto interval = presentTime - m_profileLast;
            if (interval > 0ms && interval <= 50ms) {
                m_profileActiveMs += interval.count();
                ++m_profileActive;
                m_profileMaxInterval = std::max(m_profileMaxInterval, interval);
            }
        }
        m_profileLast = presentTime;
        ++m_profileFrames;
    }

    effects->prePaintScreen(data, presentTime);
}

void LiquidGlassEffect::prePaintWindow(EffectWindow *w, WindowPrePaintData &data, std::chrono::milliseconds presentTime)
{
    effects->prePaintWindow(w, data, presentTime);

    if (auto win = m_windows.find(w); win != m_windows.end() && win->second.kind == Kind::Window && m_radius > 0 && !data.opaque.isEmpty()) {
        const QRect f = w->frameGeometry().toAlignedRect();
        const int r = m_radius + 1;
        QRegion corners;
        corners += QRect(f.left(), f.top(), r, r);
        corners += QRect(f.right() - r + 1, f.top(), r, r);
        corners += QRect(f.left(), f.bottom() - r + 1, r, r);
        corners += QRect(f.right() - r + 1, f.bottom() - r + 1, r, r);
        data.opaque -= corners;
    }

    const QRegion oldOpaque = data.opaque;
    if (data.opaque.intersects(m_currentGlass)) {
        QRegion shrunk;
        for (const QRect &rect : data.opaque) {
            shrunk += rect.adjusted(12, 12, -12, -12);
        }
        data.opaque = shrunk;
        m_currentGlass -= shrunk;
    }
    if ((data.paint - oldOpaque).intersects(m_currentGlass)) {
        data.paint += m_currentGlass;
    }

    auto it = m_windows.find(w);
    if (it != m_windows.end()) {
        Glass &glass = it->second;
        const QRect a = area(w, glass);
        if (!a.isEmpty()) {
            Render &render = glass.render[m_currentScreen];
            const bool moved = a != glass.lastArea;
            if (moved || !render.primed || render.dirty || m_paintedArea.intersects(a)) {
                render.dirty = true;
                data.paint += a;
                if (m_currentGlass.intersects(a)) {
                    data.paint += m_currentGlass;
                }
            }
            if (moved && !glass.lastArea.isEmpty()) {
                effects->addRepaint(glass.lastArea);
            }
            glass.lastArea = a;
            m_currentGlass += a;
        }
    }

    m_paintedArea -= data.opaque;
    m_paintedArea += data.paint;
}

bool LiquidGlassEffect::ensureShaders()
{
    if (m_downShader && m_upShader && m_glassShader && m_clipShader) {
        return true;
    }
    if (m_shaderFailed) {
        return false;
    }
    const QByteArray vertex = readShader(QStringLiteral(":/effects/kwick_liquidglass/shaders/pass.vert"));
    const QByteArray down = readShader(QStringLiteral(":/effects/kwick_liquidglass/shaders/down.frag"));
    const QByteArray up = readShader(QStringLiteral(":/effects/kwick_liquidglass/shaders/up.frag"));
    const QByteArray glass = readShader(QStringLiteral(":/effects/kwick_liquidglass/shaders/glass.frag"));
    const QByteArray clipVertex = readShader(QStringLiteral(":/effects/kwick_liquidglass/shaders/clip.vert"));
    const QByteArray clip = readShader(QStringLiteral(":/effects/kwick_liquidglass/shaders/clip.frag"));
    if (!vertex.isEmpty() && !down.isEmpty() && !up.isEmpty() && !glass.isEmpty() && !clipVertex.isEmpty() && !clip.isEmpty()) {
        m_clipShader = ShaderManager::instance()->generateCustomShader(ShaderTrait::MapTexture, clipVertex, clip);
        m_downShader = ShaderManager::instance()->generateCustomShader(ShaderTrait::MapTexture, vertex, down);
        m_upShader = ShaderManager::instance()->generateCustomShader(ShaderTrait::MapTexture, vertex, up);
        m_glassShader = ShaderManager::instance()->generateCustomShader(ShaderTrait::MapTexture, vertex, glass);
    }
    if (!m_downShader || !m_downShader->isValid() || !m_upShader || !m_upShader->isValid() || !m_glassShader || !m_glassShader->isValid() || !m_clipShader || !m_clipShader->isValid()) {
        m_downShader.reset();
        m_upShader.reset();
        m_glassShader.reset();
        m_clipShader.reset();
        m_shaderFailed = true;
        qWarning("kwick_liquidglass: shader compilation failed");
        return false;
    }
    return true;
}

bool LiquidGlassEffect::ensurePasses(Render &render, const QSize &size, GLenum format, int levels)
{
    if (int(render.passes.size()) == levels + 1 && render.passes[0].texture->size() == size && render.format == format) {
        return true;
    }
    render.passes.clear();
    render.primed = false;
    render.dirty = true;
    render.format = format;
    for (int i = 0; i <= levels; ++i) {
        const QSize levelSize(std::max(1, size.width() >> i), std::max(1, size.height() >> i));
        Pass pass;
        pass.texture = GLTexture::allocate(format, levelSize);
        if (!pass.texture) {
            render.passes.clear();
            return false;
        }
        pass.texture->setFilter(GL_LINEAR);
        pass.texture->setWrapMode(GL_CLAMP_TO_EDGE);
        pass.framebuffer = std::make_unique<GLFramebuffer>(pass.texture.get());
        if (!pass.framebuffer->valid()) {
            render.passes.clear();
            return false;
        }
        render.passes.push_back(std::move(pass));
    }
    return true;
}

bool LiquidGlassEffect::paintGlass(const RenderTarget &renderTarget, const RenderViewport &viewport, EffectWindow *w, Glass &glass, const QRegion &region, const WindowPaintData &data)
{
    const double scale = viewport.scale();
    const QPoint shift(int(std::round(data.xTranslation())), int(std::round(data.yTranslation())));
    const QRect a = area(w, glass).translated(shift);
    QRectF shape = shapeRect(w, glass).translated(shift);
    if (a.isEmpty() || shape.isEmpty()) {
        return false;
    }

    const QRect screen = m_currentScreen ? m_currentScreen->geometry() : effects->virtualScreenGeometry();
    Kind kind = glass.kind;
    const bool topEdge = std::abs(shape.top() - screen.top()) < 1.5;
    const bool bottomEdge = std::abs(shape.bottom() - screen.bottom() - 1) < 1.5;
    const bool leftEdge = std::abs(shape.left() - screen.left()) < 1.5;
    const bool rightEdge = std::abs(shape.right() - screen.right() - 1) < 1.5;
    if (kind == Kind::Dock && ((leftEdge && rightEdge) || (topEdge && bottomEdge))) {
        kind = Kind::Bar;
    }
    if (kind == Kind::Bar && topEdge && !m_menuBar) {
        return false;
    }
    Glass probe;
    probe.kind = kind;
    probe.content = glass.content;
    const double radius = radiusFor(w, probe, shape);
    glass.clipShape = shape;
    glass.clipRadius = radius;
    Look look = lookFor(kind);
    const double minSide = std::min(shape.width(), shape.height());
    look.bevel = float(std::min<double>(look.bevel, minSide * (kind == Kind::Bar ? 0.5 : 0.42)));

    QRectF sdf = shape;
    const double extend = radius + look.bevel + 8.0;
    if (kind == Kind::Bar || kind == Kind::Dock) {
        if (topEdge) {
            sdf.setTop(sdf.top() - extend);
        }
        if (bottomEdge) {
            sdf.setBottom(sdf.bottom() + extend);
        }
        if (leftEdge) {
            sdf.setLeft(sdf.left() - extend);
        }
        if (rightEdge) {
            sdf.setRight(sdf.right() + extend);
        }
    }
    if (kind == Kind::Frame) {
        sdf.setBottom(sdf.bottom() + extend);
    }

    const QRegion clip = (region == infiniteRegion()) ? QRegion(a) : (region & a);
    if (clip.isEmpty()) {
        return true;
    }

    const QRect device = snapToPixelGrid(scaledRect(QRectF(a), scale));
    if (device.isEmpty()) {
        return false;
    }

    Render &render = glass.render[m_currentScreen];
    const GLenum format = renderTarget.texture() ? renderTarget.texture()->internalFormat() : GL_RGBA8;
    int levels = look.levels;
    while (levels > 1 && std::min(device.width(), device.height()) >> levels < 2) {
        --levels;
    }
    if (render.device != device) {
        render.device = device;
        render.primed = false;
        render.dirty = true;
    }
    if (!ensurePasses(render, device.size(), format, levels)) {
        return false;
    }

    GLVertexBuffer *vbo = GLVertexBuffer::streamingBuffer();
    vbo->reset();
    vbo->setAttribLayout(std::span(GLVertexBuffer::GLVertex2DLayout), sizeof(GLVertex2D));

    const int shadowPad = kind == Kind::Bar || kind == Kind::Frame || kind == Kind::Window ? 1 : int(std::ceil(14 * scale));
    const QRect drawRect = snapToPixelGrid(scaledRect(shape, scale)).adjusted(-shadowPad, -shadowPad, shadowPad, shadowPad) & device;
    if (drawRect.isEmpty()) {
        return true;
    }
    const float W = device.width();
    const float H = device.height();
    std::array<GLVertex2D, 12> vertices;
    {
        const GLVertex2D tl{.position = QVector2D(0.0f, 0.0f), .texcoord = QVector2D(0.0f, 1.0f)};
        const GLVertex2D tr{.position = QVector2D(W, 0.0f), .texcoord = QVector2D(1.0f, 1.0f)};
        const GLVertex2D br{.position = QVector2D(W, H), .texcoord = QVector2D(1.0f, 0.0f)};
        const GLVertex2D bl{.position = QVector2D(0.0f, H), .texcoord = QVector2D(0.0f, 0.0f)};
        vertices[0] = tl;
        vertices[1] = br;
        vertices[2] = bl;
        vertices[3] = tl;
        vertices[4] = tr;
        vertices[5] = br;
    }
    {
        const float x0 = drawRect.left();
        const float y0 = drawRect.top();
        const float x1 = drawRect.left() + drawRect.width();
        const float y1 = drawRect.top() + drawRect.height();
        const float ox = device.left();
        const float oy = device.top();
        const GLVertex2D tl{.position = QVector2D(x0, y0), .texcoord = QVector2D(x0 - ox, y0 - oy)};
        const GLVertex2D tr{.position = QVector2D(x1, y0), .texcoord = QVector2D(x1 - ox, y0 - oy)};
        const GLVertex2D br{.position = QVector2D(x1, y1), .texcoord = QVector2D(x1 - ox, y1 - oy)};
        const GLVertex2D bl{.position = QVector2D(x0, y1), .texcoord = QVector2D(x0 - ox, y1 - oy)};
        vertices[6] = tl;
        vertices[7] = br;
        vertices[8] = bl;
        vertices[9] = tl;
        vertices[10] = tr;
        vertices[11] = br;
    }
    const auto map = vbo->map<GLVertex2D>(vertices.size());
    if (!map) {
        return false;
    }
    std::copy(vertices.begin(), vertices.end(), map->begin());
    vbo->unmap();
    vbo->bindArrays();

    if (render.dirty || !render.primed) {
        for (const QRect &rect : clip) {
            const QRect dest = snapToPixelGrid(scaledRect(QRectF(rect), scale)).translated(-device.topLeft());
            render.passes[0].framebuffer->blitFromRenderTarget(renderTarget, viewport, rect, dest);
        }

        glDisable(GL_BLEND);
        QMatrix4x4 projection;
        projection.ortho(QRectF(0.0, 0.0, W, H));
        {
            ShaderBinder binder(m_downShader.get());
            GLShader *shader = binder.shader();
            shader->setUniform("uMvp", projection);
            shader->setUniform("uOffset", look.offset);
            shader->setUniform("uTex", 0);
            for (size_t i = 1; i < render.passes.size(); ++i) {
                GLTexture *read = render.passes[i - 1].texture.get();
                shader->setUniform("uHalf", QVector2D(0.5f / read->width(), 0.5f / read->height()));
                read->bind();
                GLFramebuffer::pushFramebuffer(render.passes[i].framebuffer.get());
                vbo->draw(GL_TRIANGLES, 0, 6);
                GLFramebuffer::popFramebuffer();
            }
        }
        {
            ShaderBinder binder(m_upShader.get());
            GLShader *shader = binder.shader();
            shader->setUniform("uMvp", projection);
            shader->setUniform("uOffset", look.offset);
            shader->setUniform("uTex", 0);
            for (size_t i = render.passes.size() - 1; i > 1; --i) {
                GLTexture *read = render.passes[i].texture.get();
                shader->setUniform("uHalf", QVector2D(0.5f / read->width(), 0.5f / read->height()));
                read->bind();
                GLFramebuffer::pushFramebuffer(render.passes[i - 1].framebuffer.get());
                vbo->draw(GL_TRIANGLES, 0, 6);
                GLFramebuffer::popFramebuffer();
            }
        }
        render.dirty = false;
        if ((QRegion(a) - clip).isEmpty()) {
            render.primed = true;
        } else if (!render.primed) {
            effects->addRepaint(a);
        }
    }

    const QPointF origin = QPointF(device.topLeft());
    const QRectF sdfDevice = scaledRect(sdf, scale);
    const QRectF shapeDevice = scaledRect(shape, scale);
    const QPointF sdfCenter = sdfDevice.center() - origin;
    const QPointF shapeCenter = shapeDevice.center() - origin;
    const QPointF pointer = glass.pointer * scale - origin;

    QVector2D light(-0.62f, -0.78f);
    if (m_interactive && glass.hover > 0.0) {
        QVector2D toPointer(float(pointer.x() - shapeCenter.x()), float(pointer.y() - shapeCenter.y()));
        if (toPointer.length() > 1.0f) {
            toPointer.normalize();
            const float k = float(0.6 * glass.hover);
            light = (light * (1.0f - k) + toPointer * k);
            if (light.length() < 0.05f) {
                light = toPointer;
            }
            light.normalize();
        }
    }

    const float opacity = float(w->opacity() * data.opacity());
    const int last = int(render.passes.size()) - 1;

    ShaderBinder binder(m_glassShader.get());
    GLShader *shader = binder.shader();
    shader->setUniform("uMvp", viewport.projectionMatrix());
    shader->setUniform("uSharp", 0);
    shader->setUniform("uBlur", 1);
    shader->setUniform("uMean", 2);
    shader->setUniform("uSize", QVector2D(W, H));
    shader->setUniform("uRect", QVector4D(float(sdfCenter.x()), float(sdfCenter.y()), float(sdfDevice.width() / 2.0), float(sdfDevice.height() / 2.0)));
    shader->setUniform("uShape", QVector4D(float(shapeCenter.x()), float(shapeCenter.y()), float(shapeDevice.width() / 2.0), float(shapeDevice.height() / 2.0)));
    shader->setUniform("uRadius", float(radius * scale));
    shader->setUniform("uBevel", float(look.bevel * scale));
    shader->setUniform("uRefract", look.refract);
    shader->setUniform("uFrost", look.frost);
    shader->setUniform("uDisperse", float(kind == Kind::Window ? 0.0 : m_dispersion));
    shader->setUniform("uSpec", float(kind == Kind::Window ? 0.0 : (kind == Kind::Bar ? m_specular * 0.35 : m_specular)));
    shader->setUniform("uSat", look.sat);
    shader->setUniform("uDark", QVector2D(look.darkMin, look.darkMax));
    shader->setUniform("uMul", look.mul);
    shader->setUniform("uTint", look.tint);
    shader->setUniform("uStyle", float(m_style));
    shader->setUniform("uOpacity", opacity);
    shader->setUniform("uScale", float(scale));
    shader->setUniform("uLight", light);
    const QRectF room(QPointF(0.0, 0.0), QSizeF(device.size()));
    const QRectF shapeLocal = shapeDevice.translated(-origin);
    const double margin = std::min({shapeLocal.left() - room.left(), shapeLocal.top() - room.top(), room.right() - shapeLocal.right(), room.bottom() - shapeLocal.bottom()});
    const float shadowRoom = float(std::clamp(margin / (10.0 * scale), 0.0, 1.0));
    shader->setUniform("uShadow", kind == Kind::Bar || kind == Kind::Frame || kind == Kind::Window ? 0.0f : 0.24f * shadowRoom * shadowRoom);
    shader->setUniform("uVeil", look.veil);
    shader->setUniform("uAdapt", kind == Kind::Notification ? 1.0f : 0.0f);
    shader->setUniform("uPointer",QVector3D(float(pointer.x()), float(pointer.y()), float(m_interactive && kind != Kind::Window ? glass.hover : 0.0)));

    glActiveTexture(GL_TEXTURE2);
    render.passes[last].texture->bind();
    glActiveTexture(GL_TEXTURE1);
    render.passes[std::min(1, last)].texture->bind();
    glActiveTexture(GL_TEXTURE0);
    render.passes[0].texture->bind();

    const QRegion clipDevice = viewport.mapToRenderTarget(clip);
    glEnable(GL_SCISSOR_TEST);
    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    vbo->draw(clipDevice, GL_TRIANGLES, 6, 6, true);
    glDisable(GL_BLEND);
    glDisable(GL_SCISSOR_TEST);

    glActiveTexture(GL_TEXTURE2);
    glBindTexture(GL_TEXTURE_2D, 0);
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, 0);
    glActiveTexture(GL_TEXTURE0);
    render.passes[0].texture->unbind();
    vbo->unbindArrays();
    return true;
}

void LiquidGlassEffect::drawWindow(const RenderTarget &renderTarget, const RenderViewport &viewport, EffectWindow *w, int mask, const QRegion &region, WindowPaintData &data)
{
    auto it = m_windows.find(w);
    if (it == m_windows.end() || m_bypass || !ensureShaders()) {
        effects->drawWindow(renderTarget, viewport, w, mask, region, data);
        return;
    }
    const bool forced = w->data(WindowForceBlurRole).toBool();
    const bool scaled = !qFuzzyCompare(data.xScale(), 1.0) || !qFuzzyCompare(data.yScale(), 1.0);
    const bool translated = data.xTranslation() || data.yTranslation();
    if (it->second.kind == Kind::Window) {
        const bool moved = scaled || translated || data.rotationAngle() != 0.0;
        const bool dragging = w->isUserMove() || w->isUserResize();
        const bool deformed = (mask & PAINT_WINDOW_TRANSFORMED) && !moved && (!dragging || effects->isEffectLoaded(QStringLiteral("wobblywindows")));
        if (!deformed && !effects->activeFullScreenEffect() && roundable(w)) {
            const bool painted = moved ? false : paintGlass(renderTarget, viewport, w, it->second, region, data);
            Q_UNUSED(painted)
            const bool rigid = !scaled && data.rotationAngle() == 0.0;
            it->second.clipShape = rigid ? w->frameGeometry().translated(data.xTranslation(), data.yTranslation()) : w->frameGeometry();
            it->second.clipRadius = m_radius;
            if (drawClipped(renderTarget, viewport, w, it->second, mask, region, data)) {
                return;
            }
        }
        effects->drawWindow(renderTarget, viewport, w, mask, region, data);
        return;
    }
    if ((effects->activeFullScreenEffect() && !forced) || scaled || ((translated || (mask & PAINT_WINDOW_TRANSFORMED)) && !forced) || w->isDesktop()) {
        effects->drawWindow(renderTarget, viewport, w, mask, region, data);
        return;
    }

    bool painted = false;
    if (m_profile) {
        if (m_timerQueries < 0) {
            m_timerQueries = (epoxy_is_desktop_gl() && (epoxy_gl_version() >= 33 || epoxy_has_gl_extension("GL_ARB_timer_query"))) ? 1 : 0;
            if (m_timerQueries) {
                glGenQueries(int(m_queries.size()), m_queries.data());
            }
        }
        if (m_timerQueries) {
            const int slot = m_queryNext;
            m_queryNext = (m_queryNext + 1) % int(m_queryPending.size());
            if (m_queryPending[slot]) {
                profileCollect(true);
            }
            glQueryCounter(m_queries[slot * 2], GL_TIMESTAMP);
            painted = paintGlass(renderTarget, viewport, w, it->second, region, data);
            glQueryCounter(m_queries[slot * 2 + 1], GL_TIMESTAMP);
            m_queryPending[slot] = true;
        } else {
            glFinish();
            m_profileTimer.start();
            painted = paintGlass(renderTarget, viewport, w, it->second, region, data);
            glFinish();
            const qint64 ns = m_profileTimer.nsecsElapsed();
            m_profileGlassNs += ns;
            m_profileMaxNs = std::max(m_profileMaxNs, ns);
            ++m_profileDraws;
        }
    } else {
        painted = paintGlass(renderTarget, viewport, w, it->second, region, data);
    }
    const Kind kind = it->second.kind;
    const bool clipKind = kind == Kind::Menu || kind == Kind::Popup || kind == Kind::Notification || kind == Kind::Osd || kind == Kind::Tooltip;
    if (painted && clipKind && it->second.clipRadius > 0.5 && drawClipped(renderTarget, viewport, w, it->second, mask, region, data)) {
        return;
    }
    effects->drawWindow(renderTarget, viewport, w, painted ? (mask | PAINT_WINDOW_TRANSFORMED) : mask, region, data);
}

bool LiquidGlassEffect::roundable(EffectWindow *w) const
{
    if (w->isFullScreen()) {
        return false;
    }
    const QRectF frame = w->frameGeometry();
    const QRectF area = effects->clientArea(MaximizeArea, w);
    if (frame.width() >= area.width() - 1.0 && frame.height() >= area.height() - 1.0) {
        return false;
    }
    const QRectF expanded = w->expandedGeometry();
    return expanded.width() > frame.width() + 4.0 && expanded.height() > frame.height() + 4.0;
}

bool LiquidGlassEffect::drawClipped(const RenderTarget &renderTarget, const RenderViewport &viewport, EffectWindow *w, Glass &glass, int mask, const QRegion &region, const WindowPaintData &data)
{
    const double scale = viewport.scale();
    const QRectF geometry = snapToPixels(w->expandedGeometry(), scale);
    const QSize size = (geometry.size() * scale).toSize();
    if (size.isEmpty()) {
        return false;
    }
    const GLenum format = renderTarget.texture() ? renderTarget.texture()->internalFormat() : GL_RGBA8;
    if (!glass.clipTexture || glass.clipTexture->size() != size || glass.clipTexture->internalFormat() != format) {
        glass.clipFramebuffer.reset();
        glass.clipTexture = GLTexture::allocate(format, size);
        if (!glass.clipTexture) {
            return false;
        }
        glass.clipTexture->setFilter(GL_LINEAR);
        glass.clipTexture->setWrapMode(GL_CLAMP_TO_EDGE);
        glass.clipFramebuffer = std::make_unique<GLFramebuffer>(glass.clipTexture.get());
        if (!glass.clipFramebuffer->valid()) {
            glass.clipFramebuffer.reset();
            glass.clipTexture.reset();
            return false;
        }
    }

    {
        RenderTarget target(glass.clipFramebuffer.get());
        RenderViewport offscreen(geometry, scale, target);
        GLFramebuffer::pushFramebuffer(glass.clipFramebuffer.get());
        glClearColor(0.0, 0.0, 0.0, 0.0);
        glClear(GL_COLOR_BUFFER_BIT);
        WindowPaintData plain;
        plain.setOpacity(data.opacity());
        plain.setBrightness(data.brightness());
        plain.setSaturation(data.saturation());
        effects->drawWindow(target, offscreen, w, mask | PAINT_WINDOW_TRANSFORMED | PAINT_WINDOW_TRANSLUCENT, infiniteRegion(), plain);
        GLFramebuffer::popFramebuffer();
    }

    const bool transformed = !qFuzzyCompare(data.xScale(), 1.0) || !qFuzzyCompare(data.yScale(), 1.0) || data.rotationAngle() != 0.0;
    const QPointF shift = transformed ? QPointF() : QPointF(data.xTranslation(), data.yTranslation());
    QMatrix4x4 model;
    if (transformed) {
        const QPointF origin = w->pos() * scale;
        model.translate(float(origin.x()), float(origin.y()));
        model *= data.toMatrix(scale);
        model.translate(float(-origin.x()), float(-origin.y()));
    }
    const QRect device = snapToPixelGrid(scaledRect(geometry.translated(shift), scale));
    const QRectF shapeDevice = scaledRect(glass.clipShape, scale);
    const QMatrix4x4 texMatrix = glass.clipTexture->matrix(NormalizedCoordinates);
    auto vertex = [&](const QPointF &position, const QPointF &uv) {
        return GLVertex2D{
            .position = QVector2D(position),
            .texcoord = QVector2D(texMatrix.map(uv)),
        };
    };
    const float x0 = device.left();
    const float y0 = device.top();
    const float x1 = device.left() + device.width();
    const float y1 = device.top() + device.height();
    const GLVertex2D tl = vertex(QPointF(x0, y0), QPointF(0.0, 0.0));
    const GLVertex2D tr = vertex(QPointF(x1, y0), QPointF(1.0, 0.0));
    const GLVertex2D br = vertex(QPointF(x1, y1), QPointF(1.0, 1.0));
    const GLVertex2D bl = vertex(QPointF(x0, y1), QPointF(0.0, 1.0));
    const std::array<GLVertex2D, 6> vertices{tl, br, bl, tl, tr, br};

    GLVertexBuffer *vbo = GLVertexBuffer::streamingBuffer();
    vbo->reset();
    vbo->setAttribLayout(std::span(GLVertexBuffer::GLVertex2DLayout), sizeof(GLVertex2D));
    const auto map = vbo->map<GLVertex2D>(vertices.size());
    if (!map) {
        return false;
    }
    std::copy(vertices.begin(), vertices.end(), map->begin());
    vbo->unmap();

    ShaderBinder binder(m_clipShader.get());
    GLShader *shader = binder.shader();
    shader->setUniform("uMvp", viewport.projectionMatrix());
    shader->setUniform("uModel", model);
    shader->setUniform("uTex", 0);
    shader->setUniform("uRect", QVector4D(float(shapeDevice.center().x()), float(shapeDevice.center().y()), float(shapeDevice.width() / 2.0), float(shapeDevice.height() / 2.0)));
    shader->setUniform("uRadius", float(glass.clipRadius * scale));
    const bool window = glass.kind == Kind::Window;
    const bool active = w == effects->activeWindow();
    shader->setUniform("uShadow", window ? QVector3D(active ? 0.62f : 0.42f, float((active ? 14.0 : 8.0) * scale), float((active ? 17.0 : 12.0) * scale)) : QVector3D(0.0f, 0.0f, 1.0f));
    shader->setUniform("uStroke", window ? QVector2D(active ? 0.09f : 0.05f, active ? 0.38f : 0.26f) : QVector2D(0.0f, 0.0f));
    shader->setUniform("uScale", float(scale));
    shader->setUniform("uMean", 1);
    GLTexture *mean = nullptr;
    if (glass.kind == Kind::Notification) {
        const auto found = glass.render.find(m_currentScreen);
        if (found != glass.render.end() && !found->second.passes.empty() && !found->second.device.isEmpty()) {
            const Render &render = found->second;
            mean = render.passes.back().texture.get();
            const QPointF center = shapeDevice.center() - QPointF(render.device.topLeft());
            const float W = render.device.width();
            const float H = render.device.height();
            shader->setUniform("uMeanUv", QVector3D(float(center.x() / W), float(1.0 - center.y() / H), float(shapeDevice.width() * 0.3 / W)));
        }
    }
    shader->setUniform("uAdapt", mean ? 1.0f : 0.0f);
    shader->setUniform("uInkLeft", float(shapeDevice.left() + 48.0 * scale));
    if (mean) {
        glActiveTexture(GL_TEXTURE1);
        mean->bind();
        glActiveTexture(GL_TEXTURE0);
    }

    const QRegion logicalClip = region == infiniteRegion() ? QRegion(transformed ? viewport.renderRect().toAlignedRect() : geometry.translated(shift).toAlignedRect()) : region;
    const QRegion clipRegion = viewport.mapToRenderTarget(logicalClip);
    glEnable(GL_SCISSOR_TEST);
    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    vbo->bindArrays();
    glass.clipTexture->bind();
    vbo->draw(clipRegion, GL_TRIANGLES, 0, vertices.size(), true);
    glass.clipTexture->unbind();
    if (mean) {
        glActiveTexture(GL_TEXTURE1);
        mean->unbind();
        glActiveTexture(GL_TEXTURE0);
    }
    vbo->unbindArrays();
    glDisable(GL_BLEND);
    glDisable(GL_SCISSOR_TEST);
    return true;
}

void LiquidGlassEffect::profileCollect(bool wait)
{
    for (size_t slot = 0; slot < m_queryPending.size(); ++slot) {
        if (!m_queryPending[slot]) {
            continue;
        }
        GLint available = 0;
        glGetQueryObjectiv(m_queries[slot * 2 + 1], GL_QUERY_RESULT_AVAILABLE, &available);
        if (!available && !wait) {
            continue;
        }
        GLuint64 start = 0;
        GLuint64 end = 0;
        glGetQueryObjectui64v(m_queries[slot * 2], GL_QUERY_RESULT, &start);
        glGetQueryObjectui64v(m_queries[slot * 2 + 1], GL_QUERY_RESULT, &end);
        m_queryPending[slot] = false;
        if (end > start) {
            const qint64 ns = qint64(end - start);
            m_profileGlassNs += ns;
            m_profileMaxNs = std::max(m_profileMaxNs, ns);
            ++m_profileDraws;
        }
    }
}

void LiquidGlassEffect::postPaintScreen()
{
    if (m_animating) {
        for (const auto &[w, glass] : m_windows) {
            effects->addRepaint(glass.lastArea);
        }
    }
    if (m_profile && m_timerQueries > 0) {
        profileCollect(false);
    }
    if (m_profile && m_profileFrames >= 600) {
        qInfo("kwick_liquidglass: %d frames, %d animated frames at avg %.2f ms (%.1f fps) max %lld ms, glass %d draws GPU avg %.3f ms max %.3f ms (%s)",
              m_profileFrames, m_profileActive, m_profileActive ? m_profileActiveMs / m_profileActive : 0.0,
              m_profileActiveMs > 0.0 ? 1000.0 * m_profileActive / m_profileActiveMs : 0.0,
              static_cast<long long>(m_profileMaxInterval.count()), m_profileDraws,
              m_profileDraws ? m_profileGlassNs / 1e6 / m_profileDraws : 0.0, m_profileMaxNs / 1e6,
              m_timerQueries > 0 ? "timer queries" : "glFinish");
        m_profileFrames = 0;
        m_profileActive = 0;
        m_profileActiveMs = 0.0;
        m_profileDraws = 0;
        m_profileGlassNs = 0;
        m_profileMaxNs = 0;
        m_profileMaxInterval = 0ms;
    }
    effects->postPaintScreen();
}

}

#include "moc_liquidglasseffect.cpp"
