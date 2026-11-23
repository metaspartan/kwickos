import QtQuick

Rectangle {
    id: cap
    property string text
    property var theme
    property bool hot: false
    readonly property bool glyph: text.length === 1 && "⌘⌥⌃⇧↩⇥⌫⌦←→↑↓⇞⇟↖↘".indexOf(text) >= 0
    implicitWidth: Math.max(implicitHeight, label.implicitWidth + 12)
    implicitHeight: 22
    radius: theme.capRadius
    color: hot ? Qt.rgba(1, 1, 1, theme.dark ? 0.16 : 0.9) : theme.capFill
    border.width: 1
    border.color: theme.capEdge

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: cap.radius / 2
        anchors.rightMargin: cap.radius / 2
        height: 1
        color: cap.theme.capShadow
    }

    Text {
        id: label
        anchors.centerIn: parent
        anchors.verticalCenterOffset: cap.glyph ? 0 : -0.5
        text: cap.text
        color: cap.theme.label
        font.family: cap.theme.font
        font.pixelSize: cap.glyph ? 13 : 11.5
        font.weight: Font.Medium
    }
}
