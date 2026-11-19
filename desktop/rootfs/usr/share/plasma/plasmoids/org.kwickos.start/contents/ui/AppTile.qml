import QtQuick
import org.kde.kirigami as Kirigami
import "file:///usr/share/kwick/qml/fluent"

MouseArea {
    id: tile

    property string label
    property var iconSource
    signal launch()
    signal menu(real x, real y)

    width: 96
    height: 84
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton)
            tile.menu(mouse.x, mouse.y)
        else
            tile.launch()
    }

    Subtle {
        anchors.fill: parent
        anchors.margins: 2
        hovered: tile.containsMouse
        pressed: tile.pressed
        border.width: tile.containsMouse ? 1 : 0
        border.color: Fluent.controlStroke
    }

    Kirigami.Icon {
        id: glyph
        y: 14
        anchors.horizontalCenter: parent.horizontalCenter
        width: 32
        height: 32
        source: tile.iconSource
        scale: tile.pressed ? 0.9 : 1
        Behavior on scale { NumberAnimation { duration: 100 } }
    }

    FluentText {
        y: 52
        x: 6
        width: parent.width - 12
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Fluent.caption
        lineHeight: 16
        lineHeightMode: Text.FixedHeight
        wrapMode: Text.Wrap
        maximumLineCount: 2
        text: tile.label
    }
}
