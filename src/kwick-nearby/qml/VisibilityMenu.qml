import QtQuick

Item {
    id: menu
    property Look pal
    property Item anchorItem
    property bool open: false
    property point origin: Qt.point(0, 0)
    onOpenChanged: if (open && anchorItem) origin = anchorItem.mapToItem(menu, 0, 0)
    anchors.fill: parent
    visible: open
    z: 100

    readonly property var options: [
        { id: "off", label: "Receiving Off", hint: "Nobody can send you files" },
        { id: "contacts", label: "Known Devices Only", hint: "Devices you accepted before" },
        { id: "everyone", label: "Everyone for 10 Minutes", hint: "Any nearby device can ask" }
    ]

    MouseArea {
        anchors.fill: parent
        onClicked: menu.open = false
    }

    Rectangle {
        id: box
        x: Math.max(8, Math.min(menu.width - width - 8, menu.origin.x - 6))
        y: Math.max(8, menu.origin.y - height - 6)
        width: 262
        height: column.implicitHeight + 10
        radius: Math.round(menu.pal.small + 3)
        color: menu.pal.menu
        border.width: 1
        border.color: menu.pal.border

        Column {
            id: column
            x: 5
            y: 5
            width: parent.width - 10
            Repeater {
                model: menu.options
                Rectangle {
                    id: row
                    required property var modelData
                    width: column.width
                    height: 44
                    radius: Math.round(menu.pal.small)
                    color: rowArea.containsMouse ? menu.pal.accent : "transparent"
                    Glyph {
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Nearby.visibility === row.modelData.id
                        name: "check"
                        width: 13
                        height: 13
                        tint: rowArea.containsMouse ? "#ffffff" : menu.pal.label
                    }
                    Column {
                        x: 28
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text {
                            text: row.modelData.label
                            color: rowArea.containsMouse ? "#ffffff" : menu.pal.label
                            font.family: menu.pal.sans
                            font.pixelSize: 13
                        }
                        Text {
                            text: row.modelData.hint
                            color: rowArea.containsMouse ? Qt.rgba(1, 1, 1, 0.8) : menu.pal.secondary
                            font.family: menu.pal.sans
                            font.pixelSize: 11
                        }
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            Nearby.setVisibility(row.modelData.id)
                            menu.open = false
                        }
                    }
                }
            }
        }
    }
}
