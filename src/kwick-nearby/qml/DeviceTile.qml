import QtQuick

Item {
    id: tile
    required property var device
    property Look pal
    signal activated()

    width: 118
    height: 136

    readonly property string phase: device.state
    readonly property bool busy: phase === "waiting" || phase === "sending"
    readonly property string status: {
        switch (phase) {
        case "waiting": return "Waiting…"
        case "sending": return "Sending " + device.detail
        case "done": return "Sent"
        case "declined": return "Declined"
        case "busy": return "Busy"
        case "failed": return device.detail !== "" ? device.detail : "Failed"
        case "cancelled": return "Cancelled"
        case "pin": return "PIN Required"
        default: return device.model
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: tile.pal.radius
        color: area.pressed ? tile.pal.pressed : area.containsMouse ? tile.pal.hover : "transparent"
    }

    Avatar {
        id: avatar
        anchors.horizontalCenter: parent.horizontalCenter
        y: 8
        pal: tile.pal
        type: tile.device.type
        size: 62
        busy: tile.busy
        waiting: tile.phase === "waiting"
        progress: tile.device.progress
        badge: tile.phase === "done" ? "done" : (tile.phase === "declined" || tile.phase === "failed" || tile.phase === "busy") ? "bad" : ""
    }

    Text {
        id: name
        anchors.top: avatar.bottom
        anchors.topMargin: 4
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        horizontalAlignment: Text.AlignHCenter
        text: tile.device.alias
        color: tile.pal.label
        font.family: tile.pal.sans
        font.pixelSize: 12
        font.weight: Font.Medium
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        lineHeight: 0.95
    }

    Text {
        anchors.top: name.bottom
        anchors.topMargin: 1
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        horizontalAlignment: Text.AlignHCenter
        text: tile.status
        color: tile.phase === "done" ? tile.pal.good : (tile.phase === "declined" || tile.phase === "failed" || tile.phase === "busy") ? tile.pal.bad : tile.busy || tile.phase === "pin" ? tile.pal.accent : tile.pal.secondary
        font.family: tile.pal.sans
        font.pixelSize: 11
        elide: Text.ElideRight
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.activated()
    }
}
