import QtQuick
import org.kde.kirigami as Kirigami
import "file:///usr/share/kwick/qml/fluent"

Item {
    id: tile

    property string label
    property string icon
    property bool on: false
    property bool split: false
    property bool available: true
    signal toggled()
    signal expand()

    width: 96
    height: 76

    Rectangle {
        id: plate
        width: parent.width
        height: 48
        radius: Fluent.radius
        opacity: tile.available ? 1 : 0.5
        color: tile.on ? (main.pressed || more.pressed ? Fluent.accentPressed : main.containsMouse || more.containsMouse ? Fluent.accentHover : Fluent.accent)
                       : (main.pressed || more.pressed ? Fluent.controlPressed : main.containsMouse || more.containsMouse ? Fluent.controlHover : Fluent.control)
        border.width: tile.on ? 0 : 1
        border.color: Fluent.controlStroke

        MouseArea {
            id: main
            width: tile.split ? parent.width - 36 : parent.width
            height: parent.height
            enabled: tile.available
            hoverEnabled: true
            onClicked: tile.toggled()

            Kirigami.Icon {
                anchors.centerIn: parent
                width: 16
                height: 16
                source: tile.icon
                isMask: true
                color: tile.on ? Fluent.onAccent : Fluent.text
            }
        }

        Rectangle {
            visible: tile.split
            x: main.width
            y: 12
            width: 1
            height: parent.height - 24
            color: tile.on ? Qt.rgba(0, 0, 0, 0.2) : Fluent.divider
        }

        MouseArea {
            id: more
            visible: tile.split
            x: main.width + 1
            width: parent.width - x
            height: parent.height
            enabled: tile.available
            hoverEnabled: true
            onClicked: tile.expand()

            Kirigami.Icon {
                anchors.centerIn: parent
                width: 12
                height: 12
                source: "arrow-right"
                isMask: true
                color: tile.on ? Fluent.onAccent : Fluent.text
            }
        }
    }

    FluentText {
        anchors.top: plate.bottom
        anchors.topMargin: 8
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Fluent.caption
        text: tile.label
        opacity: tile.available ? 1 : 0.5
    }
}
