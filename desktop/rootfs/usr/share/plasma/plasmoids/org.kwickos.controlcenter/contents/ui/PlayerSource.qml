import QtQuick
import org.kde.plasma.private.mpris as Mpris

Item {
    readonly property var player: model.currentPlayer
    readonly property bool active: !!player && player.playbackStatus > Mpris.PlaybackStatus.Stopped
    readonly property bool playing: !!player && player.playbackStatus === Mpris.PlaybackStatus.Playing
    readonly property string track: player ? player.track : ""
    readonly property string artist: player ? player.artist : ""
    readonly property string art: player ? player.artUrl : ""
    readonly property string identity: player ? player.identity : ""
    readonly property string appIcon: player ? player.iconName : ""

    function toggle() {
        if (!player)
            return
        if (playing)
            player.Pause()
        else
            player.Play()
    }

    function next() {
        if (player && player.canGoNext)
            player.Next()
    }

    function previous() {
        if (player && player.canGoPrevious)
            player.Previous()
    }

    Mpris.Mpris2Model {
        id: model
    }
}
