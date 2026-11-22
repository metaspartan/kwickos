import QtQuick
import QtQuick.Controls.Basic

Item {
    id: view
    required property var theme

    FontLoader {
        id: loader
        source: ql.url
    }

    Rectangle {
        anchors.fill: parent
        color: view.theme.card
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight + 48
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
            id: col
            x: 32
            y: 26
            width: parent.width - 64
            spacing: 14

            Text {
                width: parent.width
                text: loader.status === FontLoader.Ready ? loader.name : ql.name
                color: view.theme.secondary
                font.family: view.theme.sans
                font.pixelSize: 12
                font.weight: Font.DemiBold
                renderType: Text.NativeRendering
            }
            Text {
                width: parent.width
                text: "ABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n0123456789 !?&@#%(){}"
                color: view.theme.label
                font.family: loader.name
                font.pixelSize: 30
                wrapMode: Text.Wrap
                lineHeight: 1.15
            }
            Repeater {
                model: [64, 40, 24, 16, 12]
                Text {
                    required property int modelData
                    width: col.width
                    text: "The quick brown fox jumps over the lazy dog."
                    color: view.theme.label
                    font.family: loader.name
                    font.pixelSize: modelData
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: loader.status === FontLoader.Error
        text: "This font can't be previewed"
        color: view.theme.secondary
        font.family: view.theme.sans
        font.pixelSize: 14
    }
}
