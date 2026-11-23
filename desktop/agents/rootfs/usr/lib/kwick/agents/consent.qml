import QtQuick
import QtQuick.Window

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
    readonly property bool mac: layout === "macos"
    readonly property color accent: cfg.accent ? cfg.accent : (light ? "#ff9500" : "#ff9f0a")
    readonly property color ink: light ? Qt.rgba(0, 0, 0, 0.86) : Qt.rgba(1, 1, 1, 0.92)
    readonly property color sub: light ? Qt.rgba(0, 0, 0, 0.6) : Qt.rgba(1, 1, 1, 0.62)
    readonly property color faint: light ? Qt.rgba(0, 0, 0, 0.42) : Qt.rgba(1, 1, 1, 0.42)
    readonly property string sans: layout === "windows" ? "Selawik" : layout === "linux" ? "Ubuntu Sans" : "Inter"
    readonly property string mono: layout === "windows" ? "Cascadia Code" : layout === "linux" ? "Ubuntu Sans Mono" : "JetBrains Mono"
    readonly property int shadowPad: 28
    readonly property int panelRadius: layout === "windows" ? 8 : layout === "linux" ? 12 : 16
    readonly property int buttonRadius: layout === "windows" ? 4 : layout === "linux" ? 6 : 6
    property bool answered: false

    function answer(v) {
        if (answered)
            return
        answered = true
        console.info("kwick-consent:" + v)
        Qt.quit()
    }

    title: cfg.title || "KwickOS: allow an AI agent?"
    color: "transparent"
    flags: Qt.Dialog | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    width: panel.width + shadowPad * 2
    height: panel.height + shadowPad * 2
    x: (Screen.width - width) / 2
    y: Math.max(0, Math.round(Screen.height * 0.26) - shadowPad)

    onClosing: close => win.answer("deny")
    Component.onCompleted: Qt.callLater(function () {
        visible = true
        requestActivate()
        keys.forceActiveFocus()
    })

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: win.answer("deny")
        Keys.onReturnPressed: win.answer("once")
        Keys.onEnterPressed: win.answer("once")
    }

    Repeater {
        model: 12
        Rectangle {
            required property int index
            readonly property int grow: index * 2 + 1
            x: panel.x - grow
            y: panel.y - grow + 8
            width: panel.width + grow * 2
            height: panel.height + grow * 2
            radius: panel.radius + grow
            color: "transparent"
            border.width: 2
            border.color: Qt.rgba(0, 0, 0, (win.light ? 0.07 : 0.13) * (1 - index / 12))
        }
    }

    Rectangle {
        id: panel
        x: win.shadowPad
        y: win.shadowPad
        width: 440
        height: body.implicitHeight + 40
        radius: win.panelRadius
        color: win.light ? Qt.rgba(0.965, 0.965, 0.965, 0.98) : Qt.rgba(0.16, 0.16, 0.165, 0.97)
        border.width: 1
        border.color: win.light ? Qt.rgba(0, 0, 0, 0.12) : Qt.rgba(0, 0, 0, 0.5)

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: 1
            border.color: win.light ? Qt.rgba(1, 1, 1, 0.7) : Qt.rgba(1, 1, 1, 0.1)
        }

        MouseArea {
            anchors.fill: parent
            onPressed: win.startSystemMove()
        }

        Column {
            id: body
            x: 20
            y: 20
            width: parent.width - 40
            spacing: 0

            Row {
                width: parent.width
                spacing: 16

                Item {
                    width: 56
                    height: 56

                    Rectangle {
                        anchors.fill: parent
                        radius: win.mac ? 13 : win.layout === "windows" ? 8 : 12
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.lighter(win.accent, 1.12) }
                            GradientStop { position: 1; color: Qt.darker(win.accent, 1.12) }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, 0.22)
                        }
                        Text {
                            anchors.centerIn: parent
                            text: (win.cfg.agent || "A").charAt(0).toUpperCase()
                            color: "#ffffff"
                            font.family: win.sans
                            font.pixelSize: 28
                            font.weight: Font.Bold
                        }
                    }

                    Rectangle {
                        width: 24
                        height: 24
                        radius: 12
                        x: parent.width - 18
                        y: parent.height - 18
                        color: win.light ? "#f6f6f6" : "#29292a"
                        Rectangle {
                            anchors.centerIn: parent
                            width: 18
                            height: 18
                            radius: 9
                            color: win.light ? "#3a3a3c" : "#e5e5ea"
                            Canvas {
                                anchors.fill: parent
                                property color tint: win.light ? "#f6f6f6" : "#29292a"
                                onTintChanged: requestPaint()
                                onPaint: {
                                    const ctx = getContext("2d")
                                    ctx.reset()
                                    ctx.strokeStyle = String(tint)
                                    ctx.fillStyle = String(tint)
                                    ctx.lineWidth = 1.4
                                    ctx.beginPath()
                                    ctx.moveTo(9, 3.6)
                                    ctx.lineTo(13.6, 5.3)
                                    ctx.lineTo(13.6, 8.6)
                                    ctx.quadraticCurveTo(13.4, 12.6, 9, 14.6)
                                    ctx.quadraticCurveTo(4.6, 12.6, 4.4, 8.6)
                                    ctx.lineTo(4.4, 5.3)
                                    ctx.closePath()
                                    ctx.stroke()
                                }
                            }
                        }
                    }
                }

                Column {
                    width: parent.width - 72
                    spacing: 6

                    Text {
                        width: parent.width
                        text: "Allow “" + (win.cfg.agent || "an AI agent") + "” to " + (win.cfg.action || "continue") + "?"
                        color: win.ink
                        font.family: win.sans
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        wrapMode: Text.Wrap
                        lineHeight: 1.1
                    }
                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: win.cfg.detail || ""
                        color: win.sub
                        font.family: win.sans
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        lineHeight: 1.15
                        maximumLineCount: 8
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: "You can change this at any time in Settings › Agents."
                        color: win.sub
                        font.family: win.sans
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        lineHeight: 1.15
                    }
                    Text {
                        visible: !!win.cfg.capability
                        text: win.cfg.capability || ""
                        color: win.faint
                        font.family: win.mono
                        font.pixelSize: 11
                    }
                }
            }

            Item { width: 1; height: 20 }

            Row {
                anchors.right: parent.right
                spacing: 10

                ConsentButton {
                    id: alwaysButton
                    text: "Always Allow"
                    onClicked: win.answer("always")
                }
                ConsentButton {
                    id: denyButton
                    text: "Deny"
                    onClicked: win.answer("deny")
                }
                ConsentButton {
                    id: onceButton
                    text: "Allow Once"
                    primary: true
                    onClicked: win.answer("once")
                }
            }
        }
    }

    component ConsentButton: Rectangle {
        id: b
        property string text
        property bool primary: false
        signal clicked()
        width: Math.max(86, label.implicitWidth + 28)
        height: win.mac ? 24 : 30
        radius: win.buttonRadius
        color: primary ? (area.pressed ? Qt.darker(win.accent, 1.15) : win.accent)
                       : (win.light ? (area.pressed ? "#e3e3e3" : "#ffffff") : (area.pressed ? Qt.rgba(1, 1, 1, 0.34) : Qt.rgba(1, 1, 1, 0.24)))
        border.width: primary ? 0 : 1
        border.color: win.light ? Qt.rgba(0, 0, 0, 0.13) : Qt.rgba(1, 1, 1, 0.06)

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 1
            anchors.bottomMargin: -1
            z: -1
            radius: parent.radius
            color: Qt.rgba(0, 0, 0, win.light ? 0.08 : 0.3)
        }
        Rectangle {
            visible: b.primary
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.14) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
            }
        }
        Text {
            id: label
            anchors.centerIn: parent
            text: b.text
            color: b.primary ? "#ffffff" : win.ink
            font.family: win.sans
            font.pixelSize: 13
            font.weight: Font.Medium
        }
        MouseArea {
            id: area
            anchors.fill: parent
            onClicked: b.clicked()
        }
    }
}
