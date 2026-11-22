import QtQuick

Item {
    id: seg
    property var options: []
    property string current
    signal picked(string id)
    implicitHeight: Look.mac ? 26 : Look.win ? 32 : 34
    implicitWidth: row.implicitWidth + (Look.win ? 0 : 6)

    Rectangle {
        visible: !Look.win
        anchors.fill: parent
        radius: Look.mac ? 7 : 8
        color: Look.mac ? (Look.light ? "#e3e3e6" : "#323234") : Look.hover
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        x: Look.win ? 0 : 3
        spacing: Look.win ? 8 : 2
        Repeater {
            model: seg.options
            delegate: Rectangle {
                id: item
                required property var modelData
                readonly property bool on: seg.current === modelData.id
                width: label.implicitWidth + (Look.win ? 26 : 22)
                height: Look.win ? 32 : seg.height - 6
                radius: Look.win ? 16 : Look.mac ? 5 : 6
                color: Look.win ? (on ? Look.accent : ma.containsMouse ? Look.cardHover : Look.card) : on ? (Look.mac ? (Look.light ? "#ffffff" : "#5a5a5e") : Look.selected) : ma.containsMouse ? Look.hover : "transparent"
                border.width: Look.win && !on ? 1 : 0
                border.color: Look.cardStroke
                Text {
                    id: label
                    anchors.centerIn: parent
                    text: item.modelData.label
                    color: Look.win && item.on ? Look.onAccent : Look.text
                    font.family: Look.sans
                    font.pixelSize: 13
                    font.weight: item.on ? Font.DemiBold : Font.Normal
                }
                MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: seg.picked(item.modelData.id) }
            }
        }
    }
}
