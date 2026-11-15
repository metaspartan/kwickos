import QtQuick
import org.kde.kwin as KWinComponents

KWinComponents.SceneEffect {
    id: effect

    property real progress: 0
    property real fromAzimuth: 0
    property real toAzimuth: 0
    property var lastDesktop: null
    readonly property var currentDesktop: KWinComponents.Workspace.currentDesktop
    readonly property real scrub: configuration.Scrub === undefined ? -1 : configuration.Scrub
    readonly property real turn: spring(Math.max(0, Math.min(1, (progress - 0.08) / 0.92)))
    readonly property real azimuth: fromAzimuth + (toAzimuth - fromAzimuth) * turn
    readonly property real pull: smoothstep(0, 0.3, progress) * (1 - smoothstep(0.66, 1, progress))
    readonly property real angularSpeed: Math.abs(toAzimuth - fromAzimuth) * Math.abs(springRate(Math.max(0, Math.min(1, (progress - 0.08) / 0.92)))) / 0.92 / Math.max(300, configuration.Duration) * 16.7
    readonly property real blur: Math.min(1, angularSpeed / 3.2)
    readonly property real trail: -Math.sign(toAzimuth - fromAzimuth) * Math.min(3.5, angularSpeed * 0.9)

    readonly property var screenComponent: Qt.createComponent("ScreenView.qml")
    delegate: screenComponent

    function smoothstep(a, b, x) {
        const t = Math.max(0, Math.min(1, (x - a) / (b - a)));
        return t * t * (3 - 2 * t);
    }

    function spring(t) {
        if (t <= 0) {
            return 0;
        }
        if (t >= 1) {
            return 1;
        }
        const a = 4.6;
        const w = 5.2;
        const f = 1 - Math.exp(-a * t) * (Math.cos(w * t) + (a / w) * Math.sin(w * t));
        const f1 = 1 - Math.exp(-a) * (Math.cos(w) + (a / w) * Math.sin(w));
        return f + (1 - f1) * t * t * t;
    }

    function springRate(t) {
        const h = 0.004;
        return (spring(Math.min(1, t + h)) - spring(Math.max(0, t - h))) / (Math.min(1, t + h) - Math.max(0, t - h));
    }

    onScrubChanged: {
        if (scrub < 0) {
            if (!run.running) {
                progress = 0;
                visible = false;
            }
            return;
        }
        run.stop();
        fromAzimuth = configuration.ScrubFrom;
        toAzimuth = configuration.ScrubTo;
        progress = scrub;
        visible = true;
    }

    function begin(desktop) {
        const previous = lastDesktop;
        lastDesktop = desktop;
        const count = KWinComponents.Workspace.desktops.length;
        if (scrub >= 0 || !previous || !desktop || previous === desktop || count < 2) {
            return;
        }
        const tick = 360 / count;
        let delta = (desktop.x11DesktopNumber - previous.x11DesktopNumber) * tick;
        while (delta > 180) {
            delta -= 360;
        }
        while (delta <= -180) {
            delta += 360;
        }
        fromAzimuth = (previous.x11DesktopNumber - 1) * tick;
        toAzimuth = fromAzimuth + delta;
        progress = 0;
        visible = true;
        run.restart();
    }

    Component.onCompleted: {
        lastDesktop = currentDesktop;
        warmShow.start();
        if (screenComponent.status === Component.Error) {
            console.log("kwick_cubeslide:", screenComponent.errorString());
        }
    }

    onCurrentDesktopChanged: begin(currentDesktop)

    Timer {
        id: warmShow
        interval: 900
        onTriggered: {
            if (!effect.visible && effect.progress === 0) {
                effect.visible = true;
                warmHide.start();
            }
        }
    }

    Timer {
        id: warmHide
        interval: 500
        onTriggered: {
            if (effect.progress === 0 && !run.running) {
                effect.visible = false;
            }
        }
    }

    NumberAnimation {
        id: run
        target: effect
        property: "progress"
        from: 0
        to: 1
        duration: Math.max(120, effect.configuration.Duration)
        onFinished: effect.visible = false
    }
}
