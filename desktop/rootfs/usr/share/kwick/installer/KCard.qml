import QtQuick
import QtQuick.Layouts

Rectangle {
    id: card
    default property alias content: col.data
    property alias spacing: col.spacing
    property int padding: 0
    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + padding * 2
    radius: Theme.radius
    color: Theme.card
    border.width: 1
    border.color: Theme.line

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: card.padding
        spacing: 0
    }
}
