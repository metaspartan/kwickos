#include "flipeffect.h"

#include "core/colorspace.h"
#include "core/pixelgrid.h"
#include "core/rendertarget.h"
#include "core/renderviewport.h"
#include "effect/effecthandler.h"
#include "opengl/glframebuffer.h"
#include "opengl/glshader.h"
#include "opengl/glshadermanager.h"
#include "opengl/gltexture.h"
#include "opengl/glvertexbuffer.h"
#include "scene/windowitem.h"

#include <KConfigGroup>
#include <KSharedConfig>

#include <QFile>
#include <QMatrix4x4>
#include <QSet>
#include <QVector4D>
#include <QtMath>

#include <algorithm>
#include <array>
#include <cmath>
#include <limits>

using namespace std::chrono_literals;

namespace KWin
{

static const QSet<QString> s_skipClasses{
    QStringLiteral("ksmserver ksmserver"),
    QStringLiteral("ksmserver-logout-greeter ksmserver-logout-greeter"),
    QStringLiteral("ksplashqml ksplashqml"),
    QStringLiteral("spectacle spectacle"),
    QStringLiteral("spectacle org.kde.spectacle"),
};

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

FlipEffect::FlipEffect()
{
    reconfigure(ReconfigureAll);

    connect(effects, &EffectsHandler::windowAdded, this, &FlipEffect::slotWindowAdded);
    connect(effects, &EffectsHandler::windowClosed, this, &FlipEffect::slotWindowClosed);
    connect(effects, &EffectsHandler::windowDeleted, this, &FlipEffect::slotWindowDeleted);
    connect(effects, &EffectsHandler::windowDataChanged, this, &FlipEffect::slotWindowDataChanged);
}

FlipEffect::~FlipEffect()
{
    if (!m_animations.empty() || m_shader) {
        effects->makeOpenGLContextCurrent();
        m_animations.clear();
        m_shader.reset();
    }
}

bool FlipEffect::supported()
{
    return effects->isOpenGLCompositing() && effects->animationsSupported();
}

void FlipEffect::reconfigure(ReconfigureFlags flags)
{
    Q_UNUSED(flags)
    KSharedConfigPtr config = effects->config();
    config->reparseConfiguration();
    const KConfigGroup group = config->group(QStringLiteral("Effect-kwick_flip"));
    const double ms = animationTime(group, QStringLiteral("Duration"), 700ms);
    m_duration = std::chrono::milliseconds(std::max(1, static_cast<int>(ms)));
    m_opening = group.readEntry("Opening", true);
    m_style = std::clamp(group.readEntry("Style", 0), 0, 2);
}

int FlipEffect::requestedEffectChainPosition() const
{
    return 50;
}

bool FlipEffect::blocksDirectScanout() const
{
    return false;
}

bool FlipEffect::isActive() const
{
    return !m_animations.empty();
}

bool FlipEffect::wanted(EffectWindow *w) const
{
    if (s_skipClasses.contains(w->windowClass())) {
        return false;
    }
    if (w->isPopupWindow() || w->isOutline() || w->isLockScreen() || !w->isManaged() || !w->isVisible()) {
        return false;
    }
    if (!w->hasDecoration() && w->isOnAllDesktops()) {
        return false;
    }
    return w->hasDecoration() || w->isNormalWindow() || w->isDialog();
}

void FlipEffect::slotWindowAdded(EffectWindow *w)
{
    if (!m_opening || effects->animationTimeFactor() <= 0.0 || effects->activeFullScreenEffect() || !wanted(w)) {
        return;
    }
    const void *grab = w->data(WindowAddedGrabRole).value<void *>();
    if (grab && grab != this) {
        return;
    }
    w->setData(WindowAddedGrabRole, QVariant::fromValue(static_cast<void *>(this)));

    m_animations.erase(w);
    Animation &animation = m_animations[w];
    animation.timeLine.setDuration(m_duration);
    animation.timeLine.setEasingCurve(QEasingCurve::Linear);
    animation.itemEffect = ItemEffect(w->windowItem());
    effects->addRepaintFull();
}

void FlipEffect::slotWindowClosed(EffectWindow *w)
{
    const void *grab = w->data(WindowClosedGrabRole).value<void *>();
    if (grab && grab != this) {
        dropAnimation(w);
        return;
    }
    if (effects->animationTimeFactor() <= 0.0 || effects->activeFullScreenEffect() || !wanted(w) || w->skipsCloseAnimation()) {
        dropAnimation(w);
        return;
    }
    qreal resume = 0.0;
    auto it = m_animations.find(w);
    if (it != m_animations.end() && !it->second.closing) {
        if (!it->second.started) {
            dropAnimation(w);
            return;
        }
        resume = 1.0 - it->second.timeLine.value();
    }
    w->setData(WindowClosedGrabRole, QVariant::fromValue(static_cast<void *>(this)));

    Animation &animation = m_animations[w];
    animation.closing = true;
    animation.ready = true;
    animation.started = false;
    animation.textureGeometry = QRectF();
    animation.deletedRef = EffectWindowDeletedRef(w);
    animation.itemEffect = ItemEffect(w->windowItem());
    animation.timeLine.reset();
    animation.timeLine.setDuration(m_duration);
    animation.timeLine.setEasingCurve(QEasingCurve::Linear);
    if (resume > 0.0) {
        animation.timeLine.setElapsed(std::chrono::milliseconds(static_cast<int>(resume * m_duration.count())));
    }
    effects->addRepaintFull();
}

void FlipEffect::slotWindowDeleted(EffectWindow *w)
{
    dropAnimation(w);
}

void FlipEffect::slotWindowDataChanged(EffectWindow *w, int role)
{
    if (role != WindowAddedGrabRole && role != WindowClosedGrabRole) {
        return;
    }
    const void *grab = w->data(role).value<void *>();
    if (!grab || grab == this) {
        return;
    }
    dropAnimation(w);
}

void FlipEffect::dropAnimation(EffectWindow *w)
{
    auto it = m_animations.find(w);
    if (it == m_animations.end()) {
        return;
    }
    effects->makeOpenGLContextCurrent();
    m_animations.erase(it);
    effects->addRepaintFull();
}

void FlipEffect::prePaintWindow(EffectWindow *w, WindowPrePaintData &data, std::chrono::milliseconds presentTime)
{
    auto it = m_animations.find(w);
    if (it != m_animations.end()) {
        Animation &animation = it->second;
        if (animation.ready) {
            if (animation.started) {
                const auto delta = std::clamp(presentTime - animation.lastPresent, 0ms, 100ms);
                animation.timeLine.setElapsed(animation.timeLine.elapsed() + delta);
            }
            animation.lastPresent = presentTime;
            animation.started = true;
        } else {
            if (animation.firstSeen < 0ms) {
                animation.firstSeen = presentTime;
            }
            ++animation.waitFrames;
            if (presentTime - animation.firstSeen >= 250ms) {
                animation.waitFrames = std::max(animation.waitFrames, 3);
            }
        }
        const QRect current = bounds(w, animation);
        data.paint |= QRegion(current) | QRegion(animation.lastBounds);
        animation.lastBounds = current;
        data.setTranslucent();
        data.setTransformed();
    }
    effects->prePaintWindow(w, data, presentTime);
}

bool FlipEffect::ensureShader()
{
    if (m_shader) {
        return true;
    }
    if (m_shaderFailed) {
        return false;
    }
    const QByteArray vertex = readShader(QStringLiteral(":/effects/kwick_flip/shaders/flip.vert"));
    const QByteArray fragment = readShader(QStringLiteral(":/effects/kwick_flip/shaders/flip.frag"));
    if (!vertex.isEmpty() && !fragment.isEmpty()) {
        m_shader = ShaderManager::instance()->generateCustomShader(ShaderTrait::MapTexture, vertex, fragment);
    }
    if (!m_shader || !m_shader->isValid()) {
        m_shader.reset();
        m_shaderFailed = true;
        return false;
    }
    return true;
}

bool FlipEffect::renderOffscreen(Animation &animation, EffectWindow *w, double scale)
{
    if (animation.closing && animation.texture && animation.textureGeometry.isValid()) {
        return true;
    }

    const QRectF geometry = snapToPixels(w->expandedGeometry(), scale);
    const QSize size = (geometry.size() * scale).toSize();
    if (size.isEmpty()) {
        return animation.texture != nullptr;
    }

    if (!animation.texture || animation.texture->size() != size) {
        animation.framebuffer.reset();
        const int levels = 1 + int(std::floor(std::log2(double(std::max(size.width(), size.height())))));
        animation.texture = GLTexture::allocate(GL_RGBA8, size, levels);
        if (!animation.texture) {
            animation.texture = GLTexture::allocate(GL_RGBA8, size);
        }
        if (!animation.texture) {
            return false;
        }
        animation.texture->setFilter(GL_LINEAR_MIPMAP_LINEAR);
        animation.texture->setWrapMode(GL_CLAMP_TO_EDGE);
        if (epoxy_has_gl_extension("GL_EXT_texture_filter_anisotropic") || epoxy_has_gl_extension("GL_ARB_texture_filter_anisotropic")) {
            animation.texture->bind();
            glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY_EXT, 8.0f);
            animation.texture->unbind();
        }
        animation.framebuffer = std::make_unique<GLFramebuffer>(animation.texture.get());
        if (!animation.framebuffer->valid()) {
            animation.framebuffer.reset();
            animation.texture.reset();
            return false;
        }
    }
    animation.textureGeometry = geometry;

    const QVariant blurRole = w->data(WindowForceBlurRole);
    const QVariant contrastRole = w->data(WindowForceBackgroundContrastRole);
    if (blurRole.isValid()) {
        w->setData(WindowForceBlurRole, QVariant());
    }
    if (contrastRole.isValid()) {
        w->setData(WindowForceBackgroundContrastRole, QVariant());
    }

    RenderTarget target(animation.framebuffer.get());
    RenderViewport viewport(geometry, scale, target);
    GLFramebuffer::pushFramebuffer(animation.framebuffer.get());
    glClearColor(0.0, 0.0, 0.0, 0.0);
    glClear(GL_COLOR_BUFFER_BIT);

    WindowPaintData data;
    data.setOpacity(1.0);
    effects->drawWindow(target, viewport, w, PAINT_WINDOW_TRANSFORMED | PAINT_WINDOW_TRANSLUCENT, infiniteRegion(), data);

    GLFramebuffer::popFramebuffer();
    animation.texture->generateMipmaps();

    if (blurRole.isValid()) {
        w->setData(WindowForceBlurRole, blurRole);
    }
    if (contrastRole.isValid()) {
        w->setData(WindowForceBackgroundContrastRole, contrastRole);
    }
    return true;
}

static qreal springOpen(qreal t)
{
    constexpr qreal zeta = 0.72;
    constexpr qreal omega = 8.6;
    const qreal decay = zeta * omega;
    const qreal damped = omega * std::sqrt(1.0 - zeta * zeta);
    auto x = [&](qreal s) {
        return std::exp(-decay * s) * (std::cos(damped * s) + decay / damped * std::sin(damped * s));
    };
    return x(t) - x(1.0) * t;
}

FlipEffect::Pose FlipEffect::pose(EffectWindow *w, const Animation &animation, double scale) const
{
    Pose result;
    const qreal t = animation.started ? std::clamp(animation.timeLine.value(), 0.0, 1.0) : 0.0;
    if (animation.closing) {
        result.progress = t * t;
        result.eased = t * t * (3.0 - 2.0 * t);
    } else {
        const qreal r = 1.0 - t;
        result.progress = r * r * r;
        result.eased = springOpen(t);
    }

    const QRectF frame = snapToPixels(w->frameGeometry(), scale);
    result.half = frame.size() / 2.0;
    if (result.half.isEmpty()) {
        return result;
    }
    const qreal hw = result.half.width();
    const qreal hh = result.half.height();
    const qreal big = std::max(hw, hh);
    const qreal distance = big * 2.6;

    QVector3D axis(0.0f, 1.0f, 0.0f);
    QPointF pivot(0.0, 0.0);
    qreal maxAngle = animation.closing ? 1.36 : 1.45;
    qreal sign = 1.0;
    qreal depth = 0.55;
    if (m_style == 1) {
        pivot = QPointF(-hw, 0.0);
        maxAngle = animation.closing ? 1.15 : 1.35;
        depth = 0.0;
    } else if (m_style == 2) {
        axis = QVector3D(1.0f, 0.0f, 0.0f);
        pivot = QPointF(0.0, -hh);
        maxAngle = animation.closing ? 1.25 : 1.38;
        sign = -1.0;
        depth = 0.25;
    }
    const float degrees = float(qRadiansToDegrees(sign * maxAngle * result.eased));

    QMatrix4x4 rotation;
    rotation.rotate(degrees, axis);
    result.normal = rotation.mapVector(QVector3D(0.0f, 0.0f, 1.0f));

    const QMatrix4x4 toCentered(1.0f, 0.0f, 0.0f, float(-hw),
                                0.0f, -1.0f, 0.0f, float(hh),
                                0.0f, 0.0f, 1.0f, 0.0f,
                                0.0f, 0.0f, 0.0f, 1.0f);
    QMatrix4x4 model;
    model.translate(float(pivot.x()), float(pivot.y()), float(-depth * big * result.eased));
    model.rotate(degrees, axis);
    model.translate(float(-pivot.x()), float(-pivot.y()), 0.0f);

    const qreal cx = frame.center().x();
    const qreal cy = frame.center().y();
    const QMatrix4x4 perspective(float(distance), 0.0f, float(-cx), float(cx * distance),
                                 0.0f, float(-distance), float(-cy), float(cy * distance),
                                 0.0f, 0.0f, 0.0f, 0.0f,
                                 0.0f, 0.0f, -1.0f, float(distance));
    result.perspective = perspective;
    result.world = model * toCentered;
    result.transform = perspective * result.world;
    result.distance = distance;
    result.depthShift = big;
    result.valid = true;
    return result;
}

QRect FlipEffect::bounds(EffectWindow *w, const Animation &animation) const
{
    const QRectF expanded = w->expandedGeometry();
    if (!animation.ready) {
        return expanded.toAlignedRect();
    }
    const Pose ps = pose(w, animation, 1.0);
    if (!ps.valid) {
        return expanded.toAlignedRect();
    }
    const QRectF source = animation.textureGeometry.isValid() ? animation.textureGeometry : expanded;
    const QRectF local = source.translated(-w->frameGeometry().topLeft());
    qreal left = std::numeric_limits<qreal>::max();
    qreal top = left;
    qreal right = std::numeric_limits<qreal>::lowest();
    qreal bottom = right;
    for (const QPointF &corner : {local.topLeft(), local.topRight(), local.bottomRight(), local.bottomLeft()}) {
        const QVector4D v = ps.transform.map(QVector4D(float(corner.x()), float(corner.y()), 0.0f, 1.0f));
        if (v.w() <= 0.0f) {
            return effects->virtualScreenGeometry();
        }
        const qreal x = v.x() / v.w();
        const qreal y = v.y() / v.w();
        left = std::min(left, x);
        top = std::min(top, y);
        right = std::max(right, x);
        bottom = std::max(bottom, y);
    }
    const int margin = int(0.5 * std::max(ps.half.width(), ps.half.height())) + 80;
    return QRectF(QPointF(left, top), QPointF(right, bottom)).toAlignedRect().adjusted(-margin, -margin, margin, margin);
}

void FlipEffect::scheduleRepaint(EffectWindow *w, const Animation &animation) const
{
    effects->addRepaint(QRegion(animation.lastBounds) | QRegion(w->expandedGeometry().toAlignedRect()));
}

void FlipEffect::paintFlipped(const RenderTarget &renderTarget, const RenderViewport &viewport, EffectWindow *w, const QRegion &region, const WindowPaintData &data, Animation &animation)
{
    const double scale = viewport.scale();
    const Pose ps = pose(w, animation, scale);
    if (!ps.valid) {
        return;
    }
    const QRectF frame = snapToPixels(w->frameGeometry(), scale);
    const QSizeF half = ps.half;
    const qreal p = ps.progress;
    const qreal e = std::clamp(ps.eased, 0.0, 1.0);
    const qreal big = ps.depthShift;

    QMatrix4x4 device;
    device.scale(float(scale), float(scale), 1.0f);
    const QMatrix4x4 screen = viewport.projectionMatrix() * device;
    const QMatrix4x4 mvp = screen * ps.transform;
    const QRectF local = animation.textureGeometry.translated(-frame.topLeft());
    const QMatrix4x4 texMatrix = animation.texture->matrix(NormalizedCoordinates);
    auto vertex = [&](const QPointF &position, const QPointF &uv) {
        const QPointF tc = texMatrix.map(uv);
        return GLVertex2D{
            .position = QVector2D(position),
            .texcoord = QVector2D(tc),
        };
    };

    const qreal fadeIn = std::clamp((p - 0.45) / 0.55, 0.0, 1.0);
    const qreal fadeLevel = (1.0 - fadeIn * fadeIn * (3.0 - 2.0 * fadeIn)) * data.opacity();
    const qreal sigma = 8.0 + 0.06 * big * e;
    const qreal strength = 0.6 * e * fadeLevel;
    QMatrix4x4 quad;
    bool shadow = strength > 0.004;
    QRectF shadowRect;
    if (shadow) {
        QMatrix4x4 drop;
        drop.translate(0.0f, float(-0.1 * big * e), float(-0.08 * big * e));
        const QMatrix4x4 project = ps.perspective * drop * ps.world;
        const std::array<QPointF, 4> corners{QPointF(0.0, 0.0), QPointF(frame.width(), 0.0), QPointF(frame.width(), frame.height()), QPointF(0.0, frame.height())};
        qreal left = std::numeric_limits<qreal>::max();
        qreal top = left;
        qreal right = std::numeric_limits<qreal>::lowest();
        qreal bottom = right;
        for (int i = 0; i < 4; ++i) {
            const QVector4D v = project.map(QVector4D(float(corners[i].x()), float(corners[i].y()), 0.0f, 1.0f));
            if (v.w() <= 1e-3f) {
                shadow = false;
                break;
            }
            const qreal x = v.x() / v.w();
            const qreal y = v.y() / v.w();
            quad.setColumn(i, QVector4D(float(x), float(y), 0.0f, 0.0f));
            left = std::min(left, x);
            top = std::min(top, y);
            right = std::max(right, x);
            bottom = std::max(bottom, y);
        }
        const qreal reach = sigma * 5.5 + 2.0;
        shadowRect = QRectF(QPointF(left, top), QPointF(right, bottom)).adjusted(-reach, -reach, reach, reach);
    }

    const GLVertex2D tl = vertex(local.topLeft(), QPointF(0.0, 0.0));
    const GLVertex2D tr = vertex(local.topRight(), QPointF(1.0, 0.0));
    const GLVertex2D br = vertex(local.bottomRight(), QPointF(1.0, 1.0));
    const GLVertex2D bl = vertex(local.bottomLeft(), QPointF(0.0, 1.0));
    const GLVertex2D stl{.position = QVector2D(shadowRect.topLeft()), .texcoord = QVector2D()};
    const GLVertex2D str{.position = QVector2D(shadowRect.topRight()), .texcoord = QVector2D()};
    const GLVertex2D sbr{.position = QVector2D(shadowRect.bottomRight()), .texcoord = QVector2D()};
    const GLVertex2D sbl{.position = QVector2D(shadowRect.bottomLeft()), .texcoord = QVector2D()};
    const std::array<GLVertex2D, 12> vertices{stl, str, sbr, stl, sbr, sbl, tl, tr, br, tl, br, bl};

    GLVertexBuffer *vbo = GLVertexBuffer::streamingBuffer();
    vbo->reset();
    vbo->setAttribLayout(std::span(GLVertexBuffer::GLVertex2DLayout), sizeof(GLVertex2D));
    const auto map = vbo->map<GLVertex2D>(vertices.size());
    if (!map) {
        return;
    }
    std::copy(vertices.begin(), vertices.end(), map->begin());
    vbo->unmap();

    ShaderBinder binder(m_shader.get());
    GLShader *shader = binder.shader();
    shader->setUniform("uHalf", QVector2D(float(half.width()), float(half.height())));
    shader->setUniform("uNormal", ps.normal);
    shader->setUniform("uEased", float(ps.eased));
    shader->setUniform("uProgress", float(p));
    shader->setUniform("uOpacity", float(data.opacity()));
    shader->setUniform("uDistance", float(ps.distance));
    shader->setUniform("sampler", 0);
    shader->setColorspaceUniforms(ColorDescription::sRGB, renderTarget.colorDescription(), RenderingIntent::Perceptual);

    const bool clipping = region != infiniteRegion();
    const QRegion clipRegion = clipping ? viewport.mapToRenderTarget(region) : infiniteRegion();
    if (clipping) {
        glEnable(GL_SCISSOR_TEST);
    }
    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

    vbo->bindArrays();
    animation.texture->bind();

    if (shadow) {
        shader->setUniform("uMvp", screen);
        shader->setUniform("uWorld", QMatrix4x4());
        shader->setUniform("uQuad", quad);
        shader->setUniform("uSigma", float(sigma));
        shader->setUniform("uShadow", float(strength));
        shader->setUniform("uPass", 1);
        vbo->draw(clipRegion, GL_TRIANGLES, 0, 6, clipping);
    }

    shader->setUniform("uMvp", mvp);
    shader->setUniform("uWorld", ps.world);
    shader->setUniform("uPass", 0);
    vbo->draw(clipRegion, GL_TRIANGLES, 6, 6, clipping);

    animation.texture->unbind();
    vbo->unbindArrays();

    glDisable(GL_BLEND);
    if (clipping) {
        glDisable(GL_SCISSOR_TEST);
    }
}

void FlipEffect::drawWindow(const RenderTarget &renderTarget, const RenderViewport &viewport, EffectWindow *w, int mask, const QRegion &region, WindowPaintData &data)
{
    auto it = m_animations.find(w);
    if (it == m_animations.end() || !ensureShader()) {
        effects->drawWindow(renderTarget, viewport, w, mask, region, data);
        return;
    }
    Animation &animation = it->second;

    if (!renderOffscreen(animation, w, viewport.scale())) {
        if (animation.ready) {
            effects->drawWindow(renderTarget, viewport, w, mask, region, data);
        }
        return;
    }

    if (!animation.ready) {
        if (w->hasDecoration() || animation.waitFrames >= 3) {
            animation.ready = true;
        }
        return;
    }

    paintFlipped(renderTarget, viewport, w, region, data, animation);
}

void FlipEffect::postPaintScreen()
{
    if (!m_animations.empty()) {
        bool erased = false;
        for (auto it = m_animations.begin(); it != m_animations.end();) {
            Animation &animation = it->second;
            const bool finished = animation.ready && animation.started && animation.timeLine.done();
            const bool stuck = !animation.ready && animation.waitFrames > 240;
            scheduleRepaint(it->first, animation);
            if (finished || stuck) {
                if (!erased) {
                    effects->makeOpenGLContextCurrent();
                    erased = true;
                }
                it = m_animations.erase(it);
            } else {
                ++it;
            }
        }
    }
    effects->postPaintScreen();
}

}

#include "moc_flipeffect.cpp"
