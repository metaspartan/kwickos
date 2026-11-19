import QtQuick
import org.kde.kirigami as Kirigami

MouseArea {
    id: button

    property string icon
    property int iconSize: 16
    property bool checked: false

    implicitWidth: 32
    implicitHeight: 32
    hoverEnabled: true

    Subtle {
        anchors.fill: parent
        hovered: button.containsMouse
        pressed: button.pressed
        active: button.checked
    }

    Kirigami.Icon {
        anchors.centerIn: parent
        width: button.iconSize
        height: button.iconSize
        source: button.icon
        color: Fluent.text
        isMask: true
        opacity: button.enabled ? 1 : 0.4
    }
}
