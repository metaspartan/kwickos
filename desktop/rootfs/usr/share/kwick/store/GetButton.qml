import QtQuick
import QtQuick.Controls.Basic

Item {
    id: b
    property var app
    property bool big: false
    property bool updateMode: false
    readonly property var op: app ? Store.ops[app.key] || null : null
    readonly property bool installed: Store.isInstalled(app)
    readonly property bool unavailable: !!app && app.available === false && !installed
    readonly property bool canOpen: !!app && installed && app.src !== "agent" && !app.system_only
    readonly property real progress: op && op.progress >= 0 ? op.progress / 100 : -1
    readonly property string label: {
        if (!app) return ""
        if (unavailable) return "Unavailable"
        if (updateMode) return app.needsReview ? "Review" : "Update"
        if (installed) return canOpen ? "Open" : "Installed"
        if (Look.win) return big ? "Install" : "Get"
        if (Look.gnu) return "Install"
        return "Get"
    }
    readonly property bool filled: Look.mac ? (big && !installed) : Look.win ? !installed || updateMode : !installed || updateMode
    implicitWidth: op ? (Look.mac ? (big ? 80 : 30) : Look.win ? (big ? 200 : 96) : (big ? 150 : 100)) : Math.max(Look.mac ? (big ? 80 : 68) : Look.win ? (big ? 200 : 72) : (big ? 112 : 84), lbl.implicitWidth + 32)
    implicitHeight: Look.mac ? (big ? 30 : 26) : Look.win ? (big ? 34 : 30) : (big ? 36 : 32)

    Rectangle {
        id: face
        visible: !b.op
        anchors.fill: parent
        radius: Look.mac ? height / 2 : Look.controlRadius
        opacity: b.unavailable ? 0.5 : 1
        color: b.filled ? (Look.mac ? (area.pressed ? Qt.darker(Look.accent, 1.15) : Look.accent) : area.pressed ? Qt.darker(Look.getBg, 1.1) : area.containsMouse ? Look.getBgHover : Look.getBg)
                        : Look.mac ? (area.pressed ? Look.pressed : area.containsMouse ? Look.getBgHover : Look.getBg) : (area.pressed ? Look.pressed : area.containsMouse ? Qt.tint(Look.openBg, Look.hover) : Look.openBg)
        border.width: Look.win && !b.filled ? 1 : 0
        border.color: Look.fieldStroke
        Text {
            id: lbl
            anchors.centerIn: parent
            text: b.label
            color: b.filled ? (Look.mac ? "#ffffff" : Look.getText) : Look.mac ? Look.accentText : Look.text
            font.family: Look.sans
            font.pixelSize: Look.mac ? (b.big ? 14 : 13) : 14
            font.weight: Look.mac ? Font.Bold : Look.win ? Font.DemiBold : Font.Bold
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: b.unavailable || (b.installed && !b.canOpen && !b.updateMode) ? Qt.ArrowCursor : Qt.PointingHandCursor
            onClicked: {
                if (!b.app || b.unavailable) return
                if (b.updateMode && b.app.needsReview) b.ApplicationWindow.window.requestInstall(b.app)
                else if (b.updateMode) Store.update(b.app)
                else if (b.installed) { if (b.canOpen) Store.launch(b.app) }
                else b.ApplicationWindow.window.requestInstall(b.app)
            }
        }
    }

    Item {
        visible: !!b.op && Look.mac
        anchors.fill: parent
        Item {
            id: ring
            width: b.big ? 28 : 26
            height: width
            anchors.centerIn: parent
            Canvas {
                id: cv
                anchors.fill: parent
                property real p: b.progress
                property color c: Look.accent
                property color t: Look.line
                onPChanged: requestPaint()
                onCChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.lineWidth = 2.4
                    ctx.strokeStyle = t
                    ctx.beginPath()
                    ctx.arc(width / 2, height / 2, width / 2 - 2, 0, Math.PI * 2)
                    ctx.stroke()
                    if (p >= 0) {
                        ctx.strokeStyle = c
                        ctx.lineCap = "round"
                        ctx.beginPath()
                        ctx.arc(width / 2, height / 2, width / 2 - 2, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0.03, p))
                        ctx.stroke()
                    }
                }
            }
            Rectangle {
                visible: b.progress < 0
                anchors.fill: parent
                color: "transparent"
                radius: width / 2
                Rectangle {
                    width: 2.4
                    height: parent.height / 2 - 2
                    color: Look.accent
                    radius: 1.2
                    x: parent.width / 2 - 1.2
                    y: 2
                    transformOrigin: Item.Bottom
                    RotationAnimation on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: b.op && b.progress < 0 }
                }
            }
            Rectangle {
                width: 8
                height: 8
                radius: 1.5
                anchors.centerIn: parent
                color: Look.accent
                visible: b.progress >= 0
            }
        }
    }

    Rectangle {
        visible: !!b.op && !Look.mac
        anchors.fill: parent
        radius: Look.controlRadius
        color: Look.win ? (Look.light ? "#ffffff" : "#2d2d2d") : Look.openBg
        border.width: Look.win ? 1 : 0
        border.color: Look.fieldStroke
        clip: true
        Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            height: Look.win ? 3 : parent.height
            width: b.progress >= 0 ? parent.width * Math.max(0.04, b.progress) : parent.width * 0.3
            radius: Look.win ? 1.5 : Look.controlRadius
            color: Look.win ? Look.accent : Qt.rgba(Look.accent.r, Look.accent.g, Look.accent.b, 0.35)
            Behavior on width { enabled: b.progress >= 0; NumberAnimation { duration: 300 } }
            SequentialAnimation on x {
                running: b.op && b.progress < 0
                loops: Animation.Infinite
                NumberAnimation { from: 0; to: b.width * 0.7; duration: 900; easing.type: Easing.InOutQuad }
                NumberAnimation { from: b.width * 0.7; to: 0; duration: 900; easing.type: Easing.InOutQuad }
            }
        }
        Text {
            anchors.centerIn: parent
            text: b.op ? (b.op.queued ? "Waiting…" : b.op.auth ? "Authorizing…" : b.progress >= 0 ? Math.round(b.progress * 100) + "%" : b.op.kind === "remove" ? "Removing…" : b.op.kind === "install" ? "Installing…" : "Updating…") : ""
            color: Look.text
            font.family: Look.sans
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
    }
}
