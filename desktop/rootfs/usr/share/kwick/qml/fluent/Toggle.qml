import QtQuick

MouseArea {
    id: toggle

    property bool checked: false
    signal toggled(bool value)

    implicitWidth: 40
    implicitHeight: 20
    hoverEnabled: true
    onClicked: toggle.toggled(!checked)

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: toggle.checked ? (toggle.pressed ? Fluent.accentPressed : toggle.containsMouse ? Fluent.accentHover : Fluent.accent)
                              : (toggle.containsMouse ? Fluent.controlHover : Fluent.textBox)
        border.width: toggle.checked ? 0 : 1
        border.color: Fluent.strongStroke
    }

    Rectangle {
        readonly property int size: toggle.containsMouse || toggle.pressed ? 14 : 12
        width: toggle.pressed ? 17 : size
        height: size
        radius: size / 2
        anchors.verticalCenter: parent.verticalCenter
        x: toggle.checked ? parent.width - width - 4 : 4
        color: toggle.checked ? Fluent.onAccent : Fluent.text2
        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: 100 } }
    }
}
