import QtQuick
import "file:///usr/share/kwick/qml/fluent"

Item {
    id: header

    property string title
    property bool switchable: false
    property bool on: false
    signal back()
    signal toggled(bool value)

    width: parent ? parent.width : 0
    height: 56

    IconButton {
        x: 16
        anchors.verticalCenter: parent.verticalCenter
        icon: "go-previous-symbolic"
        onClicked: header.back()
    }

    FluentText {
        x: 60
        anchors.verticalCenter: parent.verticalCenter
        text: header.title
        strong: true
    }

    Toggle {
        visible: header.switchable
        anchors.right: parent.right
        anchors.rightMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        checked: header.on
        onToggled: value => header.toggled(value)
    }
}
