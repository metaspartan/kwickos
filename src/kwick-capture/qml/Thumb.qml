import QtQuick
import KwickCapture

Item {
    id: root
    property int edge: 0
    readonly property int pad: 22
    readonly property size fit: {
        const s = Capture.thumbSize
        const maxW = 216
        const maxH = 150
        if (s.width <= 0 || s.height <= 0)
            return Qt.size(maxW, 135)
        const k = Math.min(maxW / s.width, maxH / s.height, 1)
        return Qt.size(Math.max(56, Math.round(s.width * k)), Math.max(40, Math.round(s.height * k)))
    }
    property real swipe: 0
    property bool leaving: false

    Palette { id: pal }

    function syncMask() {
        Capture.setMask(root.Window.window, [Qt.rect(root.width - card.width - root.pad - root.edge - 12, card.y - 12, card.width + 24, card.height + 24)])
    }
    onWidthChanged: syncMask()
    onHeightChanged: syncMask()
    Component.onCompleted: syncMask()

    Item {
        id: card
        width: root.fit.width
        height: root.fit.height
        x: root.width - width - root.pad - root.edge + root.swipe
        y: root.height - height - root.pad - root.edge
        opacity: 1 - Math.max(0, root.swipe) / 220
        onYChanged: root.syncMask()
        onWidthChanged: root.syncMask()
        onHeightChanged: root.syncMask()
        Behavior on x { enabled: !area.pressed; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        Drag.active: area.dragging
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction
        Drag.mimeData: { "text/uri-list": "file://" + encodeURI(Capture.thumbPath) + "\r\n" }
        Drag.imageSource: Capture.thumbSource
        Drag.onDragFinished: dropAction => {
            area.dragging = false
            if (dropAction !== Qt.IgnoreAction)
                Capture.thumbDismiss()
        }

        Repeater {
            model: 6
            Rectangle {
                required property int index
                readonly property real spread: (index + 1) * 2.5
                x: -spread
                y: -spread + 4 + index
                width: card.width + 2 * spread
                height: card.height + 2 * spread
                radius: 7 + spread
                color: "transparent"
                border.width: 2.5
                border.color: Qt.rgba(0, 0, 0, 0.09 * (1 - index / 6))
            }
        }

        Image {
            anchors.fill: parent
            visible: !Capture.thumbVideo
            source: Capture.thumbSource
            sourceSize: Qt.size(root.fit.width * 2, root.fit.height * 2)
            smooth: true
            mipmap: true
            cache: false
        }

        Rectangle {
            anchors.fill: parent
            visible: Capture.thumbVideo
            radius: 7
            gradient: Gradient {
                GradientStop { position: 0; color: "#3a3d46" }
                GradientStop { position: 1; color: "#1c1d22" }
            }
            Column {
                anchors.centerIn: parent
                spacing: 8
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 44
                    height: 44
                    radius: 22
                    color: Qt.rgba(1, 1, 1, 0.16)
                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()
                            ctx.fillStyle = "#ffffff"
                            ctx.beginPath()
                            ctx.moveTo(17, 13)
                            ctx.lineTo(32, 22)
                            ctx.lineTo(17, 31)
                            ctx.closePath()
                            ctx.fill()
                        }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Screen Recording"
                    color: "#ffffff"
                    font.family: pal.sans
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: 7
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.22)
        }

        Rectangle {
            id: closer
            visible: area.containsMouse || closeArea.containsMouse
            x: -9
            y: -9
            width: 22
            height: 22
            radius: 11
            color: pal.dark ? "#3a3a3c" : "#ffffff"
            border.width: 1
            border.color: pal.border
            Glyph {
                anchors.centerIn: parent
                name: "close"
                width: 10
                height: 10
                tint: pal.label
            }
            MouseArea {
                id: closeArea
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                onContainsMouseChanged: Capture.thumbHold(containsMouse || area.containsMouse)
                onClicked: Capture.thumbDismiss()
            }
        }

        Rectangle {
            id: sharer
            visible: area.containsMouse || closeArea.containsMouse || shareArea.containsMouse
            x: card.width - width - 6
            y: card.height - height - 6
            width: 26
            height: 26
            radius: 13
            color: shareArea.pressed ? Qt.darker(pal.accent, 1.15) : pal.accent
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.35)
            Glyph {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1
                name: "share"
                width: 14
                height: 14
                tint: "#ffffff"
            }
            MouseArea {
                id: shareArea
                anchors.fill: parent
                anchors.margins: -3
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: Capture.thumbHold(containsMouse || area.containsMouse)
                onClicked: Capture.thumbShare()
            }
        }
    }

    MouseArea {
        id: area
        property point start
        property bool swiping: false
        property bool dragging: false
        property bool moved: false
        x: card.x - root.swipe
        y: card.y
        width: card.width
        height: card.height
        z: -1
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: Capture.thumbHold(containsMouse || closeArea.containsMouse || shareArea.containsMouse)
        onPressed: mouse => {
            start = Qt.point(mouse.x, mouse.y)
            swiping = false
            moved = false
        }
        onPositionChanged: mouse => {
            if (!pressed || dragging)
                return
            const dx = mouse.x - start.x
            const dy = mouse.y - start.y
            if (!swiping && !moved && Math.abs(dx) + Math.abs(dy) > 8) {
                moved = true
                if (dx > 0 && Math.abs(dy) < dx * 0.7)
                    swiping = true
                else
                    dragging = true
            }
            if (swiping)
                root.swipe = Math.max(-12, dx)
        }
        onReleased: {
            if (swiping) {
                swiping = false
                if (root.swipe > 60) {
                    root.swipe = 320
                    Capture.thumbDismiss()
                } else {
                    root.swipe = 0
                }
            } else if (!moved) {
                Capture.thumbOpen()
            }
        }
    }
}
