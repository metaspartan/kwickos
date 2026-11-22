import QtQuick
import QtMultimedia

Item {
    id: view
    required property var theme
    readonly property bool video: ql.kind === "video"

    function clock(ms) {
        const s = Math.max(0, Math.floor(ms / 1000))
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        const r = s % 60
        return (h > 0 ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (r < 10 ? "0" : "") + r
    }

    Rectangle {
        anchors.fill: parent
        color: view.video ? "#000000" : view.theme.window
    }

    MediaPlayer {
        id: player
        source: ql.url
        videoOutput: output
        audioOutput: AudioOutput {}
        onSourceChanged: play()
        Component.onCompleted: play()
    }

    VideoOutput {
        id: output
        anchors.fill: parent
        visible: view.video
        fillMode: VideoOutput.PreserveAspectFit
    }

    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -24
        spacing: 14
        visible: !view.video
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 128
            height: 128
            sourceSize: Qt.size(256, 256)
            source: "image://icon/" + ql.iconName
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: player.metaData.stringValue(MediaMetaData.Title) || ql.name
            color: view.theme.label
            font.family: view.theme.sans
            font.pixelSize: 16
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: player.metaData.stringValue(MediaMetaData.ContributingArtist) || player.metaData.stringValue(MediaMetaData.AlbumArtist) || ""
            visible: text !== ""
            color: view.theme.secondary
            font.family: view.theme.sans
            font.pixelSize: 13
            renderType: Text.NativeRendering
        }
    }

    Text {
        anchors.centerIn: parent
        visible: player.error !== MediaPlayer.NoError
        text: "This file can't be played"
        color: view.video ? "#bbbbbb" : view.theme.secondary
        font.family: view.theme.sans
        font.pixelSize: 14
    }

    Rectangle {
        id: controls
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        width: Math.min(parent.width - 40, 520)
        height: 44
        radius: 22
        opacity: !view.video || hoverWatch.hovered || player.playbackState !== MediaPlayer.PlayingState ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        color: view.theme.dark || view.video ? Qt.rgba(0.16, 0.16, 0.17, 0.88) : Qt.rgba(1, 1, 1, 0.94)
        border.width: 1
        border.color: view.theme.dark || view.video ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.1)
        readonly property color fg: view.theme.dark || view.video ? "#ffffff" : "#1d1d1f"

        Image {
            id: playIcon
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            height: 20
            sourceSize: Qt.size(40, 40)
            source: view.theme.glyph(player.playbackState === MediaPlayer.PlayingState ? "pause" : "play", controls.fg)
            MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                cursorShape: Qt.PointingHandCursor
                onClicked: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
            }
        }

        Text {
            id: elapsed
            anchors.left: playIcon.right
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: view.clock(player.position)
            color: controls.fg
            font.family: view.theme.sans
            font.pixelSize: 11
            font.features: { "tnum": 1 }
            renderType: Text.NativeRendering
        }

        Item {
            id: track
            anchors.left: elapsed.right
            anchors.leftMargin: 10
            anchors.right: total.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            height: 16
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 4
                radius: 2
                color: Qt.rgba(controls.fg.r, controls.fg.g, controls.fg.b, 0.25)
                Rectangle {
                    width: player.duration > 0 ? parent.width * player.position / player.duration : 0
                    height: parent.height
                    radius: 2
                    color: controls.fg
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                function seek(x) {
                    if (player.duration > 0)
                        player.position = Math.max(0, Math.min(1, x / width)) * player.duration
                }
                onPressed: mouse => seek(mouse.x)
                onPositionChanged: mouse => seek(mouse.x)
            }
        }

        Text {
            id: total
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: view.clock(player.duration)
            color: controls.fg
            font.family: view.theme.sans
            font.pixelSize: 11
            font.features: { "tnum": 1 }
            renderType: Text.NativeRendering
        }
    }

    HoverHandler {
        id: hoverWatch
    }

    TapHandler {
        enabled: view.video
        onTapped: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
        onDoubleTapped: ql.toggleFullScreen()
    }

    Connections {
        target: ql
        function onShownChanged() {
            if (!ql.shown)
                player.stop()
        }
    }
}
