import QtQuick
import KwickCapture

Item {
    id: box
    property real radius: pal.radius
    property color fill: pal.panel
    property int rings: 6
    property real strength: 1
    default property alias content: inner.data

    Palette { id: pal }

    Repeater {
        model: box.rings
        Rectangle {
            required property int index
            readonly property real spread: (index + 1) * 3
            x: -spread
            y: -spread + 5 + index
            width: box.width + 2 * spread
            height: box.height + 2 * spread
            radius: box.radius + spread
            color: "transparent"
            border.width: 3
            border.color: Qt.rgba(0, 0, 0, (pal.dark ? 0.09 : 0.045) * box.strength * (1 - index / box.rings))
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: box.radius
        color: box.fill
        border.width: 1
        border.color: pal.border
    }

    Item {
        id: inner
        anchors.fill: parent
    }
}
