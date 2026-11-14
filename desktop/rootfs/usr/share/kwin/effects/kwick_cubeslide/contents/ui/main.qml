import QtQuick
import org.kde.kwin as KWinComponents

KWinComponents.SceneEffect {
    id: effect

    property real progress: 0
    property real fromAzimuth: 0
    property real toAzimuth: 0
    property var lastDesktop: null
    readonly property var currentDesktop: KWinComponents.Workspace.currentDesktop
    readonly property real azimuth: fromAzimuth + (toAzimuth - fromAzimuth) * ease(progress)
    readonly property real pull: Math.pow(Math.sin(Math.PI * progress), 0.8)

    readonly property var screenComponent: Qt.createComponent("ScreenView.qml")
    delegate: screenComponent

    function ease(t) {
        return t * t * t * (t * (6 * t - 15) + 10);
    }

    function begin(desktop) {
        const previous = lastDesktop;
        lastDesktop = desktop;
        const count = KWinComponents.Workspace.desktops.length;
        if (!previous || !desktop || previous === desktop || count < 2) {
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
        if (screenComponent.status === Component.Error) {
            console.log("kwick_cubeslide:", screenComponent.errorString());
        }
    }

    onCurrentDesktopChanged: begin(currentDesktop)

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
