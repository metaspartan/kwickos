import QtQuick

Item {
    id: preview
    property Look pal
    property var items: []
    property bool text: false
    implicitWidth: 56
    implicitHeight: 56

    readonly property var first: items.length > 0 ? items[0] : null
    readonly property string kind: text ? "text" : first ? first.kind : "waves"

    Repeater {
        model: Math.min(2, Math.max(0, preview.items.length - 1))
        Rectangle {
            required property int index
            width: 44
            height: 50
            x: 6 + (index + 1) * 4
            y: 3 - (index + 1) * 2
            radius: 6
            rotation: (index + 1) * 5
            color: preview.pal.dark ? "#3a3a3c" : "#ffffff"
            border.width: 1
            border.color: preview.pal.border
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: thumb.status === Image.Ready ? Math.max(28, thumb.paintedWidth) : 46
        height: thumb.status === Image.Ready ? Math.max(28, thumb.paintedHeight) : 52
        radius: 6
        color: thumb.status === Image.Ready ? "transparent" : preview.kind === "waves" ? preview.pal.accent : preview.pal.dark ? "#3a3a3c" : "#ffffff"
        border.width: preview.kind === "waves" ? 0 : 1
        border.color: preview.pal.border

        Image {
            id: thumb
            anchors.centerIn: parent
            width: 56
            height: 56
            fillMode: Image.PreserveAspectFit
            source: !preview.text && preview.first && preview.first.thumb ? preview.first.thumb : ""
            sourceSize: Qt.size(112, 112)
            asynchronous: true
            smooth: true
        }

        Glyph {
            anchors.centerIn: parent
            visible: thumb.status !== Image.Ready
            name: preview.kind
            width: 26
            height: 26
            tint: preview.kind === "waves" ? "#ffffff" : preview.kind === "folder" ? "#3d8ff7" : preview.kind === "image" ? "#30b0c7" : preview.kind === "film" ? "#bf5af2" : preview.kind === "music" ? "#ff375f" : preview.pal.secondary
        }
    }
}
