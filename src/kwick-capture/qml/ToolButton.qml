import QtQuick
import KwickCapture

Rectangle {
    id: button
    property string icon
    property string text
    property string tip
    property bool checked: false
    property bool focused: false
    property bool accentText: false
    property bool chevron: false
    property bool enabled: true
    property real iconSize: 24
    property color tint: pal.label
    readonly property bool hovered: area.containsMouse
    signal clicked()
    signal doubleClicked()

    Palette { id: pal }

    implicitWidth: text !== "" ? label.implicitWidth + (icon !== "" ? iconSize + 6 : 0) + (chevron ? 15 : 0) + 22 : 44
    implicitHeight: 36
    radius: pal.small
    opacity: enabled ? 1 : 0.4
    color: area.pressed ? pal.pressed : checked ? pal.selected : area.containsMouse ? pal.hover : "transparent"

    Rectangle {
        anchors.fill: parent
        anchors.margins: -2
        radius: parent.radius + 2
        color: "transparent"
        border.width: 2
        border.color: Qt.rgba(pal.accent.r, pal.accent.g, pal.accent.b, 0.85)
        visible: button.focused
    }

    Row {
        anchors.centerIn: parent
        spacing: 6
        Glyph {
            name: button.icon
            visible: button.icon !== ""
            width: button.iconSize
            height: button.iconSize
            anchors.verticalCenter: parent.verticalCenter
            tint: button.checked && button.text === "" ? (pal.dark ? "#ffffff" : "#000000") : button.tint
        }
        Text {
            id: label
            text: button.text
            visible: text !== ""
            anchors.verticalCenter: parent.verticalCenter
            color: button.accentText ? pal.accent : pal.label
            font.family: pal.sans
            font.pixelSize: 13
            font.weight: Font.Medium
        }
        Glyph {
            name: "chevron"
            visible: button.chevron
            width: 10
            height: 10
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 1
            tint: pal.secondary
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: button.enabled
        onClicked: button.clicked()
        onDoubleClicked: button.doubleClicked()
    }
}
