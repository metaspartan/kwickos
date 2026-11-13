import QtQuick

Rectangle {
    id: seg
    property var options: []
    property string current
    signal picked(string id)
    implicitHeight: 30
    implicitWidth: row.implicitWidth + 6
    radius: 9
    color: "#3a3a41"

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 2
        Repeater {
            model: seg.options
            delegate: Rectangle {
                id: item
                required property var modelData
                readonly property bool on: seg.current === modelData.id
                width: label.implicitWidth + 22
                height: 24
                radius: 7
                color: on ? Theme.accent : "transparent"
                Text {
                    id: label
                    anchors.centerIn: parent
                    text: item.modelData.label
                    color: item.on ? "#ffffff" : Theme.text
                    font.family: Theme.sans
                    font.pixelSize: 12
                    font.weight: item.on ? Font.Medium : Font.Normal
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: seg.picked(item.modelData.id) }
            }
        }
    }
}
