import QtQuick
import KwickCapture

Rectangle {
    id: root
    readonly property color c: Capture.picked
    readonly property int r: Math.round(c.r * 255)
    readonly property int g: Math.round(c.g * 255)
    readonly property int b: Math.round(c.b * 255)
    readonly property string hex: c.toString().toUpperCase()
    readonly property string rgb: "rgb(" + r + ", " + g + ", " + b + ")"
    readonly property string hsl: "hsl(" + Math.round(Math.max(0, c.hslHue) * 360) + ", " + Math.round(c.hslSaturation * 100) + "%, " + Math.round(c.hslLightness * 100) + "%)"
    property string copied: ""

    Palette { id: pal }

    color: pal.window
    focus: true
    Component.onCompleted: forceActiveFocus()

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            root.Window.window.close()
        } else if (event.matches(StandardKey.Copy)) {
            Capture.copyString(root.hex)
        } else if (event.key === Qt.Key_P || event.key === Qt.Key_Space) {
            Capture.pickColor()
        } else {
            return
        }
        event.accepted = true
    }

    Connections {
        target: Capture
        function onFlashCopied(what) {
            root.copied = what
            flash.restart()
        }
    }
    Timer {
        id: flash
        interval: 1400
        onTriggered: root.copied = ""
    }

    Column {
        x: 16
        y: 16
        width: parent.width - 32
        spacing: 14

        Rectangle {
            width: parent.width
            height: 92
            radius: Math.round(10 * pal.ratio)
            color: root.c
            border.width: 1
            border.color: pal.border
            Text {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 12
                text: root.hex
                color: root.c.hslLightness > 0.62 ? Qt.rgba(0, 0, 0, 0.75) : Qt.rgba(1, 1, 1, 0.92)
                font.family: pal.mono
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
        }

        Rectangle {
            width: parent.width
            height: rows.implicitHeight
            radius: Math.round(10 * pal.ratio)
            color: pal.card
            border.width: pal.dark ? 0 : 1
            border.color: pal.hairline

            Column {
                id: rows
                width: parent.width
                Repeater {
                    model: [
                        { label: "HEX", value: root.hex },
                        { label: "RGB", value: root.rgb },
                        { label: "HSL", value: root.hsl }
                    ]
                    Item {
                        id: line
                        required property var modelData
                        required property int index
                        width: rows.width
                        height: 40
                        Rectangle {
                            visible: line.index > 0
                            x: 12
                            width: parent.width - 24
                            height: 1
                            color: pal.hairline
                        }
                        Text {
                            x: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: line.modelData.label
                            color: pal.secondary
                            font.family: pal.sans
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                        Text {
                            x: 56
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 56 - 48
                            text: line.modelData.value
                            color: pal.label
                            font.family: pal.mono
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                        ToolButton {
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            width: 32
                            height: 28
                            iconSize: 16
                            icon: root.copied === line.modelData.value ? "check" : "copy"
                            tint: root.copied === line.modelData.value ? pal.accent : pal.secondary
                            onClicked: Capture.copyString(line.modelData.value)
                        }
                    }
                }
            }
        }

        Text {
            text: "Recent Colors"
            color: pal.secondary
            font.family: pal.sans
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }

        Row {
            spacing: 8
            Repeater {
                model: Capture.recent
                Rectangle {
                    required property string modelData
                    width: 28
                    height: 28
                    radius: 14
                    color: modelData
                    border.width: root.hex === modelData ? 2 : 1
                    border.color: root.hex === modelData ? pal.accent : pal.border
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Capture.choose(parent.modelData)
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: 34
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.copied !== "" ? "Copied " + root.copied : "HEX copied to clipboard"
                color: pal.secondary
                font.family: pal.sans
                font.pixelSize: 12
                elide: Text.ElideRight
                width: parent.width - pickButton.width - 10
            }
            Rectangle {
                id: pickButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: pickRow.implicitWidth + 24
                height: 30
                radius: 8
                color: pickArea.pressed ? Qt.darker(pal.accent, 1.15) : pal.accent
                Row {
                    id: pickRow
                    anchors.centerIn: parent
                    spacing: 6
                    Glyph {
                        name: "color"
                        width: 16
                        height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        tint: "#ffffff"
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Pick Again"
                        color: "#ffffff"
                        font.family: pal.sans
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                }
                MouseArea {
                    id: pickArea
                    anchors.fill: parent
                    onClicked: Capture.pickColor()
                }
            }
        }
    }
}
