import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell

Window {
    id: win

    readonly property var cfg: {
        const a = Qt.application.arguments
        for (let i = a.length - 1; i >= 0; i--) {
            if (a[i].charAt(0) === "{") {
                try { return JSON.parse(a[i]) } catch (e) {}
            }
        }
        return {}
    }
    readonly property bool light: cfg.appearance === "light"
    readonly property string layout: cfg.layout || "macos"
    readonly property color accent: cfg.accent ? cfg.accent : palette.highlight
    readonly property color ink: light ? Qt.rgba(0, 0, 0, 0.86) : Qt.rgba(1, 1, 1, 0.92)
    readonly property color sub: light ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(1, 1, 1, 0.6)
    readonly property color red: light ? "#d70015" : "#ff453a"
    readonly property string sans: layout === "windows" ? "Selawik" : layout === "linux" ? "Ubuntu Sans" : "Inter"
    readonly property int shadowPad: 18
    readonly property int topMargin: layout === "windows" ? 10 : 42

    function stop() {
        console.info("stop")
        stopButton.enabled = false
        Qt.quit()
    }

    color: "transparent"
    width: pill.width + shadowPad * 2
    height: pill.height + shadowPad * 2
    flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus
    title: "KwickOS agent control"

    LayerShell.Window.scope: "kwick-agents-indicator"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop
    LayerShell.Window.margins.top: topMargin - shadowPad
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    Component.onCompleted: visible = true

    Repeater {
        model: 9
        Rectangle {
            required property int index
            readonly property int grow: (index + 1) * 2
            x: pill.x - grow
            y: pill.y - grow + 4
            width: pill.width + grow * 2
            height: pill.height + grow * 2
            radius: pill.radius + grow
            color: "transparent"
            border.width: 2
            border.color: Qt.rgba(0, 0, 0, (win.light ? 0.05 : 0.09) * (1 - index / 9))
        }
    }

    Rectangle {
        id: pill
        x: win.shadowPad
        y: win.shadowPad
        width: row.implicitWidth + 12
        height: 40
        radius: win.layout === "windows" ? 8 : win.layout === "linux" ? 12 : height / 2
        color: win.light ? Qt.rgba(0.98, 0.98, 0.98, 0.94) : Qt.rgba(0.13, 0.13, 0.14, 0.92)
        border.width: 1
        border.color: win.light ? Qt.rgba(0, 0, 0, 0.1) : Qt.rgba(1, 1, 1, 0.12)

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: 1
            border.color: win.light ? Qt.rgba(1, 1, 1, 0.9) : Qt.rgba(1, 1, 1, 0.04)
        }

        Row {
            id: row
            anchors.verticalCenter: parent.verticalCenter
            x: 6
            spacing: 10

            Item {
                width: 28
                height: 28
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.fill: parent
                    radius: win.layout === "windows" ? 6 : width / 2
                    color: Qt.rgba(win.accent.r, win.accent.g, win.accent.b, win.light ? 0.16 : 0.24)
                    Text {
                        anchors.centerIn: parent
                        text: (win.cfg.agent || "A").charAt(0).toUpperCase()
                        color: win.light ? Qt.darker(win.accent, 1.25) : Qt.lighter(win.accent, 1.35)
                        font.family: win.sans
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                }

                Item {
                    width: 10
                    height: 10
                    x: parent.width - 8
                    y: -1

                    Rectangle {
                        id: halo
                        anchors.centerIn: parent
                        width: 10
                        height: 10
                        radius: 5
                        color: win.accent
                        opacity: 0.5
                        SequentialAnimation on scale {
                            loops: Animation.Infinite
                            NumberAnimation { from: 1; to: 2.2; duration: 1400; easing.type: Easing.OutCubic }
                            PauseAnimation { duration: 200 }
                        }
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            NumberAnimation { from: 0.55; to: 0; duration: 1400; easing.type: Easing.OutCubic }
                            PauseAnimation { duration: 200 }
                        }
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 8
                        height: 8
                        radius: 4
                        color: win.accent
                        border.width: 1.5
                        border.color: win.light ? "#fbfbfb" : "#232325"
                    }
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Text {
                    text: (win.cfg.agent || "An AI agent") + " is using this computer"
                    color: win.ink
                    font.family: win.sans
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text {
                    text: "Mouse, keyboard and windows" + (win.cfg.until ? " until " + win.cfg.until : "") + (win.cfg.hotkey ? "  ·  " + win.cfg.hotkey + " stops" : "")
                    color: win.sub
                    font.family: win.sans
                    font.pixelSize: 11
                }
            }

            Item { width: 2; height: 1 }

            Rectangle {
                id: stopButton
                anchors.verticalCenter: parent.verticalCenter
                width: stopLabel.implicitWidth + 30
                height: 28
                radius: win.layout === "windows" ? 5 : win.layout === "linux" ? 8 : height / 2
                color: Qt.rgba(win.red.r, win.red.g, win.red.b, area.pressed ? 0.34 : area.containsMouse ? 0.24 : (win.light ? 0.12 : 0.18))
                border.width: 1
                border.color: Qt.rgba(win.red.r, win.red.g, win.red.b, area.containsMouse ? 0.45 : 0.28)
                scale: area.pressed ? 0.96 : 1
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on scale { NumberAnimation { duration: 90 } }

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 8
                        radius: 2
                        color: win.red
                    }
                    Text {
                        id: stopLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Stop"
                        color: win.red
                        font.family: win.sans
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.stop()
                }
            }
        }
    }
}
