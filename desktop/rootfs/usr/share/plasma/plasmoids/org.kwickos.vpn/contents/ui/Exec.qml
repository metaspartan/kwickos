import QtQuick
import org.kde.plasma.plasma5support as P5Support

P5Support.DataSource {
    id: exec

    property var callbacks: ({})
    property int serial: 0

    function run(cmd, cb) {
        const source = cmd + " #" + serial++
        if (cb)
            callbacks[source] = cb
        connectSource(source)
    }

    function quote(text) {
        return "'" + String(text).replace(/'/g, "'\\''") + "'"
    }

    function lastLine(text) {
        const lines = String(text).trim().split("\n")
        return lines[lines.length - 1].replace(/^kwick-vpn: /, "")
    }

    engine: "executable"
    onNewData: (source, data) => {
        disconnectSource(source)
        const cb = callbacks[source]
        delete callbacks[source]
        if (cb)
            cb(String(data["stdout"]), data["exit code"])
    }
}
