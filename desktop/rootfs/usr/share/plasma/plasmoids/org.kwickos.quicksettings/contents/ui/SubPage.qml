import QtQuick
import QtQuick.Controls as QQC2
import "file:///usr/share/kwick/qml/fluent"

Item {
    id: page

    property var qs
    property alias title: header.title
    property alias switchable: header.switchable
    property alias on: header.on
    property string link
    property string empty
    default property alias rows: list.data
    signal back()
    signal toggled(bool value)
    signal linkClicked()

    PageHeader {
        id: header
        onBack: page.back()
        onToggled: value => page.toggled(value)
    }

    Flickable {
        y: header.height
        width: parent.width
        height: parent.height - header.height - foot.height
        contentHeight: list.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

        Column {
            id: list
            width: parent.width
            spacing: 2
        }

        FluentText {
            anchors.centerIn: parent
            visible: list.implicitHeight === 0 && page.empty !== ""
            text: page.empty
            level: 1
        }
    }

    Rectangle {
        id: foot
        anchors.bottom: parent.bottom
        width: parent.width
        height: 48
        color: Fluent.footer
        radius: Fluent.overlayRadius - 1

        Rectangle {
            width: parent.width
            height: parent.radius
            color: parent.color
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Fluent.divider
        }

        MouseArea {
            id: more
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            width: label.implicitWidth + 16
            height: 32
            hoverEnabled: true
            onClicked: page.linkClicked()

            Subtle {
                anchors.fill: parent
                hovered: more.containsMouse
                pressed: more.pressed
            }

            FluentText {
                id: label
                anchors.centerIn: parent
                text: page.link
            }
        }
    }
}
