"use strict";

const skipClasses = [
    "ksmserver ksmserver",
    "ksmserver-logout-greeter ksmserver-logout-greeter",
    "ksplashqml ksplashqml",
    "spectacle spectacle",
    "spectacle org.kde.spectacle"
];

class @CLS@Effect {
    constructor() {
        effect.configChanged.connect(this.loadConfig.bind(this));
        effect.animationEnded.connect(this.release.bind(this));
        effects.windowAdded.connect(this.onWindowAdded.bind(this));
        effects.windowClosed.connect(this.onWindowClosed.bind(this));
        effects.windowDataChanged.connect(this.onWindowDataChanged.bind(this));
        this.shader = effect.addFragmentShader(Effect.MapTexture, "@SHADER@.frag");
        this.loadConfig();
    }

    loadConfig() {
        this.duration = animationTime(effect.readConfig("Duration", @DUR@));
        this.opening = effect.readConfig("Opening", true);
        this.seeded = @SEEDED@;
@EXTRA@
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
        if (!this.opening || effects.hasActiveFullScreenEffect || !@CLS@Effect.wanted(w)) {
            return;
        }
        if (effect.isGrabbed(w, Effect.WindowAddedGrabRole)) {
            return;
        }
        w.@CLS@In = this.run(w, true);
    }

    onWindowClosed(w) {
        if (effects.hasActiveFullScreenEffect || !@CLS@Effect.wanted(w) || w.skipsCloseAnimation) {
            return;
        }
        if (effect.isGrabbed(w, Effect.WindowClosedGrabRole)) {
            return;
        }
        if (w.@CLS@In) {
            cancel(w.@CLS@In);
            delete w.@CLS@In;
        }
        w.@CLS@Out = this.run(w, false);
    }

    onWindowDataChanged(w, role) {
        if (role == Effect.WindowAddedGrabRole && w.@CLS@In && effect.isGrabbed(w, role)) {
            cancel(w.@CLS@In);
            delete w.@CLS@In;
            this.release(w);
        } else if (role == Effect.WindowClosedGrabRole && w.@CLS@Out && effect.isGrabbed(w, role)) {
            cancel(w.@CLS@Out);
            delete w.@CLS@Out;
            this.release(w);
        }
    }
}

new @CLS@Effect();
