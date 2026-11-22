import QtQuick
import QtQuick.Controls.Basic

Item {
    id: view
    required property var theme

    Item {
        id: head
        width: parent.width
        height: 96

        Image {
            id: big
            x: 22
            anchors.verticalCenter: parent.verticalCenter
            width: 64
            height: 64
            sourceSize: Qt.size(128, 128)
            source: "image://icon/" + ql.iconName
        }
        Column {
            anchors.left: big.right
            anchors.leftMargin: 16
            anchors.right: parent.right
            anchors.rightMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Text {
                width: parent.width
                text: ql.name
                color: view.theme.label
                font.family: view.theme.sans
                font.pixelSize: 17
                font.weight: Font.DemiBold
                elide: Text.ElideMiddle
                renderType: Text.NativeRendering
            }
            Text {
                width: parent.width
                text: ql.summary
                color: view.theme.secondary
                font.family: view.theme.sans
                font.pixelSize: 12
                elide: Text.ElideRight
                renderType: Text.NativeRendering
            }
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: view.theme.hairline
        }
    }

    ListView {
        id: list
        anchors.top: head.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        model: ql.entries
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: Rectangle {
            required property var modelData
            required property int index
            width: list.width
            height: 28
            color: index % 2 ? "transparent" : Qt.rgba(view.theme.ink.r, view.theme.ink.g, view.theme.ink.b, view.theme.dark ? 0.035 : 0.03)
            Image {
                id: icon
                x: 18 + Math.min(8, modelData.depth) * 16
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                sourceSize: Qt.size(32, 32)
                source: "image://icon/" + modelData.icon
            }
            Text {
                anchors.left: icon.right
                anchors.leftMargin: 8
                anchors.right: size.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.name
                color: view.theme.label
                font.family: view.theme.sans
                font.pixelSize: 12
                elide: Text.ElideMiddle
                renderType: Text.NativeRendering
            }
            Text {
                id: size
                anchors.right: parent.right
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.size
                color: view.theme.secondary
                font.family: view.theme.sans
                font.pixelSize: 11
                renderType: Text.NativeRendering
            }
        }
    }

    Text {
        anchors.centerIn: list
        visible: list.count === 0
        text: ql.kind === "folder" ? "This folder is empty" : "No entries could be read"
        color: view.theme.secondary
        font.family: view.theme.sans
        font.pixelSize: 13
    }
}
