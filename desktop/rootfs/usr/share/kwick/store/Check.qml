import QtQuick
import QtQuick.Layouts

RowLayout {
    id: c
    property bool checked: false
    property string text
    property color tint: Look.accent
    spacing: 10

    Rectangle {
        Layout.alignment: Qt.AlignTop
        implicitWidth: 18
        implicitHeight: 18
        radius: Look.win ? 4 : Look.mac ? 4 : 5
        color: c.checked ? c.tint : "transparent"
        border.width: c.checked ? 0 : 1.5
        border.color: Look.faint
        Glyph { anchors.centerIn: parent; visible: c.checked; name: "check"; size: 13; stroke: 2.4; color: Look.win && !Look.light ? "#000000" : "#ffffff" }
        MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: c.checked = !c.checked }
    }
    Text {
        Layout.fillWidth: true
        text: c.text
        color: Look.text
        font.family: Look.sans
        font.pixelSize: 13
        wrapMode: Text.WordWrap
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: c.checked = !c.checked }
    }
}
