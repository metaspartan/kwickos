import QtQuick
import KwickCapture

Item {
    id: root
    property int screenIndex: 0
    property string purpose: "select"
    property string source
    property real pixelRatio: 1
    property var windows: []
    property bool dragging: false
    property point anchor: Qt.point(0, 0)
    property point pointer: Qt.point(-1, -1)
    property bool hasPointer: false
    property int hovered: -1
    readonly property bool windowMode: purpose === "window" && windows.length > 0
    readonly property bool colorMode: purpose === "color"
    readonly property rect selection: Qt.rect(Math.min(anchor.x, pointer.x), Math.min(anchor.y, pointer.y), Math.abs(pointer.x - anchor.x), Math.abs(pointer.y - anchor.y))
    readonly property string hint: purpose === "text" ? "Drag over the text you want to copy" : purpose === "record" ? "Drag to choose the area to record" : purpose === "color" ? "Click to pick a color" : windowMode ? "Click a window to capture it" : "Drag to capture an area"

    Palette { id: pal }

    focus: true
    Component.onCompleted: forceActiveFocus()

    function windowAt(x, y) {
        for (let i = 0; i < windows.length; ++i) {
            const w = windows[i]
            if (x >= w.x && x < w.x + w.w && y >= w.y && y < w.y + w.h)
                return i
        }
        return -1
    }

    function finishWindow(index) {
        if (index < 0)
            return
        const w = windows[index]
        const x = Math.max(0, w.x)
        const y = Math.max(0, w.y)
        Capture.overlayDone(screenIndex, x, y, Math.min(width, w.x + w.w) - x, Math.min(height, w.y + w.h) - y)
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            Capture.overlayCancel()
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) && windowMode) {
            finishWindow(hovered >= 0 ? hovered : 0)
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && colorMode && hasPointer) {
            Capture.overlayPoint(screenIndex, pointer.x, pointer.y)
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && purpose !== "color") {
            Capture.overlayDone(screenIndex, 0, 0, width, height)
        } else {
            return
        }
        event.accepted = true
    }

    Image {
        id: frozen
        anchors.fill: parent
        source: root.source
        smooth: true
        cache: false
        asynchronous: false
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.08)
        visible: !root.dragging && !root.windowMode && !root.colorMode
    }

    Item {
        anchors.fill: parent
        visible: root.dragging
        readonly property rect s: root.selection
        Rectangle {
            readonly property real spread: Math.max(root.width, root.height) * 2
            x: parent.s.x - spread
            y: parent.s.y - spread
            width: parent.s.width + spread * 2
            height: parent.s.height + spread * 2
            color: "transparent"
            border.width: spread
            border.color: Qt.rgba(0, 0, 0, 0.36)
        }
        Rectangle {
            x: parent.s.x - 1
            y: parent.s.y - 1
            width: parent.s.width + 2
            height: parent.s.height + 2
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.35)
        }
        Rectangle {
            x: parent.s.x
            y: parent.s.y
            width: parent.s.width
            height: parent.s.height
            color: "transparent"
            border.width: 1
            border.color: "#ffffff"
        }
    }

    Repeater {
        model: root.windowMode ? root.windows : []
        Rectangle {
            required property var modelData
            required property int index
            visible: root.hovered === index
            x: modelData.x
            y: modelData.y
            width: modelData.w
            height: modelData.h
            color: Qt.rgba(pal.accent.r, pal.accent.g, pal.accent.b, 0.22)
            border.width: 2
            border.color: pal.accent
            radius: 6
            Rectangle {
                anchors.centerIn: parent
                visible: titleText.text !== ""
                width: titleText.implicitWidth + 24
                height: 30
                radius: 15
                color: Qt.rgba(0, 0, 0, 0.62)
                Text {
                    id: titleText
                    anchors.centerIn: parent
                    text: parent.parent.modelData.title || ""
                    color: "#ffffff"
                    font.family: pal.sans
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
            }
        }
    }

    Rectangle {
        id: sizeLabel
        visible: root.hasPointer && !root.windowMode && !root.colorMode
        readonly property string value: root.dragging ? Math.round(root.selection.width * root.pixelRatio) + " × " + Math.round(root.selection.height * root.pixelRatio) : Math.round(root.pointer.x * root.pixelRatio) + ", " + Math.round(root.pointer.y * root.pixelRatio)
        width: sizeText.implicitWidth + 14
        height: 22
        radius: 6
        color: Qt.rgba(0, 0, 0, 0.66)
        x: Math.min(root.width - width - 4, root.pointer.x + 14)
        y: Math.min(root.height - height - 4, root.pointer.y + 16)
        Text {
            id: sizeText
            anchors.centerIn: parent
            text: sizeLabel.value
            color: "#ffffff"
            font.family: pal.sans
            font.pixelSize: 12
            font.features: { "tnum": 1 }
        }
    }

    Item {
        id: loupe
        visible: root.colorMode && root.hasPointer
        readonly property int cells: 11
        readonly property int cell: 11
        readonly property int side: cells * cell
        readonly property color sample: visible ? Capture.colorAt(root.screenIndex, root.pointer.x, root.pointer.y) : "transparent"
        width: side
        height: side + 30
        x: root.pointer.x + side + 24 > root.width ? root.pointer.x - side - 18 : root.pointer.x + 18
        y: root.pointer.y + side + 50 > root.height ? root.pointer.y - side - 48 : root.pointer.y + 18

        Repeater {
            model: 4
            Rectangle {
                required property int index
                x: -(index + 1) * 2
                y: -(index + 1) * 2 + 3
                width: loupe.side + (index + 1) * 4
                height: loupe.side + (index + 1) * 4
                radius: 10 + (index + 1) * 2
                color: "transparent"
                border.width: 2
                border.color: Qt.rgba(0, 0, 0, 0.12 * (1 - index / 4))
            }
        }
        Item {
            width: loupe.side
            height: loupe.side
            clip: true
            Image {
                source: root.source
                smooth: false
                cache: false
                width: frozen.sourceSize.width * loupe.cell
                height: frozen.sourceSize.height * loupe.cell
                x: -Math.floor(root.pointer.x * root.pixelRatio) * loupe.cell + Math.floor(loupe.cells / 2) * loupe.cell
                y: -Math.floor(root.pointer.y * root.pixelRatio) * loupe.cell + Math.floor(loupe.cells / 2) * loupe.cell
            }
            Rectangle {
                x: Math.floor(loupe.cells / 2) * loupe.cell - 1
                y: x
                width: loupe.cell + 2
                height: loupe.cell + 2
                color: "transparent"
                border.width: 1.5
                border.color: loupe.sample.hslLightness > 0.6 ? "#000000" : "#ffffff"
            }
        }
        Rectangle {
            width: loupe.side
            height: loupe.side
            radius: 10
            color: "transparent"
            border.width: 3
            border.color: "#ffffff"
        }
        Rectangle {
            y: loupe.side + 8
            anchors.horizontalCenter: parent.horizontalCenter
            width: hexRow.implicitWidth + 16
            height: 22
            radius: 6
            color: Qt.rgba(0, 0, 0, 0.7)
            Row {
                id: hexRow
                anchors.centerIn: parent
                spacing: 6
                Rectangle {
                    width: 10
                    height: 10
                    radius: 3
                    anchors.verticalCenter: parent.verticalCenter
                    color: loupe.sample
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.6)
                }
                Text {
                    text: loupe.sample.toString().toUpperCase()
                    color: "#ffffff"
                    font.family: pal.mono
                    font.pixelSize: 12
                }
            }
        }
    }

    Rectangle {
        id: banner
        anchors.horizontalCenter: parent.horizontalCenter
        y: 28
        visible: !root.dragging
        width: bannerText.implicitWidth + 40
        height: 34
        radius: 17
        color: Qt.rgba(0, 0, 0, 0.62)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)
        Text {
            id: bannerText
            anchors.centerIn: parent
            text: root.hint + "   ·   Esc to cancel"
            color: "#ffffff"
            font.family: pal.sans
            font.pixelSize: 13
            font.weight: Font.Medium
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.windowMode ? Qt.PointingHandCursor : Qt.CrossCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPositionChanged: mouse => {
            root.pointer = Qt.point(mouse.x, mouse.y)
            root.hasPointer = true
            if (root.windowMode)
                root.hovered = root.windowAt(mouse.x, mouse.y)
        }
        onEntered: root.hasPointer = true
        onPressed: mouse => {
            if (mouse.button === Qt.RightButton) {
                Capture.overlayCancel()
                return
            }
            root.pointer = Qt.point(mouse.x, mouse.y)
            root.hasPointer = true
            if (root.windowMode || root.colorMode)
                return
            root.anchor = Qt.point(mouse.x, mouse.y)
            root.dragging = true
        }
        onReleased: mouse => {
            if (mouse.button !== Qt.LeftButton)
                return
            if (root.colorMode) {
                Capture.overlayPoint(root.screenIndex, mouse.x, mouse.y)
            } else if (root.windowMode) {
                root.finishWindow(root.windowAt(mouse.x, mouse.y))
            } else if (root.dragging) {
                root.dragging = false
                const s = root.selection
                if (s.width >= 4 && s.height >= 4)
                    Capture.overlayDone(root.screenIndex, s.x, s.y, s.width, s.height)
            }
        }
    }
}
