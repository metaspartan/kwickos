import QtQuick

Item {
    id: shell

    required property var exec
    property bool active: false
    property var profiles: []

    function refresh() {
        exec.run("kwick-vpn list 2>/dev/null", out => {
            profiles = out.split("\n").filter(l => l.indexOf("\t") > 0).map(l => {
                const f = l.split("\t")
                return { id: f[0], name: f[0], type: f[1], state: f[2], ip: f[3] || "", since: 0 }
            })
        })
    }

    Timer {
        interval: 3000
        running: shell.active
        repeat: true
        triggeredOnStart: true
        onTriggered: shell.refresh()
    }
}
