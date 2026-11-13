import QtQuick
import org.kde.kirigami as Kirigami

Rectangle {
    id: ai
    property string name
    property string icon
    implicitWidth: 34
    implicitHeight: 34
    radius: 9
    color: "#3a3a42"
    border.width: 1
    border.color: Theme.line

    Text {
        anchors.centerIn: parent
        visible: !ic.valid
        text: ai.name.length ? ai.name.charAt(0).toUpperCase() : "?"
        color: Theme.text
        font.family: Theme.sans
        font.pixelSize: 15
        font.weight: Font.DemiBold
    }
    Kirigami.Icon {
        id: ic
        anchors.centerIn: parent
        width: 24
        height: 24
        source: ai.icon
        visible: valid
    }
}
