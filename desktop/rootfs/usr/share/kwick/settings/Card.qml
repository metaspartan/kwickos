import QtQuick
import QtQuick.Layouts

Rectangle {
    id: card
    default property alias content: col.data
    Layout.fillWidth: true
    implicitHeight: col.implicitHeight
    radius: 12
    color: Theme.card
    border.width: 1
    border.color: Theme.line

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0
    }
}
