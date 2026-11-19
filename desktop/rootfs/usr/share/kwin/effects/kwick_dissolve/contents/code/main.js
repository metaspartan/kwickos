"use strict";

const skipClasses = [
    "ksmserver ksmserver",
    "ksmserver-logout-greeter ksmserver-logout-greeter",
    "ksplashqml ksplashqml",
    "spectacle spectacle",
    "spectacle org.kde.spectacle"
];

class KwickDissolveEffect {
    constructor() {
        effect.configChanged.connect(this.loadConfig.bind(this));
        effect.animationEnded.connect(this.release.bind(this));
        effects.windowAdded.connect(this.onWindowAdded.bind(this));
        effects.windowClosed.connect(this.onWindowClosed.bind(this));
        effects.windowDataChanged.connect(this.onWindowDataChanged.bind(this));
        this.shader = effect.addFragmentShader(Effect.MapTexture, "dissolve.frag");
        this.loadConfig();
    }

    loadConfig() {
        this.duration = animationTime(effect.readConfig("Duration", 900));
        this.opening = effect.readConfig("Opening", true);

    }

    static wanted(w) {
        if (skipClasses.indexOf(w.windowClass) != -1) {
            return false;
        }
        if (w.popupWindow || w.outline || w.lockScreen || !w.managed || !w.visible) {
            return false;
        }
        if (!w.hasDecoration && w.onAllDesktops) {
            return false;
        }
        return w.hasDecoration || w.normalWindow || w.dialog;
    }

    hold(w) {
        w.setData(Effect.WindowForceBackgroundContrastRole, false);
        w.setData(Effect.WindowForceBlurRole, false);
    }

    release(w) {
        w.setData(Effect.WindowForceBackgroundContrastRole, null);
        w.setData(Effect.WindowForceBlurRole, null);
    }

    run(w, opening) {
        this.loadConfig();
        if (this.duration <= 1) {
            return null;
        }
        this.hold(w);
        const mx = Math.min(Math.max(0.15 * w.width, 60), 180);
        const my = Math.min(Math.max(0.3 * w.height, 90), 240);
        const sx = 1 + 2 * mx / Math.max(1, w.width);
        const sy = 1 + 2 * my / Math.max(1, w.height);
        const eg = w.expandedGeometry;
        const fg = w.geometry;
        const ew = Math.max(1, eg.width);
        const eh = Math.max(1, eg.height);
        const fixed = {
            uSeed: Math.random() * 64.0,
            uScaleX: sx,
            uScaleY: sy,
            uCenterX: (fg.x + fg.width / 2 - eg.x) / ew,
            uCenterY: 1 - (fg.y + fg.height / 2 - eg.y) / eh,
            uWidth: ew
        };
        const held = Object.keys(fixed).map(uniform => ({
            type: Effect.ShaderUniform,
            fragmentShader: this.shader,
            uniform: uniform,
            curve: QEasingCurve.Linear,
            from: fixed[uniform],
            to: fixed[uniform]
        }));
        return animate({
            window: w,
            curve: opening ? QEasingCurve.Linear : QEasingCurve.InQuad,
            duration: this.duration,
            animations: [{
                type: Effect.ShaderUniform,
                fragmentShader: this.shader,
                uniform: "uProgress",
                from: opening ? 1.0 : 0.0,
                to: opening ? 0.0 : 1.0
            }, {
                type: Effect.ShaderUniform,
                fragmentShader: this.shader,
                uniform: "uClock",
                curve: QEasingCurve.Linear,
                from: 0.0,
                to: this.duration * 0.001
            }, {
                type: Effect.Scale,
                curve: QEasingCurve.Linear,
                from: { value1: sx, value2: sy },
                to: { value1: sx, value2: sy }
            }].concat(held)
        });
    }

    onWindowAdded(w) {
        if (!this.opening || effects.hasActiveFullScreenEffect || !KwickDissolveEffect.wanted(w)) {
            return;
        }
        if (effect.isGrabbed(w, Effect.WindowAddedGrabRole)) {
            return;
        }
        w.KwickDissolveIn = this.run(w, true);
    }

    onWindowClosed(w) {
        if (effects.hasActiveFullScreenEffect || !KwickDissolveEffect.wanted(w) || w.skipsCloseAnimation) {
            return;
        }
        if (effect.isGrabbed(w, Effect.WindowClosedGrabRole)) {
            return;
        }
        if (w.KwickDissolveIn) {
            cancel(w.KwickDissolveIn);
            delete w.KwickDissolveIn;
        }
        w.KwickDissolveOut = this.run(w, false);
    }

    onWindowDataChanged(w, role) {
        if (role == Effect.WindowAddedGrabRole && w.KwickDissolveIn && effect.isGrabbed(w, role)) {
            cancel(w.KwickDissolveIn);
            delete w.KwickDissolveIn;
            this.release(w);
        } else if (role == Effect.WindowClosedGrabRole && w.KwickDissolveOut && effect.isGrabbed(w, role)) {
            cancel(w.KwickDissolveOut);
            delete w.KwickDissolveOut;
            this.release(w);
        }
    }
}

new KwickDissolveEffect();
