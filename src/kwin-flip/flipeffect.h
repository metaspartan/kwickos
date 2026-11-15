#pragma once

#include "effect/effect.h"
#include "effect/effectwindow.h"
#include "effect/timeline.h"
#include "scene/item.h"

#include <QMatrix4x4>
#include <QRect>
#include <QVector3D>

#include <chrono>
#include <map>
#include <memory>

namespace KWin
{

class GLFramebuffer;
class GLShader;
class GLTexture;

class FlipEffect : public Effect
{
    Q_OBJECT

public:
    FlipEffect();
    ~FlipEffect() override;

    static bool supported();

    void reconfigure(ReconfigureFlags flags) override;
    void prePaintWindow(EffectWindow *w, WindowPrePaintData &data, std::chrono::milliseconds presentTime) override;
    void drawWindow(const RenderTarget &renderTarget, const RenderViewport &viewport, EffectWindow *w, int mask, const QRegion &region, WindowPaintData &data) override;
    void postPaintScreen() override;
    bool isActive() const override;
    int requestedEffectChainPosition() const override;
    bool blocksDirectScanout() const override;

private:
    struct Animation
    {
        TimeLine timeLine;
        EffectWindowDeletedRef deletedRef;
        ItemEffect itemEffect;
        std::unique_ptr<GLTexture> texture;
        std::unique_ptr<GLFramebuffer> framebuffer;
        QRectF textureGeometry;
        QRect lastBounds;
        bool closing = false;
        bool ready = false;
        bool started = false;
        int waitFrames = 0;
        std::chrono::milliseconds firstSeen{-1};
        std::chrono::milliseconds lastPresent{0};
    };

    struct Pose
    {
        QMatrix4x4 transform;
        QVector3D normal;
        QSizeF half;
        qreal progress = 0.0;
        qreal eased = 0.0;
        bool valid = false;
    };

    void slotWindowAdded(EffectWindow *w);
    void slotWindowClosed(EffectWindow *w);
    void slotWindowDeleted(EffectWindow *w);
    void slotWindowDataChanged(EffectWindow *w, int role);

    bool wanted(EffectWindow *w) const;
    bool ensureShader();
    bool renderOffscreen(Animation &animation, EffectWindow *w, double scale);
    void paintFlipped(const RenderTarget &renderTarget, const RenderViewport &viewport, EffectWindow *w, const QRegion &region, const WindowPaintData &data, Animation &animation);
    Pose pose(EffectWindow *w, const Animation &animation, double scale) const;
    QRect bounds(EffectWindow *w, const Animation &animation) const;
    void scheduleRepaint(EffectWindow *w, const Animation &animation) const;
    void dropAnimation(EffectWindow *w);

    std::map<EffectWindow *, Animation> m_animations;
    std::unique_ptr<GLShader> m_shader;
    bool m_shaderFailed = false;
    std::chrono::milliseconds m_duration{700};
    bool m_opening = true;
    int m_style = 0;
};

}
