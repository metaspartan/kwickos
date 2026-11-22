import QtQuick
import KwickCapture

Rectangle {
    id: root
    property string path
    property bool temporary: false
    property string popup: ""
    property string flashText: ""
    readonly property var tools: [
        { id: "select", icon: "select", tip: "Select and Move" },
        { id: "pen", icon: "pen", tip: "Sketch" },
        { id: "highlighter", icon: "highlighter", tip: "Highlight" },
        { id: "line", icon: "line", tip: "Line" },
        { id: "arrow", icon: "arrow", tip: "Arrow" },
        { id: "rect", icon: "rect", tip: "Rectangle" },
        { id: "ellipse", icon: "ellipse", tip: "Oval" },
        { id: "text", icon: "type", tip: "Text" },
        { id: "redact", icon: "redact", tip: "Redact" },
        { id: "crop", icon: "crop", tip: "Crop" }
    ]
    readonly property var swatches: ["#ff3b30", "#ff9500", "#ffcc00", "#34c759", "#0a84ff", "#af52de", "#000000", "#ffffff"]
    readonly property var widths: [2, 4, 8]

    Palette { id: pal }

    color: pal.window
    focus: true
    Component.onCompleted: canvas.forceActiveFocus()

    function flash(text) {
        flashText = text
        flashTimer.restart()
    }
    function commitText() {
        if (textEntry.visible) {
            canvas.addText(textEntry.x, textEntry.y, textEdit.text)
            textEdit.text = ""
            textEntry.visible = false
            canvas.forceActiveFocus()
        }
    }
    function save() {
        commitText()
        Capture.markupSave(canvas, root.temporary ? "" : root.path)
        if (!root.temporary)
            flash("Saved")
    }

    Connections {
        target: Capture
        function onFlashCopied(what) {
            if (what === "image")
                root.flash("Copied")
        }
    }
    Timer {
        id: flashTimer
        interval: 1500
        onTriggered: root.flashText = ""
    }

    Shortcut { sequences: [StandardKey.Undo]; enabled: !textEntry.visible; onActivated: canvas.undo() }
    Shortcut { sequences: ["Ctrl+Shift+Z", StandardKey.Redo]; enabled: !textEntry.visible; onActivated: canvas.redo() }
    Shortcut { sequences: [StandardKey.Copy]; enabled: !textEntry.visible; onActivated: Capture.markupCopy(canvas) }
    Shortcut { sequences: [StandardKey.Save]; onActivated: root.save() }
    Shortcut { sequences: ["Ctrl+Shift+S"]; onActivated: { root.commitText(); Capture.markupSaveAs(canvas, root.path) } }
    Shortcut { sequences: ["Ctrl+W"]; onActivated: Capture.markupClose(root.Window.window) }
    Shortcut { sequences: ["Delete", "Backspace"]; enabled: !textEntry.visible && canvas.hasSelection; onActivated: canvas.deleteSelected() }
    Shortcut { sequences: ["Return", "Enter"]; enabled: canvas.cropPending && !textEntry.visible; onActivated: canvas.applyCrop() }
    Shortcut {
        sequences: ["Escape"]
        enabled: !textEntry.visible
        onActivated: {
            if (root.popup !== "")
                root.popup = ""
            else if (canvas.cropPending)
                canvas.cancelCrop()
            else if (canvas.tool !== "select")
                canvas.tool = "select"
        }
    }

    Rectangle {
        id: toolbar
        width: parent.width
        height: 52
        color: pal.toolbar
        z: 2

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: pal.hairline
        }

        Row {
            id: toolRow
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Repeater {
                model: root.tools
                ToolButton {
                    id: toolButton
                    required property var modelData
                    icon: modelData.icon
                    iconSize: 20
                    width: 36
                    height: 32
                    checked: canvas.tool === modelData.id
                    onClicked: {
                        root.commitText()
                        root.popup = ""
                        canvas.tool = modelData.id
                    }
                    onHoveredChanged: {
                        tipBox.target = hovered ? toolButton : null
                        tipBox.text = hovered ? modelData.tip : ""
                    }
                }
            }

            Item { width: 10; height: 32
                Rectangle { anchors.centerIn: parent; width: 1; height: 20; color: pal.hairline }
            }

            ToolButton {
                id: colorButton
                width: 44
                height: 32
                checked: root.popup === "color"
                onClicked: root.popup = root.popup === "color" ? "" : "color"
                onHoveredChanged: {
                    tipBox.target = hovered ? colorButton : null
                    tipBox.text = hovered ? "Color" : ""
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    radius: 10
                    color: canvas.color
                    border.width: 1
                    border.color: pal.border
                }
            }

            ToolButton {
                id: widthButton
                width: 44
                height: 32
                checked: root.popup === "width"
                onClicked: root.popup = root.popup === "width" ? "" : "width"
                onHoveredChanged: {
                    tipBox.target = hovered ? widthButton : null
                    tipBox.text = hovered ? "Line Width" : ""
                }
                Column {
                    anchors.centerIn: parent
                    spacing: 3
                    Repeater {
                        model: [1, 2, 4]
                        Rectangle {
                            required property int modelData
                            width: 18
                            height: modelData
                            radius: modelData / 2
                            color: pal.label
                        }
                    }
                }
            }

            Item { width: 10; height: 32
                Rectangle { anchors.centerIn: parent; width: 1; height: 20; color: pal.hairline }
            }

            ToolButton {
                id: undoButton
                icon: "undo"
                iconSize: 20
                width: 36
                height: 32
                enabled: canvas.canUndo
                onClicked: canvas.undo()
                onHoveredChanged: {
                    tipBox.target = hovered ? undoButton : null
                    tipBox.text = hovered ? "Undo" : ""
                }
            }
            ToolButton {
                id: redoButton
                icon: "redo"
                iconSize: 20
                width: 36
                height: 32
                enabled: canvas.canRedo
                onClicked: canvas.redo()
                onHoveredChanged: {
                    tipBox.target = hovered ? redoButton : null
                    tipBox.text = hovered ? "Redo" : ""
                }
            }
        }

        Row {
            id: actionRow
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.flashText !== ""
                text: root.flashText
                color: pal.secondary
                font.family: pal.sans
                font.pixelSize: 12
                rightPadding: 4
            }

            Row {
                visible: canvas.cropPending
                spacing: 6
                anchors.verticalCenter: parent.verticalCenter
                ToolButton {
                    text: "Cancel"
                    height: 30
                    onClicked: canvas.cancelCrop()
                }
                Rectangle {
                    width: cropText.implicitWidth + 24
                    height: 30
                    radius: 7
                    color: cropArea.pressed ? Qt.darker(pal.accent, 1.15) : pal.accent
                    Text {
                        id: cropText
                        anchors.centerIn: parent
                        text: "Crop"
                        color: "#ffffff"
                        font.family: pal.sans
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        id: cropArea
                        anchors.fill: parent
                        onClicked: canvas.applyCrop()
                    }
                }
                Item { width: 6; height: 30 }
            }

            ToolButton {
                id: shareButton
                icon: "share"
                iconSize: 20
                width: 36
                height: 32
                onClicked: {
                    root.commitText()
                    Capture.markupShare(canvas, root.path)
                }
                onHoveredChanged: {
                    tipBox.target = hovered ? shareButton : null
                    tipBox.text = hovered ? "Show in Folder" : ""
                }
            }
            ToolButton {
                id: copyButton
                icon: "copy"
                iconSize: 20
                width: 36
                height: 32
                onClicked: {
                    root.commitText()
                    Capture.markupCopy(canvas)
                }
                onHoveredChanged: {
                    tipBox.target = hovered ? copyButton : null
                    tipBox.text = hovered ? "Copy" : ""
                }
            }
            ToolButton {
                id: saveAsButton
                icon: "save"
                iconSize: 20
                width: 36
                height: 32
                onClicked: {
                    root.commitText()
                    Capture.markupSaveAs(canvas, root.path)
                }
                onHoveredChanged: {
                    tipBox.target = hovered ? saveAsButton : null
                    tipBox.text = hovered ? "Save As…" : ""
                }
            }
            Rectangle {
                width: doneText.implicitWidth + 28
                height: 30
                radius: 7
                anchors.verticalCenter: parent.verticalCenter
                color: doneArea.pressed ? Qt.darker(pal.accent, 1.15) : doneArea.containsMouse ? Qt.lighter(pal.accent, 1.08) : pal.accent
                Text {
                    id: doneText
                    anchors.centerIn: parent
                    text: root.temporary ? "Save…" : "Save"
                    color: "#ffffff"
                    font.family: pal.sans
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    id: doneArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.save()
                }
            }
        }
    }

    Item {
        id: stage
        anchors.top: toolbar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        Rectangle {
            readonly property rect r: canvas.imageRect
            x: canvas.x + r.x - 1
            y: canvas.y + r.y - 1
            width: r.width + 2
            height: r.height + 2
            color: "transparent"
            border.width: 1
            border.color: pal.hairline
        }

        MarkupCanvas {
            id: canvas
            objectName: "canvas"
            anchors.fill: parent
            anchors.margins: 22
            accent: pal.accent
            focus: true
            onTextRequested: (x, y, size) => {
                root.commitText()
                textEntry.x = x + canvas.x
                textEntry.y = y + canvas.y
                textEdit.font.pixelSize = size
                textEntry.visible = true
                textEdit.forceActiveFocus()
            }
            onToolChanged: if (tool !== "text") root.commitText()
        }

        Item {
            id: textEntry
            visible: false
            width: Math.max(80, textEdit.contentWidth + 12)
            height: textEdit.contentHeight + 8
            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                color: "transparent"
                border.width: 1
                border.color: pal.accent
                radius: 3
            }
            TextEdit {
                id: textEdit
                x: 0
                y: 0
                width: Math.max(80, contentWidth + 4)
                color: canvas.color
                font.family: "Inter"
                font.weight: Font.DemiBold
                selectionColor: Qt.rgba(pal.accent.r, pal.accent.g, pal.accent.b, 0.4)
                Keys.onPressed: event => {
                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                        root.commitText()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Escape) {
                        textEdit.text = ""
                        textEntry.visible = false
                        canvas.forceActiveFocus()
                        event.accepted = true
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            visible: root.popup !== ""
            onClicked: root.popup = ""
        }

        PanelBox {
            visible: root.popup === "color"
            fill: pal.menu
            radius: 10
            rings: 4
            x: colorButton.mapToItem(stage, 0, 0).x - 8
            y: 6
            width: swatchGrid.implicitWidth + 20
            height: swatchGrid.implicitHeight + 20
            Grid {
                id: swatchGrid
                anchors.centerIn: parent
                columns: 4
                spacing: 8
                Repeater {
                    model: root.swatches
                    Rectangle {
                        required property string modelData
                        width: 26
                        height: 26
                        radius: 13
                        color: modelData
                        border.width: canvas.color.toString() === modelData ? 2 : 1
                        border.color: canvas.color.toString() === modelData ? pal.accent : pal.border
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                canvas.color = parent.modelData
                                root.popup = ""
                            }
                        }
                    }
                }
            }
        }

        PanelBox {
            visible: root.popup === "width"
            fill: pal.menu
            radius: 10
            rings: 4
            x: widthButton.mapToItem(stage, 0, 0).x - 8
            y: 6
            width: 120
            height: widthColumn.implicitHeight + 12
            Column {
                id: widthColumn
                x: 6
                y: 6
                width: parent.width - 12
                Repeater {
                    model: root.widths
                    Rectangle {
                        required property int modelData
                        width: widthColumn.width
                        height: 28
                        radius: 5
                        color: widthArea.containsMouse ? pal.accent : "transparent"
                        Glyph {
                            name: "check"
                            visible: canvas.strokeWidth === parent.modelData
                            width: 13
                            height: 13
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            tint: widthArea.containsMouse ? "#ffffff" : pal.label
                        }
                        Rectangle {
                            x: 30
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 42
                            height: parent.modelData
                            radius: height / 2
                            color: widthArea.containsMouse ? "#ffffff" : pal.label
                        }
                        MouseArea {
                            id: widthArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                canvas.strokeWidth = parent.modelData
                                root.popup = ""
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        id: tipBox
        property Item target: null
        property string text: ""
        z: 5
        visible: target !== null && text !== "" && root.popup === ""
        readonly property point at: target ? target.mapToItem(root, target.width / 2, target.height) : Qt.point(0, 0)
        x: Math.round(Math.max(4, Math.min(root.width - width - 4, at.x - width / 2)))
        y: at.y + 8
        width: tipLabel.implicitWidth + 16
        height: 24
        radius: 6
        color: pal.menu
        border.width: 1
        border.color: pal.border
        Text {
            id: tipLabel
            anchors.centerIn: parent
            text: tipBox.text
            color: pal.label
            font.family: pal.sans
            font.pixelSize: 12
        }
    }
}
