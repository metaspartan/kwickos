import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

MouseArea {
    id: entry

    property string text
    property string icon
    signal triggered()

    Layout.fillWidth: true
    implicitWidth: label.implicitWidth + (icon !== "" ? 76 : 48)
    implicitHeight: 36
    hoverEnabled: true
    onClicked: entry.triggered()

    Subtle {
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        anchors.topMargin: 2
        anchors.bottomMargin: 2
        hovered: entry.containsMouse
        pressed: entry.pressed
    }

    Kirigami.Icon {
        x: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        height: 16
        source: entry.icon
        visible: entry.icon !== ""
        isMask: true
        color: Fluent.text
    }

    FluentText {
        id: label
        x: entry.icon !== "" ? 44 : 16
        anchors.verticalCenter: parent.verticalCenter
        text: entry.text
    }
}
