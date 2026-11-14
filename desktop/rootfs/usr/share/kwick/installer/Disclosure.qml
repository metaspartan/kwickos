import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: d
    property string title
    property bool open: false
    default property alias content: body.data
    spacing: 10
    Layout.fillWidth: true

    FocusScope {
        id: head
        Layout.fillWidth: true
        implicitHeight: 28
        activeFocusOnTab: true

        Rectangle {
            anchors.fill: headRow
            anchors.margins: -4
            radius: 6
            color: "transparent"
            border.width: 2.5
            border.color: Theme.focusRing
            visible: head.activeFocus
        }

        Row {
            id: headRow
            anchors.verticalCenter: parent.verticalCenter
            x: 4
            spacing: 8
            Chevron {
                anchors.verticalCenter: parent.verticalCenter
                width: 11
                height: 11
                color: Theme.sub
                rotation: d.open ? 90 : 0
                Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: d.title
                color: hover.containsMouse ? Theme.text : Theme.sub
                font.family: Theme.sans
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }

        MouseArea {
            id: hover
            anchors.fill: headRow
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: d.open = !d.open
        }

        Keys.onSpacePressed: d.open = !d.open
        Keys.onRightPressed: d.open = true
        Keys.onLeftPressed: d.open = false
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: d.open ? body.implicitHeight : 0
        clip: true
        opacity: d.open ? 1 : 0
        visible: implicitHeight > 0.5
        Behavior on implicitHeight { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200 } }

        ColumnLayout {
            id: body
            width: parent.width
            spacing: 12
        }
    }
}
