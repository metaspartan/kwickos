import QtQuick

Item {
    id: root
    readonly property var info: Nearby.incoming
    readonly property string phase: info.state || ""
    readonly property int pad: 14
    width: 380 + pad * 2
    height: card.height + pad * 2

    Look { id: look }

    HoverHandler {
        onHoveredChanged: Nearby.holdIncoming(hovered)
    }

    Repeater {
        model: 7
        Rectangle {
            required property int index
            readonly property real spread: (index + 1) * 1.8
            x: card.x - spread
            y: card.y - spread + 3
            width: card.width + 2 * spread
            height: card.height + 2 * spread
            radius: card.radius + spread
            color: "transparent"
            border.width: 2
            border.color: Qt.rgba(0, 0, 0, (look.dark ? 0.16 : 0.07) * (1 - index / 7))
        }
    }

    Rectangle {
        id: card
        x: root.pad
        y: root.pad
        width: 380
        height: content.implicitHeight + 28
        radius: Math.round(look.radius + 4)
        color: look.panel
        border.width: 1
        border.color: look.border

        Column {
            id: content
            x: 14
            y: 14
            width: parent.width - 28
            spacing: 12

            Row {
                width: parent.width
                spacing: 12

                Avatar {
                    id: avatar
                    pal: look
                    size: 46
                    type: root.info.type || "desktop"
                    busy: root.phase === "receiving"
                    waiting: root.phase === "receiving" && (root.info.progress || 0) <= 0
                    progress: root.info.progress || 0
                    badge: root.phase === "done" ? "done" : root.phase === "failed" ? "bad" : ""
                }

                Column {
                    width: parent.width - avatar.width - 12
                    anchors.verticalCenter: avatar.verticalCenter
                    spacing: 3
                    Text {
                        width: parent.width
                        text: root.phase === "done" ? "Received from " + root.info.alias
                            : root.phase === "receiving" ? "Receiving from " + root.info.alias
                            : root.phase === "failed" ? "Transfer from " + root.info.alias + " Failed"
                            : root.phase === "cancelled" ? root.info.alias
                            : root.info.title || ""
                        color: look.label
                        font.family: look.sans
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: root.phase === "ask" || root.phase === "message" ? (root.info.subtitle || "") : (root.info.detail || "")
                        color: root.phase === "copied" ? look.accent : look.secondary
                        font.family: look.sans
                        font.pixelSize: 12
                        elide: Text.ElideMiddle
                    }
                    Row {
                        visible: root.phase === "ask" || root.phase === "message"
                        spacing: 4
                        Glyph {
                            anchors.verticalCenter: parent.verticalCenter
                            name: root.info.known ? "check" : "lock"
                            width: 10
                            height: 10
                            tint: root.info.known ? look.good : look.tertiary
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: (root.info.known ? "Known device" : "New device") + "  ·  " + (root.info.model || "") + "  ·  " + (root.info.ip || "")
                            color: look.tertiary
                            font.family: look.sans
                            font.pixelSize: 11
                        }
                    }
                }
            }

            Rectangle {
                visible: (root.phase === "message" || root.phase === "copied") && (root.info.text || "") !== ""
                width: parent.width
                height: Math.min(messageText.implicitHeight + 18, 112)
                radius: Math.round(look.small + 1)
                color: look.field
                border.width: 1
                border.color: look.border
                clip: true
                Text {
                    id: messageText
                    x: 10
                    y: 9
                    width: parent.width - 20
                    text: root.info.text || ""
                    color: root.info.link ? look.accent : look.label
                    font.family: look.sans
                    font.pixelSize: 13
                    wrapMode: Text.Wrap
                    maximumLineCount: 5
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }

            Rectangle {
                visible: root.phase === "receiving"
                width: parent.width
                height: 6
                radius: 3
                color: look.hairline
                Rectangle {
                    width: Math.max(6, parent.width * Math.min(1, root.info.progress || 0))
                    height: parent.height
                    radius: 3
                    color: look.accent
                    Behavior on width { NumberAnimation { duration: 160 } }
                }
            }

            Row {
                anchors.right: parent.right
                spacing: 8
                visible: root.phase !== "copied" && root.phase !== "cancelled"

                PushButton {
                    pal: look
                    visible: root.phase === "ask" || root.phase === "message"
                    text: "Decline"
                    onClicked: Nearby.decline()
                }
                PushButton {
                    pal: look
                    visible: root.phase === "ask"
                    primary: true
                    text: "Accept"
                    onClicked: Nearby.accept()
                }
                PushButton {
                    pal: look
                    visible: root.phase === "message"
                    primary: !root.info.link
                    text: "Copy"
                    onClicked: Nearby.copyMessage()
                }
                PushButton {
                    pal: look
                    visible: root.phase === "message" && !!root.info.link
                    primary: true
                    text: "Open Link"
                    onClicked: Nearby.openMessageLink()
                }
                PushButton {
                    pal: look
                    visible: root.phase === "receiving"
                    text: "Stop"
                    onClicked: Nearby.cancelIncoming()
                }
                PushButton {
                    pal: look
                    visible: root.phase === "done" || root.phase === "failed"
                    text: "Close"
                    onClicked: Nearby.closeIncoming()
                }
                PushButton {
                    pal: look
                    visible: root.phase === "done"
                    text: "Show in Files"
                    onClicked: Nearby.revealReceived()
                }
                PushButton {
                    pal: look
                    visible: root.phase === "done" && (root.info.saved || []).length === 1
                    primary: true
                    text: "Open"
                    onClicked: Nearby.openReceived()
                }
            }
        }
    }
}
