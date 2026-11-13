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
                   : (area.pressed ? "#4a4a52" : area.containsMouse ? "#45454d" : Theme.field)
    border.width: primary ? 0 : 1
    border.color: Theme.line

    Text {
        id: label
        anchors.centerIn: parent
        text: b.text
        color: b.danger ? Theme.bad : "#ffffff"
        font.family: Theme.sans
        font.pixelSize: 13
        font.weight: Font.Medium
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: b.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: b.clicked()
    }
}
