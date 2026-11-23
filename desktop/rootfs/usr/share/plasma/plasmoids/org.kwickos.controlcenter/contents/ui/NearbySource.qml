import QtQuick
import org.kde.plasma.plasma5support as P5Support

Item {
    id: source

    property bool available: false
    property string mode: "off"
    property int minutesLeft: 0
    property int known: 0
    property bool watching: false
    readonly property bool on: mode !== "off"
    readonly property string subtitle: !available ? "" : mode === "everyone" ? "Everyone · " + minutesLeft + " min" : mode === "contacts" ? "Known Devices" : "Receiving Off"
    readonly property string statusCommand: "kwick-nearby --status"
    property string statusSource: ""

    function refresh() {
        if (statusSource)
            status.disconnectSource(statusSource)
        statusSource = statusCommand + " #" + Date.now()
        status.connectSource(statusSource)
    }

    function setMode(m) {
        mode = m
        if (m === "everyone")
            minutesLeft = 10
        run.connectSource("kwick-nearby --set visibility " + m + " #" + Date.now())
    }

    function toggle() {
        setMode(on ? "off" : "everyone")
    }

    P5Support.DataSource {
        id: status
        engine: "executable"
        interval: source.watching ? 15000 : 0
        onNewData: (src, data) => {
            if (src !== source.statusSource)
                return
            const out = String(data["stdout"] || "").trim()
            if (data["exit code"] !== 0 || out === "") {
                source.available = false
                return
            }
            try {
                const s = JSON.parse(out)
                source.available = true
                source.mode = s.effective || "off"
                source.minutesLeft = s.minutesLeft || 0
                source.known = (s.known || []).length
            } catch (e) {
                source.available = false
            }
        }
    }

    P5Support.DataSource {
        id: run
        engine: "executable"
        onNewData: src => {
            disconnectSource(src)
            source.refresh()
        }
    }

    onWatchingChanged: {
        if (!watching && statusSource) {
            status.disconnectSource(statusSource)
            statusSource = ""
        }
    }
    Component.onCompleted: refresh()
}
