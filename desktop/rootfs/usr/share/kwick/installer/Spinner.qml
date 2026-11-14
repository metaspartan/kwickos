import QtQuick

Item {
    id: s
    property real size: 20
    property color color: Theme.sub
    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    Repeater {
        model: 12
        Rectangle {
            required property int index
            x: s.size / 2 - width / 2
            y: 0
            width: Math.max(1.5, s.size * 0.09)
            height: s.size * 0.28
            radius: width / 2
            color: s.color
            opacity: ((index - tick.step + 12) % 12) / 12 * 0.85 + 0.15
            transform: Rotation { origin.x: width / 2; origin.y: s.size / 2; angle: index * 30 }
        }
    }

    Timer {
        id: tick
        property int step: 0
        interval: 80
        repeat: true
        running: s.visible
        onTriggered: step = (step + 1) % 12
    }
}
