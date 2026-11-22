import QtQuick

Item {
    id: avatar
    property string type: "desktop"
    property int size: 64
    property Look pal
    property real progress: 0
    property bool busy: false
    property bool waiting: false
    property string badge: ""

    implicitWidth: size + 12
    implicitHeight: size + 12

    readonly property var colors: pal.avatarColors(type)

    Rectangle {
        id: disc
        anchors.centerIn: parent
        width: avatar.size
        height: avatar.size
        radius: width / 2
        gradient: Gradient {
            GradientStop { position: 0; color: avatar.colors[0] }
            GradientStop { position: 1; color: avatar.colors[1] }
        }
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.12)

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.22)
        }

        Glyph {
            anchors.centerIn: parent
            name: avatar.pal.deviceIcon(avatar.type)
            width: Math.round(avatar.size * 0.46)
            height: width
            tint: "#ffffff"
        }
    }

    Canvas {
        id: ring
        anchors.fill: parent
        visible: avatar.busy
        property real value: avatar.progress
        property real spin: 0
        property color ink: avatar.pal.accent
        property color track: avatar.pal.hairline
        onValueChanged: requestPaint()
        onSpinChanged: requestPaint()
        onInkChanged: requestPaint()
        onVisibleChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const r = width / 2 - 2.5
            ctx.lineWidth = 3
            ctx.lineCap = "round"
            ctx.strokeStyle = String(track)
            ctx.beginPath()
            ctx.arc(width / 2, height / 2, r, 0, Math.PI * 2)
            ctx.stroke()
            ctx.strokeStyle = String(ink)
            ctx.beginPath()
            if (avatar.waiting) {
                const start = spin * Math.PI * 2 - Math.PI / 2
                ctx.arc(width / 2, height / 2, r, start, start + Math.PI * 0.55)
            } else {
                ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.max(0.02, Math.min(1, value)))
            }
            ctx.stroke()
        }
        NumberAnimation on spin {
            running: avatar.busy && avatar.waiting
            from: 0
            to: 1
            duration: 1100
            loops: Animation.Infinite
        }
    }

    Rectangle {
        visible: avatar.badge !== ""
        width: Math.round(avatar.size * 0.36)
        height: width
        radius: width / 2
        x: disc.x + disc.width - width * 0.78
        y: disc.y + disc.height - height * 0.78
        color: avatar.badge === "done" ? avatar.pal.good : avatar.pal.bad
        border.width: 2
        border.color: avatar.pal.window
        Glyph {
            anchors.centerIn: parent
            name: avatar.badge === "done" ? "check" : "close"
            width: Math.round(parent.width * 0.56)
            height: width
            tint: "#ffffff"
        }
    }
}
