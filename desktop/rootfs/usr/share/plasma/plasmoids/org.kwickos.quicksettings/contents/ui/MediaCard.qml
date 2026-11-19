import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "file:///usr/share/kwick/qml/fluent"

Item {
    id: card

    property var media

    implicitHeight: visible ? 148 : 0

    Rectangle {
        anchors.fill: parent
        anchors.margins: 12
        anchors.bottomMargin: 0
        radius: Fluent.overlayRadius
        color: Fluent.card
        border.width: 1
        border.color: Fluent.controlStroke

        RowLayout {
            x: 16
            y: 14
            width: parent.width - 32
            spacing: 8

            Kirigami.Icon {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                source: card.media ? card.media.appIcon : ""
            }

            FluentText {
                Layout.fillWidth: true
                text: card.media ? card.media.identity : ""
                font.pixelSize: Fluent.caption
                level: 1
            }
        }

        Column {
            x: 16
            y: 42
            width: parent.width - 32 - art.width - 12

            FluentText {
                width: parent.width
                text: card.media ? card.media.track : ""
                strong: true
            }

            FluentText {
                width: parent.width
                text: card.media ? card.media.artist : ""
                font.pixelSize: Fluent.caption
                level: 1
            }
        }

        Image {
            id: art
            anchors.right: parent.right
            anchors.rightMargin: 16
            y: 40
            width: 48
            height: 48
            source: card.media ? card.media.art : ""
            fillMode: Image.PreserveAspectCrop
            visible: status === Image.Ready
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            spacing: 8

            IconButton {
                icon: "media-skip-backward-symbolic"
                onClicked: card.media.previous()
            }

            IconButton {
                icon: card.media && card.media.playing ? "media-playback-pause-symbolic" : "media-playback-start-symbolic"
                onClicked: card.media.toggle()
            }

            IconButton {
                icon: "media-skip-forward-symbolic"
                onClicked: card.media.next()
            }
        }
    }
}
