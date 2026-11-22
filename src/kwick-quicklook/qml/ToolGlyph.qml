import QtQuick

Rectangle {
    id: button
    required property var theme
    property string icon
    property string tip
    property bool enabled: true
    signal clicked()

    width: 30
    height: 28
    radius: theme.small
    opacity: enabled ? 1 : 0.35
    color: area.pressed ? theme.pressed : area.containsMouse ? theme.hover : "transparent"

    Image {
        anchors.centerIn: parent
        width: 18
        height: 18
        sourceSize: Qt.size(36, 36)
        source: button.theme.glyph(button.icon, button.theme.label)
        smooth: true
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: button.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }

    Rectangle {
        visible: area.containsMouse && button.tip !== ""
        y: parent.height + 6
        anchors.horizontalCenter: parent.horizontalCenter
        width: tipText.implicitWidth + 14
        height: 22
        radius: 5
        z: 10
        color: button.theme.dark ? "#3a3a3c" : "#ffffff"
        border.width: 1
        border.color: button.theme.hairline
        Text {
            id: tipText
            anchors.centerIn: parent
            text: button.tip
            color: button.theme.label
            font.family: button.theme.sans
            font.pixelSize: 11
            renderType: Text.NativeRendering
        }
    }
}
