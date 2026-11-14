"use strict";

const skipClasses = [
    "ksmserver ksmserver",
    "ksmserver-logout-greeter ksmserver-logout-greeter",
    "ksplashqml ksplashqml",
    "spectacle spectacle",
    "spectacle org.kde.spectacle"
];

class KwickFlipEffect {
    constructor() {
        effect.configChanged.connect(this.loadConfig.bind(this));
        effect.animationEnded.connect(this.onEnded.bind(this));
        effects.windowAdded.connect(this.onWindowAdded.bind(this));
        effects.windowClosed.connect(this.onWindowClosed.bind(this));
        effects.windowDataChanged.connect(this.onWindowDataChanged.bind(this));
        this.shader = effect.addFragmentShader(Effect.MapTexture, "flip.frag");
        this.loadConfig();
    }

    loadConfig() {
        this.duration = animationTime(effect.readConfig("Duration", 700));
        this.opening = effect.readConfig("Opening", true);
        this.seeded = false;
        this.styleId = effect.readConfig("Style", 0);
        effect.setUniform(this.shader, "uStyle", this.styleId);
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
        w.setData(Effect.WindowForceBackgroundContrastRole, true);
        w.setData(Effect.WindowForceBlurRole, true);
    }

    release(w) {
        w.setData(Effect.WindowForceBackgroundContrastRole, null);
        w.setData(Effect.WindowForceBlurRole, null);
    }

    onEnded(w) {
        if (w.kwickPhase === 1) {
            w.kwickPhase = 2;
            w.KwickFlipIn = this.openNative(w);
            return;
        }
        w.kwickPhase = 0;
        this.release(w);
    }

    prepare(w) {
        this.hold(w);
        w.kwickPhase = 1;
        return animate({
            window: w,
            duration: 700,
            curve: QEasingCurve.Linear,
            animations: [{
                type: Effect.Opacity,
                from: 0.0,
                to: 0.0
            }]
        });
    }

    openNative(w) {
        this.hold(w);
        const dur = this.duration;
        return animate({
            window: w,
            duration: dur,
            curve: QEasingCurve.OutCubic,
            animations: [{
                type: Effect.Rotation,
                axis: this.styleId === 2 ? 0 : 1,
                from: this.styleId === 1 ? 72 : (this.styleId === 2 ? 62 : -72),
                to: 0
            }, {
                type: Effect.Opacity,
                from: 0.0,
                to: 1.0
            }, {
                type: Effect.Scale,
                from: { value1: 0.7, value2: 0.7 },
                to: { value1: 1.0, value2: 1.0 }
            }]
        });
    }

    run(w, opening) {
        this.loadConfig();
        this.hold(w);
        if (this.seeded) {
            effect.setUniform(this.shader, "uSeed", Math.random() * 64.0);
        }
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
            }]
        });
    }

    onWindowAdded(w) {
        if (!this.opening || effects.hasActiveFullScreenEffect || !KwickFlipEffect.wanted(w)) {
            return;
        }
        if (effect.isGrabbed(w, Effect.WindowAddedGrabRole)) {
            return;
        }
        w.KwickFlipIn = this.prepare(w);
    }

    onWindowClosed(w) {
        if (effects.hasActiveFullScreenEffect || !KwickFlipEffect.wanted(w) || w.skipsCloseAnimation) {
            return;
        }
        if (effect.isGrabbed(w, Effect.WindowClosedGrabRole)) {
            return;
        }
        if (w.KwickFlipIn) {
            cancel(w.KwickFlipIn);
            delete w.KwickFlipIn;
        }
        w.kwickPhase = 0;
        w.KwickFlipOut = this.run(w, false);
    }

    onWindowDataChanged(w, role) {
        if (role == Effect.WindowAddedGrabRole && w.KwickFlipIn && effect.isGrabbed(w, role)) {
            cancel(w.KwickFlipIn);
            delete w.KwickFlipIn;
            this.release(w);
        } else if (role == Effect.WindowClosedGrabRole && w.KwickFlipOut && effect.isGrabbed(w, role)) {
            cancel(w.KwickFlipOut);
            delete w.KwickFlipOut;
            this.release(w);
        }
    }
}

new KwickFlipEffect();
