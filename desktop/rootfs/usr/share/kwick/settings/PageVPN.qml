import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs

ColumnLayout {
    id: page
    spacing: 10

    property var conns: []
    property var provs: ({})
    property string note: ""
    property bool noteBad: false

    readonly property var catalog: [
        { id: "tailscale", name: "Tailscale", blurb: "Mesh VPN built on WireGuard", color: "#3b4252", connect: "tailscale up" },
        { id: "mullvad", name: "Mullvad VPN", blurb: "Privacy VPN with its own app", color: "#2f6fb0", open: "mullvad-vpn" },
        { id: "protonvpn", name: "Proton VPN", blurb: "Swiss privacy VPN with its own app", color: "#6d4aff", open: "protonvpn-app" },
        { id: "zerotier", name: "ZeroTier", blurb: "Virtual Ethernet networks", color: "#d98a1e", connect: "zerotier-cli info" },
        { id: "netbird", name: "NetBird", blurb: "Zero-config WireGuard mesh", color: "#e0662c", connect: "netbird up" }
    ]

    function quote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    function parseConns(out) {
        var list = []
        out.split("\n").forEach(function (l) {
            var m = /^(.*):([^:]*):([^:]*)$/.exec(l)
            if (!m) return
            var type = m[2]
            if (type !== "vpn" && type !== "wireguard") return
            list.push({ name: m[1].replace(/\\:/g, ":"), type: type, active: m[3] === "yes" })
        })
        page.conns = list
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
        Sys.run("nmcli -t -f NAME,TYPE,ACTIVE con show", parseConns)
        Sys.run("kwick-vpn providers", parseProvs)
    }

    function toggle(name, on) {
        page.note = (on ? "Connecting " : "Disconnecting ") + name + "…"
        page.noteBad = false
        Sys.run("kwick-vpn " + (on ? "up " : "down ") + page.quote(name) + " 2>&1", function (out, code) {
            page.note = code === 0 ? "" : out.trim().split("\n").slice(-1)[0]
            page.noteBad = code !== 0
            page.load()
        })
    }

    function importFile(path) {
        page.note = "Importing…"
        page.noteBad = false
        Sys.run("kwick-vpn import " + page.quote(path) + " 2>&1", function (out, code) {
            page.note = out.trim().split("\n").slice(-1)[0]
            page.noteBad = code !== 0
            page.load()
        })
    }

    function install(id) {
        Sys.terminal(Sys.elevated("/usr/bin/kwick-vpn install " + id))
        refreshTimer.restart()
    }

    Component.onCompleted: load()

    Timer {
        id: refreshTimer
        interval: 4000
        onTriggered: page.load()
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: page.load()
    }

    FileDialog {
        id: picker
        title: "Import VPN configuration"
        nameFilters: ["VPN profiles (*.conf *.ovpn)", "All files (*)"]
        onAccepted: page.importFile(selectedFile.toString().replace(/^file:\/\//, ""))
    }

    SectionTitle { text: "CONNECTIONS" }
    Card {
        Repeater {
            model: page.conns
            delegate: Cell {
                required property var modelData
                required property int index
                last: false
                title: modelData.name
                subtitle: (modelData.type === "wireguard" ? "WireGuard" : "VPN plugin") + (modelData.active ? " · connected" : "")
                Toggle {
                    checked: modelData.active
                    onToggled: function (v) { page.toggle(modelData.name, v) }
                }
            }
        }
        Cell {
            visible: page.conns.length === 0
            last: false
            title: "No VPN connections yet"
            subtitle: "Import a WireGuard or OpenVPN profile, or add one in the network applet"
        }
        Cell {
            last: true
            title: "Import configuration…"
            subtitle: page.note !== "" ? page.note : "WireGuard .conf or OpenVPN .ovpn files"
            titleColor: Theme.text
            Btn { text: "Network editor"; onClicked: Sys.run("kcmshell6 kcm_networkmanagement || gnome-control-center network") }
            Btn { text: "Import…"; primary: true; onClicked: picker.open() }
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
                Layout.fillWidth: true
                implicitHeight: 64
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 16
                    spacing: 14
                    Rectangle {
                        width: 38
                        height: 38
                        radius: 10
                        color: pr.modelData.color
                        opacity: pr.gone ? 0.4 : 1
                        Image { anchors.centerIn: parent; width: 22; height: 22; source: "icons/vpn.svg"; sourceSize.width: 44; sourceSize.height: 44 }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text { Layout.fillWidth: true; text: pr.modelData.name; color: Theme.text; font.family: Theme.sans; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Text {
                            Layout.fillWidth: true
                            text: pr.have ? "Installed" : pr.gone ? "Not available on this architecture" : pr.modelData.blurb
                            color: pr.have ? Theme.good : Theme.sub
                            font.family: Theme.sans
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }
                    Btn {
                        visible: pr.have && (pr.modelData.open !== undefined || pr.modelData.connect !== undefined)
                        text: pr.modelData.open !== undefined ? "Open" : "Connect"
                        onClicked: pr.modelData.open !== undefined ? Sys.run(pr.modelData.open) : Sys.terminal(Sys.elevated(pr.modelData.connect))
                    }
                    Btn { visible: !pr.have; enabled: !pr.gone; text: "Install"; primary: true; onClicked: page.install(pr.modelData.id) }
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

    Btn { Layout.alignment: Qt.AlignRight; text: "Refresh"; onClicked: page.load() }
}
