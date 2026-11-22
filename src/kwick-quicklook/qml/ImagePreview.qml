import QtQuick

Item {
    id: view
    required property var theme
    property real zoom: 1

    clip: true

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: Math.max(width, shown.paintedWidth * view.zoom)
        contentHeight: Math.max(height, shown.paintedHeight * view.zoom)
        interactive: view.zoom > 1
        boundsBehavior: Flickable.StopAtBounds

        AnimatedImage {
            id: shown
            width: flick.width * view.zoom
            height: flick.height * view.zoom
            source: ql.url
            fillMode: Image.PreserveAspectFit
            autoTransform: true
            asynchronous: true
            cache: false
            smooth: true
            mipmap: true
            playing: ql.kind === "animation"
            sourceSize: ql.kind === "animation" ? undefined : Qt.size(Math.min(ql.imageSize.width > 0 ? ql.imageSize.width : 4096, 4096), Math.min(ql.imageSize.height > 0 ? ql.imageSize.height : 4096, 4096))
        }
    }

    Text {
        anchors.centerIn: parent
        visible: shown.status === Image.Error
        text: "This image can't be previewed"
        color: view.theme.secondary
        font.family: view.theme.sans
        font.pixelSize: 14
    }

    WheelHandler {
        acceptedModifiers: Qt.ControlModifier
        onWheel: event => view.zoom = Math.max(1, Math.min(8, view.zoom * (event.angleDelta.y > 0 ? 1.15 : 1 / 1.15)))
    }

    PinchHandler {
        target: null
        onScaleChanged: delta => view.zoom = Math.max(1, Math.min(8, view.zoom * delta))
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onDoubleTapped: view.zoom = view.zoom > 1 ? 1 : 2
    }

    Connections {
        target: ql
        function onCurrentChanged() {
            view.zoom = 1
        }
    }
}
