import QtQuick
import QtQuick.Layouts

RowLayout {
    id: r
    property string label
    property string message
    property bool error: false
    property int labelWidth: 132
    default property alias field: slot.data
    Layout.fillWidth: true
    spacing: 16

    Text {
        Layout.preferredWidth: r.labelWidth
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: (Theme.controlHeight - height) / 2
        text: r.label
        color: Theme.text
        font.family: Theme.sans
        font.pixelSize: Theme.bodySize
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 5
        ColumnLayout {
            id: slot
            Layout.fillWidth: true
            spacing: 0
        }
        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 2
            visible: r.message !== ""
            text: r.message
            color: r.error ? Theme.bad : Theme.sub
            font.family: Theme.sans
            font.pixelSize: Theme.smallSize
            wrapMode: Text.WordWrap
        }
    }
}
