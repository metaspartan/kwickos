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
        this.duration = animationTime(effect.readConfig("Style", 0) === 4 ? effect.readConfig("LegacyDuration", 1000) : effect.readConfig("Duration", 1100));
        this.opening = effect.readConfig("Opening", true);
        this.style = effect.readConfig("Style", 0);
        this.heightScale = effect.readConfig("Height", 100) / 100;
        effect.setUniform(this.shader, "uStyle", this.style);
        effect.setUniform(this.shader, "uHeight", this.heightScale);
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

    run(w, opening, elapsed) {
        this.loadConfig();
        if (this.duration <= 1) {
            return null;
        }
        this.hold(w);
        const done = Math.min(Math.max(elapsed || 0, 0), this.duration - 1);
        if (!done) {
            w.KwickFlameStart = Date.now();
            w.KwickFlameSeed = Math.random() * 64.0;
        }
        const u = 1 - done / this.duration;
        const start = opening ? u * u * u : 0.0;
        const hs = Math.max(0.3, this.heightScale);
        const eg = w.expandedGeometry;
        const fg = w.frameGeometry || w.geometry;
        const ew = Math.max(1, eg.width);
        const eh = Math.max(1, eg.height);
        const fh = Math.max(1, fg.height);
        const room = Math.max(0, fg.y - eg.y);
        const over = Math.min(room, Math.round(Math.min(0.08 * fh, 40) * hs * (this.style === 1 ? 1.15 : 1.0)));
        const bottom = 1 - (fg.y + fg.height - eg.y) / eh;
        const fixed = {
            uSeed: w.KwickFlameSeed,
            uFrameL: (fg.x - eg.x) / ew,
            uFrameR: (fg.x + fg.width - eg.x) / ew,
            uFrameB: bottom,
            uFrameT: 1 - (fg.y - eg.y) / eh,
            uLogW: ew,
            uLogH: eh,
            uOver: over
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
            curve: opening ? QEasingCurve.OutCubic : QEasingCurve.InQuad,
            duration: this.duration - done,
            animations: [{
                type: Effect.ShaderUniform,
                fragmentShader: this.shader,
                uniform: "uProgress",
                from: opening ? start : 0.0,
                to: opening ? 0.0 : 1.0
            }, {
                type: Effect.ShaderUniform,
                fragmentShader: this.shader,
                uniform: "uClock",
                curve: QEasingCurve.Linear,
                from: done * 0.001,
                to: this.duration * 0.001
            }].concat(held)
        });
    }

    onWindowAdded(w) {
        if (!this.opening || effects.hasActiveFullScreenEffect || !KwickFlameEffect.wanted(w)) {
            return;
        }
        if (effect.isGrabbed(w, Effect.WindowAddedGrabRole)) {
            return;
        }
        if (!w.KwickFlameHooked && w.windowFrameGeometryChanged) {
            w.KwickFlameHooked = true;
            w.windowFrameGeometryChanged.connect(this.onGeometryChanged.bind(this, w));
        }
        w.KwickFlameIn = this.run(w, true);
    }

    onGeometryChanged(w) {
        if (!w.KwickFlameIn || w.KwickFlameOut) {
            return;
        }
        const elapsed = Date.now() - w.KwickFlameStart;
        if (elapsed >= this.duration * 0.6) {
            return;
        }
        cancel(w.KwickFlameIn);
        w.KwickFlameIn = this.run(w, true, Math.max(elapsed, 1));
    }

    onWindowClosed(w) {
        if (effects.hasActiveFullScreenEffect || !KwickFlameEffect.wanted(w) || w.skipsCloseAnimation) {
            return;
        }
        if (effect.isGrabbed(w, Effect.WindowClosedGrabRole)) {
            return;
        }
        if (w.KwickFlameIn) {
            cancel(w.KwickFlameIn);
            delete w.KwickFlameIn;
        }
        w.KwickFlameOut = this.run(w, false);
    }

    onWindowDataChanged(w, role) {
        if (role == Effect.WindowAddedGrabRole && w.KwickFlameIn && effect.isGrabbed(w, role)) {
            cancel(w.KwickFlameIn);
            delete w.KwickFlameIn;
            this.release(w);
        } else if (role == Effect.WindowClosedGrabRole && w.KwickFlameOut && effect.isGrabbed(w, role)) {
            cancel(w.KwickFlameOut);
            delete w.KwickFlameOut;
            this.release(w);
        }
    }
}

new KwickFlameEffect();
