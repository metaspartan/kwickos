import QtQuick
import QtCore
import QtQuick.Layouts
import QtQuick.Dialogs

ColumnLayout {
    id: page
    spacing: 10

    property var profiles: []
    property bool loaded: false
    property var pending: ({})
    property var errors: ({})
    property var provs: ({})
    property var installs: ({})
    property string note: ""
    property bool noteBad: false

    readonly property var kinds: ({ wireguard: "WireGuard", openvpn: "OpenVPN", openconnect: "OpenConnect", vpnc: "Cisco IPsec", l2tp: "L2TP", strongswan: "IPsec", sstp: "SSTP", pptp: "PPTP", fortisslvpn: "Fortinet SSL" })
    readonly property var catalog: [
        { id: "plugins", name: "VPN plugins", blurb: "OpenVPN, OpenConnect, IPsec, L2TP and SSTP for NetworkManager", color: "#2c5aa0" },
        { id: "tailscale", name: "Tailscale", blurb: "Mesh VPN built on WireGuard", color: "#3b4252", connect: "tailscale up" },
        { id: "mullvad", name: "Mullvad VPN", blurb: "Privacy VPN with its own app", color: "#2f6fb0", open: "mullvad-vpn" },
        { id: "protonvpn", name: "Proton VPN", blurb: "Swiss privacy VPN with its own app", color: "#6d4aff", open: "protonvpn-app" },
        { id: "zerotier", name: "ZeroTier", blurb: "Virtual Ethernet networks", color: "#d98a1e", connect: "zerotier-cli info" },
        { id: "netbird", name: "NetBird", blurb: "Zero-config WireGuard mesh", color: "#e0662c", connect: "netbird up" }
    ]

    function quote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    function lastLine(out) {
        var lines = out.split("\n").filter(function (l) { return l.trim() !== "" && !/^(sudo:|pmstatus:|dlstatus:)/.test(l) })
        return lines.length ? lines[lines.length - 1].replace(/^kwick-vpn: /, "").replace(/^E: /, "") : ""
    }

    function patch(map, key, value) {
        var next = Object.assign({}, map)
        if (value === undefined)
            delete next[key]
        else
            next[key] = value
        return next
    }

    function kind(t) {
        return page.kinds[t] || (t ? t.charAt(0).toUpperCase() + t.slice(1) : "VPN")
    }

    function stateOf(p) {
        return page.pending[p.name] || p.state
    }

    function statusText(p) {
        var s = page.stateOf(p)
        if (s === "connected") return "Connected" + (p.ip ? " · " + p.ip : "")
        if (s === "connecting") return "Connecting…"
        if (s === "disconnecting") return "Disconnecting…"
        return "Not Connected"
    }

    function statusColor(p) {
        var s = page.stateOf(p)
        return s === "connected" ? Theme.good : s === "disconnected" ? Theme.faint : Theme.warn
    }

    function parseProfiles(out) {
        var list = []
        out.split("\n").forEach(function (l) {
            var f = l.split("\t")
            if (f.length >= 3 && f[0] !== "")
                list.push({ name: f[0], type: f[1], state: f[2], ip: f[3] || "" })
        })
        page.profiles = list
        page.loaded = true
    }

    function parseProvs(out) {
        var p = {}
        out.split("\n").forEach(function (l) {
            var f = l.split("\t")
            if (f.length === 2) p[f[0]] = f[1].trim()
        })
        page.provs = p
    }

    function load() {
        Sys.run("kwick-vpn list 2>/dev/null", parseProfiles)
    }

    function loadProviders() {
        Sys.run("kwick-vpn providers", parseProvs)
    }

    function toggle(p, on) {
        page.errors = page.patch(page.errors, p.name, undefined)
        page.pending = page.patch(page.pending, p.name, on ? "connecting" : "disconnecting")
        Sys.run("kwick-vpn " + (on ? "up " : "down ") + page.quote(p.name) + " 2>&1", function (out, code) {
            page.pending = page.patch(page.pending, p.name, undefined)
            if (code !== 0)
                page.errors = page.patch(page.errors, p.name, page.lastLine(out) || (on ? "Could not connect" : "Could not disconnect"))
            page.load()
        })
    }

    function importFile(path) {
        page.note = "Importing " + path.replace(/.*\//, "") + "…"
        page.noteBad = false
        Sys.run("kwick-vpn import " + page.quote(path) + " 2>&1", function (out, code) {
            page.note = code === 0 ? page.lastLine(out).replace(/^imported /, "Imported ") : page.lastLine(out)
            page.noteBad = code !== 0
            page.load()
        })
    }

    function logFile(id) {
        return "/tmp/kwick-vpn-install-" + id + ".log"
    }

    function install(id) {
        page.installs = page.patch(page.installs, id, { percent: -1, line: "Waiting for authorization…", error: "" })
        Sys.run("sh -c " + page.quote(Sys.elevated("/usr/bin/kwick-vpn install --progress " + id)) + " >" + page.logFile(id) + " 2>&1", function () {
            Sys.run("cat " + page.logFile(id) + "; kwick-vpn providers | grep -q '^" + id + "\tinstalled'", function (out, code) {
                page.installs = page.patch(page.installs, id, code === 0 ? undefined : { percent: -1, line: "", error: page.lastLine(out) || "Installation failed" })
                page.loadProviders()
            })
        })
    }

    function readProgress(id) {
        Sys.run("tail -n 40 " + page.logFile(id) + " 2>/dev/null", function (out) {
            var cur = page.installs[id]
            if (!cur || cur.error !== "")
                return
            var lines = out.split("\n")
            var percent = cur.percent
            var line = page.lastLine(out) || cur.line
            for (var i = lines.length - 1; i >= 0; i--) {
                var m = /^(pm|dl)status:[^:]*:([0-9.]+):(.*)$/.exec(lines[i])
                if (m) {
                    percent = m[1] === "dl" ? parseFloat(m[2]) * 0.4 : 40 + parseFloat(m[2]) * 0.6
                    line = m[3]
                    break
                }
            }
            page.installs = page.patch(page.installs, id, { percent: percent, line: line, error: "" })
        })
    }

    Component.onCompleted: {
        load()
        loadProviders()
    }

    Timer {
        interval: 2500
        running: true
        repeat: true
        onTriggered: page.load()
    }

    Timer {
        interval: 700
        repeat: true
        running: Object.keys(page.installs).some(function (k) { return page.installs[k].error === "" })
        onTriggered: Object.keys(page.installs).forEach(page.readProgress)
    }

    FileDialog {
        id: picker
        title: "Import VPN Configuration"
        nameFilters: ["VPN configurations (*.conf *.ovpn)", "All files (*)"]
        currentFolder: StandardPaths.writableLocation(StandardPaths.DownloadLocation)
        onAccepted: page.importFile(decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, "")))
    }

    SectionTitle { text: "VPN CONFIGURATIONS" }
    Card {
        Item {
            visible: page.loaded && page.profiles.length === 0
            Layout.fillWidth: true
            implicitHeight: empty.implicitHeight + 56
            ColumnLayout {
                id: empty
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 420)
                spacing: 6
                Image {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 6
                    source: "icons/obj-vpn.svg"
                    sourceSize.width: 112
                    sourceSize.height: 112
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: 56
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: "No VPN Configurations"
                    color: Theme.text
                    font.family: Theme.sans
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: "Import a WireGuard .conf or OpenVPN .ovpn file from your VPN provider or company. Profiles made in the network editor appear here too."
                    color: Theme.sub
                    font.family: Theme.sans
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    lineHeight: 1.15
                }
                Text {
                    Layout.fillWidth: true
                    visible: page.note !== ""
                    horizontalAlignment: Text.AlignHCenter
                    text: page.note
                    color: page.noteBad ? Theme.bad : Theme.good
                    font.family: Theme.sans
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 8
                    spacing: 8
                    Btn { text: "Network Editor…"; onClicked: Sys.run("kcmshell6 kcm_networkmanagement || nm-connection-editor || gnome-control-center network") }
                    Btn { text: "Import Configuration…"; primary: true; onClicked: picker.open() }
                }
            }
        }

        Repeater {
            model: page.profiles
            delegate: Item {
                id: vr
                required property var modelData
                readonly property string st: page.stateOf(modelData)
                readonly property bool busy: st === "connecting" || st === "disconnecting"
                readonly property string error: page.errors[modelData.name] || ""
                Layout.fillWidth: true
                implicitHeight: Math.max(58, info.implicitHeight + 22)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 16
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: 8
                        color: vr.st === "connected" ? Theme.accent : "#5a5a60"
                        Behavior on color { ColorAnimation { duration: 160 } }
                        Image { anchors.centerIn: parent; width: 19; height: 19; source: "icons/vpn.svg"; sourceSize.width: 38; sourceSize.height: 38 }
                        SequentialAnimation on opacity {
                            running: vr.busy
                            loops: Animation.Infinite
                            alwaysRunToEnd: true
                            NumberAnimation { to: 0.45; duration: 600; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
                        }
                    }

                    ColumnLayout {
                        id: info
                        Layout.fillWidth: true
                        spacing: 3
                        Text {
                            Layout.fillWidth: true
                            text: vr.modelData.name
                            color: Theme.text
                            font.family: Theme.sans
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                        RowLayout {
                            spacing: 6
                            Rectangle { width: 7; height: 7; radius: 3.5; color: page.statusColor(vr.modelData) }
                            Text {
                                text: page.statusText(vr.modelData) + "  ·  " + page.kind(vr.modelData.type)
                                color: Theme.sub
                                font.family: Theme.sans
                                font.pixelSize: 12
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: vr.error !== ""
                            text: vr.error
                            color: Theme.bad
                            font.family: Theme.sans
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }
                    }

                    Toggle {
                        checked: vr.st === "connected" || vr.st === "connecting"
                        enabled: !vr.busy
                        onToggled: function (v) { page.toggle(vr.modelData, v) }
                    }
                }

                Rectangle {
                    height: 1
                    color: Theme.line
                    anchors.left: parent.left
                    anchors.leftMargin: 60
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                }
            }
        }

        Item {
            visible: page.profiles.length > 0
            Layout.fillWidth: true
            implicitHeight: Math.max(58, foot.implicitHeight + 22)
            ColumnLayout {
                id: foot
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.right: actions.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: "Add a VPN"
                    color: Theme.text
                    font.family: Theme.sans
                    font.pixelSize: 13
                }
                Text {
                    Layout.fillWidth: true
                    text: page.note !== "" ? page.note : "WireGuard .conf or OpenVPN .ovpn files"
                    color: page.note === "" ? Theme.sub : page.noteBad ? Theme.bad : Theme.good
                    font.family: Theme.sans
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }
            RowLayout {
                id: actions
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Btn { text: "Network Editor…"; onClicked: Sys.run("kcmshell6 kcm_networkmanagement || nm-connection-editor || gnome-control-center network") }
                Btn { text: "Import Configuration…"; primary: true; onClicked: picker.open() }
            }
        }
    }

    SectionTitle { text: "PROVIDERS" }
    Card {
        Repeater {
            model: page.catalog
            delegate: Item {
                id: pr
                required property var modelData
                required property int index
                readonly property string state: page.provs[modelData.id] || "available"
                readonly property bool have: state === "installed"
                readonly property bool gone: state === "unavailable"
                readonly property var job: page.installs[modelData.id] || null
                readonly property bool running: job !== null && job.error === ""
                Layout.fillWidth: true
                implicitHeight: Math.max(64, details.implicitHeight + 24)
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 16
                    spacing: 14
                    Rectangle {
                        Layout.preferredWidth: 38
                        Layout.preferredHeight: 38
                        radius: 10
                        color: pr.modelData.color
                        opacity: pr.gone ? 0.4 : 1
                        Image { anchors.centerIn: parent; width: 22; height: 22; source: "icons/vpn.svg"; sourceSize.width: 44; sourceSize.height: 44 }
                    }
                    ColumnLayout {
                        id: details
                        Layout.fillWidth: true
                        spacing: 4
                        Text { Layout.fillWidth: true; text: pr.modelData.name; color: Theme.text; font.family: Theme.sans; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Text {
                            Layout.fillWidth: true
                            text: pr.running ? pr.job.line : pr.job ? pr.job.error : pr.have ? "Installed" : pr.gone ? "Not available on this architecture" : pr.modelData.blurb
                            color: pr.job && !pr.running ? Theme.bad : pr.have ? Theme.good : Theme.sub
                            font.family: Theme.sans
                            font.pixelSize: 12
                            elide: pr.running ? Text.ElideRight : Text.ElideNone
                            wrapMode: pr.running ? Text.NoWrap : Text.WordWrap
                        }
                        Rectangle {
                            visible: pr.running
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            implicitHeight: 4
                            radius: 2
                            color: Theme.track
                            clip: true
                            Rectangle {
                                visible: pr.running && pr.job.percent >= 0
                                height: parent.height
                                radius: 2
                                color: Theme.accent
                                width: pr.running ? parent.width * Math.min(100, Math.max(0, pr.job.percent)) / 100 : 0
                                Behavior on width { NumberAnimation { duration: 300 } }
                            }
                            Rectangle {
                                visible: pr.running && pr.job.percent < 0
                                height: parent.height
                                width: parent.width * 0.3
                                radius: 2
                                color: Theme.accent
                                NumberAnimation on x {
                                    running: pr.running && pr.job.percent < 0
                                    loops: Animation.Infinite
                                    from: -pr.width * 0.3
                                    to: pr.width
                                    duration: 1300
                                    easing.type: Easing.InOutQuad
                                }
                            }
                        }
                    }
                    Btn {
                        visible: pr.have && (pr.modelData.open !== undefined || pr.modelData.connect !== undefined)
                        text: pr.modelData.open !== undefined ? "Open" : "Connect"
                        onClicked: pr.modelData.open !== undefined ? Sys.run(pr.modelData.open) : Sys.terminal(Sys.elevated(pr.modelData.connect))
                    }
                    Btn {
                        visible: !pr.have
                        enabled: !pr.gone && !pr.running
                        text: pr.running ? "Installing…" : pr.job ? "Try Again" : "Install"
                        primary: true
                        onClicked: page.install(pr.modelData.id)
                    }
                }
                Rectangle {
                    visible: pr.index < page.catalog.length - 1
                    height: 1
                    color: Theme.line
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                }
            }
        }
    }
}
