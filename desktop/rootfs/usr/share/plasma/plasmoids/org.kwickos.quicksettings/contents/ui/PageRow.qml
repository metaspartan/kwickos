import QtQuick
import org.kde.kirigami as Kirigami
import "file:///usr/share/kwick/qml/fluent"

MouseArea {
    id: row

    property string icon
    property string label
    property string detail
    property bool active: false
    default property alias trailing: tail.data

    x: 8
    width: parent ? parent.width - 16 : 0
    height: detail !== "" ? 52 : 40
    hoverEnabled: true

    Subtle {
        anchors.fill: parent
        hovered: row.containsMouse
        pressed: row.pressed
    }

    Rectangle {
        visible: row.active
        x: 0
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: 16
        radius: 1.5
        color: Fluent.accent
    }

    Kirigami.Icon {
        id: glyph
        x: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        height: 16
        source: row.icon
        isMask: true
        color: Fluent.text
    }

    Column {
        anchors.left: glyph.right
        anchors.leftMargin: 16
        anchors.right: tail.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter

        FluentText {
            width: parent.width
            text: row.label
        }

        FluentText {
            width: parent.width
            visible: row.detail !== ""
            text: row.detail
            level: 1
            font.pixelSize: Fluent.caption
        }
    }

    Row {
        id: tail
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
    }
}
