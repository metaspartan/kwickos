import QtQuick

Item {
    id: s
    property real from: 0
    property real to: 100
    property real value: 50
    property real step: 1
    signal released(real value)
    readonly property bool pressed: area.pressed
    implicitWidth: 200
    implicitHeight: 24

    readonly property real pos: (value - from) / (to - from)

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 5
        radius: 2.5
        color: "#4a4a52"
        Rectangle {
            width: knob.x + knob.width / 2
            height: parent.height
            radius: 2.5
            color: Theme.accent
        }
    }

    Rectangle {
        id: knob
        width: 20
        height: 20
        radius: 10
        anchors.verticalCenter: parent.verticalCenter
        x: s.pos * (s.width - width)
        color: "#ffffff"
        border.width: 1
        border.color: "#30000000"
    }

    MouseArea {
        id: area
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        function set(mx) {
            var p = Math.max(0, Math.min(1, (mx - knob.width / 2) / (s.width - knob.width)))
            var v = s.from + p * (s.to - s.from)
            s.value = Math.round(v / s.step) * s.step
        }
        onPressed: (m) => set(m.x)
        onPositionChanged: (m) => { if (pressed) set(m.x) }
        onReleased: s.released(s.value)
    }
}
