import QtQuick

FocusScope {
    id: t
    property bool checked: false
    signal toggled(bool value)
    implicitWidth: 42
    implicitHeight: 24
    activeFocusOnTab: enabled
    opacity: enabled ? 1 : 0.4

    Rectangle {
        anchors.fill: track
        anchors.margins: -3.5
        radius: height / 2
        color: "transparent"
        border.width: 3
        border.color: Theme.focusRing
        visible: t.activeFocus
    }

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: t.checked ? Theme.accent : Theme.knobOff
        Behavior on color { ColorAnimation { duration: 160 } }

        Rectangle {
            width: parent.height - 4
            height: width
            radius: width / 2
            y: 2
            x: t.checked ? parent.width - width - 2 : 2
            color: "#ffffff"
            border.width: Theme.dark ? 0 : 0.5
            border.color: "#26000000"
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: t.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: { t.forceActiveFocus(); t.toggled(!t.checked) }
    }

    Keys.onSpacePressed: t.toggled(!t.checked)
}
