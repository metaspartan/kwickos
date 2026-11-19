import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

MouseArea {
    id: item

    property alias text: label.text

    Layout.fillWidth: true
    implicitHeight: Math.round(Kirigami.Units.gridUnit * 1.35)
    hoverEnabled: true

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: Kirigami.Theme.highlightColor
        visible: item.containsMouse
    }

    PlasmaComponents3.Label {
        id: label
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        color: item.containsMouse ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
        textFormat: Text.PlainText
    }
}
