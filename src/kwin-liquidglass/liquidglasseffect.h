#pragma once

#include "effect/effect.h"
#include "effect/effectwindow.h"
#include "scene/item.h"

#include <QElapsedTimer>
#include <QPointF>
#include <QRect>
#include <QRegion>

#include <array>
#include <chrono>
#include <map>
#include <memory>
#include <optional>
#include <vector>

namespace KWin
{

class GLFramebuffer;
class GLShader;
class GLTexture;
class Output;

class LiquidGlassEffect : public Effect
{
    Q_OBJECT

public:
    LiquidGlassEffect();
    ~LiquidGlassEffect() override;

    static bool supported();
    static bool enabledByDefault();

    void reconfigure(ReconfigureFlags flags) override;
    void prePaintScreen(ScreenPrePaintData &data, std::chrono::milliseconds presentTime) override;
    void prePaintWindow(EffectWindow *w, WindowPrePaintData &data, std::chrono::milliseconds presentTime) override;
    void drawWindow(const RenderTarget &renderTarget, const RenderViewport &viewport, EffectWindow *w, int mask, const QRegion &region, WindowPaintData &data) override;
    void postPaintScreen() override;
    bool isActive() const override;
    int requestedEffectChainPosition() const override;
    bool blocksDirectScanout() const override;
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    enum class Kind {
        None,
        Bar,
        Dock,
        Menu,
        Popup,
        Notification,
        Tooltip,
        Osd,
        Search,
        Frame,
        Window,
    };

    struct Pass
    {
        std::unique_ptr<GLTexture> texture;
        std::unique_ptr<GLFramebuffer> framebuffer;
    };

    struct Render
    {
        std::vector<Pass> passes;
        QRect device;
        GLenum format = 0;
        bool primed = false;
        bool dirty = true;
    };

    struct Glass
    {
        std::optional<QRegion> content;
        std::optional<QRegion> frame;
        Kind kind = Kind::None;
        std::map<Output *, Render> render;
        ItemEffect itemEffect;
        QRect lastArea;
        std::unique_ptr<GLTexture> clipTexture;
        std::unique_ptr<GLFramebuffer> clipFramebuffer;
        QRectF clipShape;
        double clipRadius = 0.0;
        double hover = 0.0;
        double hoverTarget = 0.0;
        QPointF pointer;
    };

    struct Look
    {
        float refract = 1.0f;
        float frost = 0.5f;
        float bevel = 18.0f;
        int levels = 3;
        float offset = 2.5f;
        float tint = 1.0f;
        float sat = 1.32f;
        float darkMin = 0.04f;
        float darkMax = 0.30f;
        float mul = 0.0f;
        float veil = 0.0f;
    };

    void slotWindowAdded(EffectWindow *w);
    void slotWindowDeleted(EffectWindow *w);
    void slotScreenRemoved(Output *output);
    void slotMouseChanged(const QPointF &pos);
    void updateWindow(EffectWindow *w);
    Kind classify(EffectWindow *w) const;
    QRegion glassRegion(EffectWindow *w, const Glass &glass) const;
    QRectF shapeRect(EffectWindow *w, const Glass &glass) const;
    QRect area(EffectWindow *w, const Glass &glass) const;
    double radiusFor(EffectWindow *w, const Glass &glass, const QRectF &shape) const;
    Look lookFor(Kind kind) const;
    bool ensureShaders();
    bool ensurePasses(Render &render, const QSize &size, GLenum format, int levels);
    bool roundable(EffectWindow *w) const;
    bool drawClipped(const RenderTarget &renderTarget, const RenderViewport &viewport, EffectWindow *w, Glass &glass, int mask, const QRegion &region, const WindowPaintData &data);
    bool paintGlass(const RenderTarget &renderTarget, const RenderViewport &viewport, EffectWindow *w, Glass &glass, const QRegion &region, const WindowPaintData &data);

    std::map<EffectWindow *, Glass> m_windows;
    std::map<EffectWindow *, QMetaObject::Connection> m_connections;
    std::unique_ptr<GLShader> m_downShader;
    std::unique_ptr<GLShader> m_upShader;
    std::unique_ptr<GLShader> m_glassShader;
    std::unique_ptr<GLShader> m_clipShader;
    bool m_shaderFailed = false;
    Output *m_currentScreen = nullptr;
    QRegion m_paintedArea;
    QRegion m_currentGlass;
    std::chrono::milliseconds m_lastPresent{-1};
    bool m_animating = false;

    double m_refraction = 0.6;
    double m_blur = 0.5;
    double m_dispersion = 0.35;
    double m_specular = 0.7;
    double m_tint = 1.0;
    int m_style = 0;
    int m_radius = 12;
    bool m_titleBars = false;
    bool m_menuBar = false;
    bool m_light = false;
    bool m_interactive = true;
    bool m_profile = false;
    bool m_bypass = false;
    bool m_roundWindows = true;
    EffectWindow *m_lastActive = nullptr;

    void profileCollect(bool wait);

    QElapsedTimer m_profileTimer;
    qint64 m_profileGlassNs = 0;
    qint64 m_profileMaxNs = 0;
    int m_profileDraws = 0;
    int m_profileFrames = 0;
    int m_profileActive = 0;
    double m_profileActiveMs = 0.0;
    std::chrono::milliseconds m_profileLast{-1};
    std::chrono::milliseconds m_profileMaxInterval{0};
    int m_timerQueries = -1;
    std::array<unsigned int, 32> m_queries{};
    std::array<bool, 16> m_queryPending{};
    int m_queryNext = 0;
};

}
