import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: sw

    property bool checked: false

    signal toggled(bool on)

    implicitWidth: 26
    implicitHeight: 15

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: sw.checked ? Kirigami.Theme.highlightColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.16)
        Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
    }

    Rectangle {
        width: sw.height - 2
        height: width
        radius: width / 2
        y: 1
        x: sw.checked ? sw.width - width - 1 : 1
        color: "#ffffff"
        border.width: sw.checked ? 0 : 0.5
        border.color: Qt.rgba(0, 0, 0, 0.12)
        Behavior on x { NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -4
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.toggled(!sw.checked)
    }
}
