import QtQuick
import QtQuick.Layouts

Item {
    id: cell
    property string title
    property string subtitle
    property bool last: false
    property bool dim: false
    property int minHeight: 50
    default property alias trailing: slot.data
    Layout.fillWidth: true
    implicitHeight: Math.max(minHeight, textCol.implicitHeight + 22)

    ColumnLayout {
        id: textCol
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.right: slot.left
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
            Layout.fillWidth: true
            text: cell.title
            color: cell.dim ? Theme.faint : Theme.text
            font.family: Theme.sans
            font.pixelSize: Theme.bodySize
            elide: Text.ElideRight
        }
        Text {
            Layout.fillWidth: true
            visible: cell.subtitle !== ""
            text: cell.subtitle
            color: cell.dim ? Theme.faint : Theme.sub
            font.family: Theme.sans
            font.pixelSize: Theme.smallSize
            wrapMode: Text.WordWrap
        }
    }

    RowLayout {
        id: slot
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
    }

    Rectangle {
        visible: !cell.last
        height: 1
        color: Theme.line
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.right: parent.right
        anchors.bottom: parent.bottom
    }
}
