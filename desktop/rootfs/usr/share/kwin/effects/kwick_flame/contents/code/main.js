"use strict";

const skipClasses = [
    "ksmserver ksmserver",
    "ksmserver-logout-greeter ksmserver-logout-greeter",
    "ksplashqml ksplashqml",
    "spectacle spectacle",
    "spectacle org.kde.spectacle"
];

class KwickFlameEffect {
    constructor() {
        effect.configChanged.connect(this.loadConfig.bind(this));
        effect.animationEnded.connect(this.release.bind(this));
        effects.windowAdded.connect(this.onWindowAdded.bind(this));
        effects.windowClosed.connect(this.onWindowClosed.bind(this));
        effects.windowDataChanged.connect(this.onWindowDataChanged.bind(this));
        this.shader = effect.addFragmentShader(Effect.MapTexture, "flame.frag");
        this.loadConfig();
    }

    loadConfig() {
        this.duration = animationTime(effect.readConfig("Duration", 900));
        this.opening = effect.readConfig("Opening", true);
        effect.setUniform(this.shader, "uDuration", this.duration * 0.001);
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

    run(w, opening) {
        this.hold(w);
        effect.setUniform(this.shader, "uOpening", opening ? 1.0 : 0.0);
        effect.setUniform(this.shader, "uSeed", Math.random() * 64.0);
        return animate({
            window: w,
            curve: QEasingCurve.Linear,
            duration: this.duration,
            animations: [{
                type: Effect.ShaderUniform,
                fragmentShader: this.shader,
                uniform: "uProgress",
                from: 0.0,
                to: 1.0
            }]
        });
    }

    onWindowAdded(w) {
        if (!this.opening || effects.hasActiveFullScreenEffect || !KwickFlameEffect.wanted(w)) {
            return;
        }
        if (effect.isGrabbed(w, Effect.WindowAddedGrabRole)) {
            return;
        }
        w.kwickFlameIn = this.run(w, true);
    }

    onWindowClosed(w) {
        if (effects.hasActiveFullScreenEffect || !KwickFlameEffect.wanted(w) || w.skipsCloseAnimation) {
            return;
        }
        if (effect.isGrabbed(w, Effect.WindowClosedGrabRole)) {
            return;
        }
        if (w.kwickFlameIn) {
            cancel(w.kwickFlameIn);
            delete w.kwickFlameIn;
        }
        w.kwickFlameOut = this.run(w, false);
    }

    onWindowDataChanged(w, role) {
        if (role == Effect.WindowAddedGrabRole && w.kwickFlameIn && effect.isGrabbed(w, role)) {
            cancel(w.kwickFlameIn);
            delete w.kwickFlameIn;
            this.release(w);
        } else if (role == Effect.WindowClosedGrabRole && w.kwickFlameOut && effect.isGrabbed(w, role)) {
            cancel(w.kwickFlameOut);
            delete w.kwickFlameOut;
            this.release(w);
        }
    }
}

new KwickFlameEffect();
