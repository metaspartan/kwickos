import QtQuick
import org.kde.plasma.private.volume

QtObject {
    readonly property var sink: PreferredDevice.sink
    readonly property bool available: !!sink && sink.name !== "auto_null"
    readonly property real value: available ? sink.volume / PulseAudio.NormalVolume : 0
    readonly property bool muted: available && sink.muted
    readonly property string device: available ? sink.description : ""
    readonly property string icon: !available || muted || value <= 0 ? "audio-volume-muted-symbolic" : value < 0.34 ? "audio-volume-low-symbolic" : value < 0.67 ? "audio-volume-medium-symbolic" : "audio-volume-high-symbolic"

    function setValue(v) {
        if (!available)
            return
        sink.volume = Math.round(Math.max(0, Math.min(1, v)) * PulseAudio.NormalVolume)
        if (sink.muted && v > 0)
            sink.muted = false
    }

    function toggleMute() {
        if (available)
            sink.muted = !sink.muted
    }
}
