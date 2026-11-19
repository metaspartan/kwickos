import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "file:///usr/share/kwick/qml/fluent"

Item {
    id: header

    property string title
    property string action
    property string actionIcon: "arrow-right"
    signal triggered()

    implicitHeight: 32

    FluentText {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: header.title
        strong: true
    }

    MouseArea {
        id: link
        visible: header.action !== ""
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: row.implicitWidth + 16
        height: 24
        hoverEnabled: true
        onClicked: header.triggered()

        Rectangle {
            anchors.fill: parent
            radius: Fluent.radius
            color: link.pressed ? Fluent.controlPressed : link.containsMouse ? Fluent.controlHover : Fluent.control
            border.width: 1
            border.color: Fluent.controlStroke
        }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 6

            FluentText {
                text: header.action
                font.pixelSize: Fluent.caption
            }

            Kirigami.Icon {
                Layout.preferredWidth: 12
                Layout.preferredHeight: 12
                source: header.actionIcon
                isMask: true
                color: Fluent.text
            }
        }
    }
}
