import QtQuick

Rectangle {
    id: b
    property string text
    property bool primary: false
    property bool enabled: true
    property bool danger: false
    signal clicked()
    implicitWidth: label.implicitWidth + 28
    implicitHeight: 30
    radius: 8
    opacity: enabled ? 1 : 0.4
    color: primary ? (area.pressed ? Qt.darker(Theme.accent, 1.2) : area.containsMouse ? Qt.lighter(Theme.accent, 1.1) : Theme.accent)
                   : (area.pressed ? Theme.controlPressed : area.containsMouse ? Theme.controlHover : Theme.control)
    border.width: 0
    border.color: Theme.line

    Text {
        id: label
        anchors.centerIn: parent
        text: b.text
        color: b.danger ? Theme.bad : "#e6ffffff"
        font.family: Theme.sans
        font.pixelSize: 13
        font.weight: Font.Medium
    }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.topMargin: -7
        anchors.bottomMargin: -7
        hoverEnabled: true
        enabled: b.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: b.clicked()
    }
}
