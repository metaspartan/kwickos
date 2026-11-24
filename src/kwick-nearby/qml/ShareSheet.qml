import QtQuick

Rectangle {
    id: root
    width: 600
    height: 452
    color: look.window
    focus: true

    property string pinFor: ""
    property string pinAlias: ""
    readonly property var devices: Nearby.devices

    Look { id: look }

    Keys.onEscapePressed: {
        if (visibility.open)
            visibility.open = false
        else if (root.pinFor !== "")
            root.pinFor = ""
        else
            Nearby.closeSheet()
    }

    Component.onCompleted: if (composer.visible) draftEdit.forceActiveFocus()

    onDevicesChanged: {
        for (let i = 0; i < devices.length; i++) {
            if (devices[i].state === "pin" && root.pinFor === "") {
                root.pinFor = devices[i].id
                root.pinAlias = devices[i].alias
                pinField.text = ""
                pinField.forceActiveFocus()
            }
        }
    }

    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        height: 82

        ItemPreview {
            id: preview
            x: 22
            anchors.verticalCenter: parent.verticalCenter
            pal: look
            items: Nearby.items
            text: Nearby.items.length === 0 && Nearby.draft.trim() !== ""
        }

        Column {
            anchors.left: preview.right
            anchors.leftMargin: 14
            anchors.right: addButton.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Text {
                width: parent.width
                text: Nearby.itemsTitle
                color: look.label
                font.family: look.sans
                font.pixelSize: 15
                font.weight: Font.DemiBold
                elide: Text.ElideMiddle
            }
            Text {
                width: parent.width
                text: Nearby.itemsSubtitle
                color: look.secondary
                font.family: look.sans
                font.pixelSize: 12
                elide: Text.ElideRight
            }
        }

        PushButton {
            id: addButton
            pal: look
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            glyph: "plus"
            text: Nearby.items.length > 0 ? "Add" : "Choose Files…"
            onClicked: Nearby.chooseFiles()
        }
    }

    Rectangle {
        id: rule
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: look.hairline
    }

    Rectangle {
        id: composer
        visible: Nearby.composing && Nearby.items.length === 0
        anchors.top: rule.bottom
        anchors.topMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        height: visible ? 70 : 0
        radius: Math.round(look.small + 1)
        color: look.field
        border.width: 1
        border.color: draftEdit.activeFocus ? Qt.rgba(look.accent.r, look.accent.g, look.accent.b, 0.7) : look.border

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: 9
            contentHeight: draftEdit.contentHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            TextEdit {
                id: draftEdit
                width: flick.width
                height: Math.max(flick.height, contentHeight)
                focus: composer.visible
                text: Nearby.draft
                color: look.label
                selectionColor: look.accent
                selectedTextColor: "#ffffff"
                font.family: look.sans
                font.pixelSize: 13
                wrapMode: TextEdit.Wrap
                onTextChanged: if (text !== Nearby.draft) Nearby.draft = text
                onCursorRectangleChanged: {
                    if (cursorRectangle.y + cursorRectangle.height > flick.contentY + flick.height)
                        flick.contentY = cursorRectangle.y + cursorRectangle.height - flick.height
                }
            }
            Text {
                visible: draftEdit.text === "" && !draftEdit.preeditText
                text: "Type a message, or choose files to share"
                color: look.tertiary
                font.family: look.sans
                font.pixelSize: 13
            }
        }
    }

    Item {
        id: body
        anchors.top: composer.visible ? composer.bottom : rule.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top

        Text {
            id: sectionLabel
            x: 22
            y: 12
            text: "Nearby"
            color: look.secondary
            font.family: look.sans
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 22
            anchors.verticalCenter: sectionLabel.verticalCenter
            visible: root.devices.length > 0
            text: Nearby.searching ? "Searching…" : ""
            color: look.tertiary
            font.family: look.sans
            font.pixelSize: 11
        }

        Flickable {
            id: grid
            anchors.top: sectionLabel.bottom
            anchors.topMargin: 6
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            contentHeight: flow.implicitHeight + 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            visible: root.devices.length > 0

            Flow {
                id: flow
                width: Math.min(grid.width, Math.max(1, root.devices.length) * 122)
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4
                Repeater {
                    model: root.devices
                    DeviceTile {
                        id: tile
                        required property var modelData
                        device: modelData
                        pal: look
                        enabled: Nearby.canSend || tile.busy
                        opacity: enabled ? 1 : 0.55
                        onActivated: {
                            if (tile.busy)
                                Nearby.cancelSend(modelData.id)
                            else if (modelData.state === "pin") {
                                root.pinFor = modelData.id
                                root.pinAlias = modelData.alias
                            } else
                                Nearby.send(modelData.id)
                        }
                    }
                }
            }
        }

        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 4
            visible: root.devices.length === 0
            spacing: 10
            Radar {
                anchors.horizontalCenter: parent.horizontalCenter
                pal: look
                width: composer.visible ? 112 : 136
                height: width
                active: Nearby.searching || root.devices.length === 0
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Nearby.networkProblem !== "" ? "Send Nearby Is Unavailable" : "Looking for Nearby Devices…"
                color: look.label
                font.family: look.sans
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 380
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: Nearby.networkProblem !== "" ? Nearby.networkProblem : "Open LocalSend or Send Nearby on the other device. Both devices need to be on the same network."
                color: look.secondary
                font.family: look.sans
                font.pixelSize: 12
                lineHeight: 1.1
            }
        }
    }

    Rectangle {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 50
        color: look.toolbar

        Rectangle {
            anchors.top: parent.top
            width: parent.width
            height: 1
            color: look.hairline
        }

        Row {
            x: 20
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Allow me to be discovered by:"
                color: look.secondary
                font.family: look.sans
                font.pixelSize: 12
            }
            Rectangle {
                id: visibilityButton
                anchors.verticalCenter: parent.verticalCenter
                width: visRow.implicitWidth + 14
                height: 24
                radius: 6
                color: visArea.containsMouse || visibility.open ? look.hover : "transparent"
                Row {
                    id: visRow
                    anchors.centerIn: parent
                    spacing: 4
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Nearby.visibilityText
                        color: look.accent
                        font.family: look.sans
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "chevron"
                        width: 10
                        height: 10
                        tint: look.accent
                    }
                }
                MouseArea {
                    id: visArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: visibility.open = !visibility.open
                }
            }
        }

        PushButton {
            pal: look
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: "Done"
            onClicked: Nearby.closeSheet()
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.pinFor !== ""
        color: Qt.rgba(0, 0, 0, look.dark ? 0.45 : 0.25)
        z: 50
        MouseArea { anchors.fill: parent }

        Rectangle {
            anchors.centerIn: parent
            width: 320
            height: pinColumn.implicitHeight + 36
            radius: look.radius
            color: look.panel
            border.width: 1
            border.color: look.border

            Column {
                id: pinColumn
                anchors.centerIn: parent
                width: parent.width - 40
                spacing: 12
                Glyph {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "lock"
                    width: 30
                    height: 30
                    tint: look.accent
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Enter the PIN for " + root.pinAlias
                    color: look.label
                    font.family: look.sans
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "This device only accepts files from senders who know its PIN."
                    color: look.secondary
                    font.family: look.sans
                    font.pixelSize: 12
                }
                Rectangle {
                    width: parent.width
                    height: 32
                    radius: Math.round(look.small)
                    color: look.field
                    border.width: 1
                    border.color: pinField.activeFocus ? look.accent : look.border
                    TextInput {
                        id: pinField
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        horizontalAlignment: TextInput.AlignHCenter
                        color: look.label
                        font.family: look.sans
                        font.pixelSize: 16
                        font.letterSpacing: 4
                        maximumLength: 12
                        echoMode: TextInput.Normal
                        onAccepted: sendPin.clicked()
                    }
                }
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    PushButton {
                        pal: look
                        text: "Cancel"
                        onClicked: {
                            Nearby.cancelSend(root.pinFor)
                            root.pinFor = ""
                        }
                    }
                    PushButton {
                        id: sendPin
                        pal: look
                        primary: true
                        text: "Send"
                        enabled: pinField.text.length >= 4
                        onClicked: {
                            Nearby.submitPin(root.pinFor, pinField.text)
                            root.pinFor = ""
                        }
                    }
                }
            }
        }
    }

    VisibilityMenu {
        id: visibility
        pal: look
        anchorItem: visibilityButton
    }
}
