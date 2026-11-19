import QtQuick
import org.kde.kirigami as Kirigami
import "file:///usr/share/kwick/qml/fluent"

MouseArea {
    id: toast

    property string appName
    property string appIcon
    property string summary
    property string body
    property var image
    property date time
    property date now
    signal activated()
    signal dismissed()

    function ago() {
        const m = Math.floor((now - time) / 60000)
        if (m < 1)
            return "Now"
        if (m < 60)
            return m + "m ago"
        if (m < 1440)
            return Qt.formatTime(time, "h:mm AP")
        return Qt.formatDate(time, "M/d")
    }

    height: content.implicitHeight + 28
    hoverEnabled: true
    onClicked: toast.activated()

    Rectangle {
        anchors.fill: parent
        radius: Fluent.overlayRadius
        color: toast.containsMouse ? Fluent.controlHover : Fluent.card
        border.width: 1
        border.color: Fluent.controlStroke
    }

    Column {
        id: content
        x: 14
        y: 12
        width: parent.width - 28
        spacing: 6

        Row {
            width: parent.width
            spacing: 8

            Kirigami.Icon {
                width: 16
                height: 16
                source: toast.appIcon || "preferences-desktop-notification"
            }

            FluentText {
                width: parent.width - 16 - 8 - stamp.width - 8
                text: toast.appName
                font.pixelSize: Fluent.caption
                level: 1
            }

            FluentText {
                id: stamp
                text: toast.ago()
                font.pixelSize: Fluent.caption
                level: 2
                visible: !toast.containsMouse
            }
        }

        Row {
            width: parent.width
            spacing: 12

            Kirigami.Icon {
                id: picture
                width: 48
                height: 48
                source: toast.image
                visible: !!toast.image && toast.image !== toast.appIcon
            }

            Column {
                width: parent.width - (picture.visible ? 60 : 0)
                spacing: 2

                FluentText {
                    width: parent.width
                    text: toast.summary
                    strong: true
                }

                FluentText {
                    width: parent.width
                    text: toast.body.replace(/<[^>]*>/g, "")
                    font.pixelSize: Fluent.caption
                    level: 1
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    visible: text !== ""
                }
            }
        }
    }

    IconButton {
        anchors.right: parent.right
        anchors.rightMargin: 6
        y: 6
        width: 28
        height: 28
        iconSize: 12
        visible: toast.containsMouse
        icon: "window-close-symbolic"
        onClicked: toast.dismissed()
    }
}
