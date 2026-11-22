import QtQuick

Rectangle {
    id: button
    property string text
    property bool primary: false
    property bool destructive: false
    property string glyph: ""
    property Look pal
    signal clicked()

    implicitWidth: Math.max(72, row.implicitWidth + 26)
    implicitHeight: 28
    radius: Math.round(pal.small)
    color: primary ? (area.pressed ? Qt.darker(pal.accent, 1.18) : area.containsMouse ? Qt.lighter(pal.accent, 1.08) : pal.accent)
                   : (area.pressed ? pal.controlPressed : area.containsMouse ? pal.controlHover : pal.control)
    border.width: !primary && !pal.dark ? 1 : 0
    border.color: Qt.rgba(0, 0, 0, 0.12)
    opacity: enabled ? 1 : 0.45

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        visible: button.primary
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.14) }
            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Glyph {
            visible: button.glyph !== ""
            anchors.verticalCenter: parent.verticalCenter
            name: button.glyph
            width: 14
            height: 14
            tint: button.primary ? "#ffffff" : button.pal.label
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: button.text
            color: button.primary ? "#ffffff" : button.destructive ? button.pal.bad : button.pal.label
            font.family: button.pal.sans
            font.pixelSize: 13
            font.weight: Font.Medium
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
