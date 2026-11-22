import QtQuick

Item {
    id: view
    required property var theme

    Row {
        anchors.centerIn: parent
        spacing: 26

        Image {
            anchors.verticalCenter: parent.verticalCenter
            width: 128
            height: 128
            sourceSize: Qt.size(256, 256)
            source: "image://icon/" + ql.iconName
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            width: Math.min(320, view.width - 210)
            Text {
                width: parent.width
                text: ql.name
                color: view.theme.label
                font.family: view.theme.sans
                font.pixelSize: 18
                font.weight: Font.DemiBold
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 3
                elide: Text.ElideRight
                renderType: Text.NativeRendering
            }
            Repeater {
                model: ql.details.split("  ·  ")
                Text {
                    required property string modelData
                    width: parent.width
                    text: modelData
                    color: view.theme.secondary
                    font.family: view.theme.sans
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    renderType: Text.NativeRendering
                }
            }
        }
    }
}
