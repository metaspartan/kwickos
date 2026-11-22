import QtQuick
import KwickCapture

Rectangle {
    id: row
    property string text
    property bool checked: false
    property bool header: false
    property bool focused: false
    signal triggered()

    Palette { id: pal }

    width: parent ? parent.width : 200
    height: header ? 26 : 24
    radius: 5
    readonly property bool lit: !header && (area.containsMouse || focused)
    color: lit ? pal.accent : "transparent"

    Glyph {
        name: "check"
        visible: row.checked && !row.header
        width: 14
        height: 14
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        tint: row.lit ? "#ffffff" : pal.label
    }

    Text {
        x: row.header ? 10 : 28
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: row.header ? 2 : 0
        text: row.text
        color: row.header ? pal.secondary : row.lit ? "#ffffff" : pal.label
        font.family: pal.sans
        font.pixelSize: row.header ? 11 : 13
        font.weight: row.header ? Font.DemiBold : Font.Normal
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: !row.header
        onClicked: row.triggered()
    }
}
