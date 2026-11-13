import QtQuick
import QtQuick.Layouts

Item {
    id: cell
    property string title
    property string subtitle
    property bool last: false
    property color titleColor: Theme.text
    default property alias trailing: slot.data
    Layout.fillWidth: true
    implicitHeight: Math.max(54, textCol.implicitHeight + 22)

    ColumnLayout {
        id: textCol
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.right: slot.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
            Layout.fillWidth: true
            text: cell.title
            color: cell.titleColor
            font.family: Theme.sans
            font.pixelSize: 13
            elide: Text.ElideRight
        }
        Text {
            Layout.fillWidth: true
            visible: cell.subtitle !== ""
            text: cell.subtitle
            color: Theme.sub
            font.family: Theme.sans
            font.pixelSize: 12
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
