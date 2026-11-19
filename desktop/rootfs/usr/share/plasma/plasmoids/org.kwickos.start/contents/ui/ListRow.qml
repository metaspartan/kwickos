import QtQuick
import org.kde.kirigami as Kirigami
import "file:///usr/share/kwick/qml/fluent"

MouseArea {
    id: row

    property string label
    property string detail
    property var iconSource
    property int iconSize: 24
    property bool selected: false
    signal launch()
    signal menu(real x, real y)

    height: detail !== "" ? 48 : 40
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton)
            row.menu(mouse.x, mouse.y)
        else
            row.launch()
    }

    Subtle {
        anchors.fill: parent
        hovered: row.containsMouse
        pressed: row.pressed
        active: row.selected
    }

    Kirigami.Icon {
        id: glyph
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        width: row.iconSize
        height: row.iconSize
        source: row.iconSource
    }

    Column {
        anchors.left: glyph.right
        anchors.leftMargin: 12
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter

        FluentText {
            width: parent.width
            text: row.label
            font.pixelSize: Fluent.caption
        }

        FluentText {
            width: parent.width
            visible: row.detail !== ""
            text: row.detail
            level: 1
            font.pixelSize: Fluent.caption
        }
    }
}
