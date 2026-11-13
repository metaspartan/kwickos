import QtQuick

Rectangle {
    id: t
    property bool checked: false
    property bool enabled: true
    signal toggled(bool value)
    implicitWidth: 44
    implicitHeight: 26
    radius: 13
    opacity: enabled ? 1 : 0.4
    color: checked ? Theme.accent : "#4a4a52"
    Behavior on color { ColorAnimation { duration: 140 } }

    Rectangle {
        width: 22
        height: 22
        radius: 11
        y: 2
        x: t.checked ? parent.width - width - 2 : 2
        color: "#ffffff"
        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        anchors.fill: parent
        enabled: t.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: t.toggled(!t.checked)
    }
}
