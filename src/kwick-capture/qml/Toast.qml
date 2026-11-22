import QtQuick
import KwickCapture

Item {
    id: root
    property int edge: 0
    readonly property int pad: 22

    Palette { id: pal }

    function syncMask() {
        Capture.setMask(root.Window.window, [Qt.rect(card.x - 8, card.y - 8, card.width + 16, card.height + 16)])
    }
    onWidthChanged: syncMask()
    onHeightChanged: syncMask()
    focus: true
    Component.onCompleted: {
        syncMask()
        forceActiveFocus()
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            Capture.toastDismiss()
            event.accepted = true
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && Capture.toastAction !== "") {
            Capture.toastAccept()
            event.accepted = true
        }
    }

    PanelBox {
        id: card
        width: 344
        height: content.implicitHeight + 28
        x: root.width - width - root.pad - root.edge
        y: root.height - height - root.pad - root.edge
        radius: Math.round(14 * pal.ratio)
        onHeightChanged: root.syncMask()
        onXChanged: root.syncMask()
        onYChanged: root.syncMask()

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onContainsMouseChanged: Capture.toastHold(containsMouse)
            onClicked: {
                if (Capture.toastAction === "" && Capture.toastProgress < 0)
                    Capture.toastDismiss()
            }
        }

        Row {
            id: content
            x: 14
            y: 14
            width: parent.width - 28
            spacing: 12

            Rectangle {
                width: 36
                height: 36
                radius: 9
                color: Capture.toastIcon === "close" ? Qt.rgba(pal.danger.r, pal.danger.g, pal.danger.b, 0.16) : Qt.rgba(pal.accent.r, pal.accent.g, pal.accent.b, 0.16)
                Glyph {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    name: Capture.toastIcon === "close" ? "close" : Capture.toastIcon
                    tint: Capture.toastIcon === "close" ? pal.danger : pal.accent
                }
            }

            Column {
                width: parent.width - 48
                spacing: 3
                Text {
                    width: parent.width
                    text: Capture.toastTitle
                    color: pal.label
                    font.family: pal.sans
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: Capture.toastBody
                    visible: text !== ""
                    color: pal.secondary
                    font.family: pal.sans
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    lineHeight: 1.1
                }
                Item {
                    width: 1
                    height: 6
                    visible: Capture.toastProgress >= 0 || Capture.toastAction !== ""
                }
                Rectangle {
                    visible: Capture.toastProgress >= 0
                    width: parent.width
                    height: 5
                    radius: 2.5
                    color: pal.hairline
                    Rectangle {
                        width: Math.max(height, parent.width * Math.max(0, Capture.toastProgress))
                        height: parent.height
                        radius: parent.radius
                        color: pal.accent
                        Behavior on width { NumberAnimation { duration: 200 } }
                    }
                }
                Row {
                    visible: Capture.toastAction !== ""
                    spacing: 8
                    layoutDirection: Qt.RightToLeft
                    width: parent.width
                    Rectangle {
                        width: actionText.implicitWidth + 26
                        height: 28
                        radius: 7
                        color: actionArea.pressed ? Qt.darker(pal.accent, 1.15) : pal.accent
                        Text {
                            id: actionText
                            anchors.centerIn: parent
                            text: Capture.toastAction
                            color: "#ffffff"
                            font.family: pal.sans
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }
                        MouseArea {
                            id: actionArea
                            anchors.fill: parent
                            onClicked: Capture.toastAccept()
                        }
                    }
                    Rectangle {
                        width: laterText.implicitWidth + 26
                        height: 28
                        radius: 7
                        color: laterArea.pressed ? pal.pressed : pal.control
                        border.width: pal.dark ? 0 : 1
                        border.color: pal.border
                        Text {
                            id: laterText
                            anchors.centerIn: parent
                            text: "Not Now"
                            color: pal.label
                            font.family: pal.sans
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }
                        MouseArea {
                            id: laterArea
                            anchors.fill: parent
                            onClicked: Capture.toastDismiss()
                        }
                    }
                }
            }
        }
    }
}
