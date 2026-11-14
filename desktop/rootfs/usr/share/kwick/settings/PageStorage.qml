import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: page
    spacing: 10

    property bool available: true
    property var mods: ({})
    property var disks: []
    property var pools: []
    property var shares: []
    property string webUrl: ""
    property string webState: ""
    readonly property var catalog: [
        { id: "zfs", name: "OpenZFS", color: "#2c5aa0" },
        { id: "array", name: "Parity array (mergerfs + SnapRAID)", color: "#ff9f0a" },
        { id: "raid", name: "mdadm RAID and LVM", color: "#5e5ce6" },
        { id: "btrfs", name: "Btrfs and snapper", color: "#30b0c7" },
        { id: "shares", name: "SMB and NFS shares", color: "#34c759" },
        { id: "iscsi", name: "iSCSI target", color: "#8e8e93" },
        { id: "smart", name: "Disk health and spindown", color: "#ff453a" },
        { id: "ups", name: "UPS (NUT)", color: "#ffd60a" },
        { id: "containers", name: "Docker and Podman", color: "#0a84ff" },
        { id: "vms", name: "Virtual machines", color: "#bf5af2" },
        { id: "webui", name: "Cockpit web console", color: "#32ade6" }
    ]

    function healthColor(h) {
        var s = (h || "").toUpperCase()
        if (s === "ONLINE" || s === "ACTIVE" || s === "PROTECTED") return Theme.good
        if (s === "DEGRADED" || s === "UNPROTECTED") return Theme.warn
        return Theme.bad
    }

    function load() {
        Sys.run("sh " + Sys.dir + "helpers/storage.sh", function (out) {
            var m = {}
            var d = []
            var p = []
            var s = []
            var url = ""
            var ws = ""
            out.split("\n").forEach(function (l) {
                var f = l.split("|")
                if (f[0] === "disk" && f.length >= 6)
                    d.push({ name: f[1], size: f[2], model: f[3], kind: f[4], use: f[5] })
                else if (f[0] === "zpool" && f.length >= 5)
                    p.push({ kind: "ZFS pool", name: f[1], detail: f[3] + " of " + f[2] + " used", health: f[4] })
                else if (f[0] === "md" && f.length >= 5)
                    p.push({ kind: "RAID " + f[2].replace("raid", ""), name: f[1], detail: f[4] + " blocks", health: f[3] })
                else if (f[0] === "array" && f.length >= 6)
                    p.push({ kind: "Parity array", name: f[1], detail: f[3] + " of " + f[2] + " used, " + f[4] + " data, " + f[5] + " parity", health: parseInt(f[5]) > 0 ? "protected" : "unprotected" })
                else if (f[0] === "share" && f.length >= 4)
                    s.push({ proto: f[1].toUpperCase(), name: f[2], path: f[3] })
                else if (f[0] === "console" && f.length >= 3) {
                    url = f[1]
                    ws = f[2]
                } else if (f.length >= 4)
                    m[f[0]] = { state: f[1], desc: f[2], note: f[3] }
            })
            page.available = out.trim() !== ""
            page.mods = m
            page.disks = d
            page.pools = p
            page.shares = s
            page.webUrl = url
            page.webState = ws
        })
    }

    function act(verb, id) {
        Sys.terminal(Sys.elevated("/usr/bin/kwick-storage " + verb + " " + id))
        refreshTimer.restart()
    }

    Component.onCompleted: load()

    Timer {
        id: refreshTimer
        interval: 5000
        onTriggered: page.load()
    }

    Card {
        visible: !page.available
        Cell {
            last: true
            title: "kwick-storage is not installed"
            subtitle: "Install it with: sudo apt install kwick-storage"
            Btn { text: "Install"; primary: true; onClicked: { Sys.terminal(Sys.elevated("apt-get install -y kwick-storage")); refreshTimer.restart() } }
        }
    }

    SectionTitle { text: "DISKS" }
    Card {
        Cell {
            visible: page.disks.length === 0
            last: true
            title: "No disks found"
        }
        Repeater {
            model: page.disks
            delegate: Item {
                id: dr
                required property var modelData
                required property int index
                Layout.fillWidth: true
                implicitHeight: 56
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 16
                    spacing: 14
                    Rectangle {
                        width: 34
                        height: 34
                        radius: 9
                        color: dr.modelData.kind === "hdd" ? "#8e8e93" : dr.modelData.kind === "nvme" ? "#30b0c7" : "#5e5ce6"
                        Image { anchors.centerIn: parent; width: 20; height: 20; source: "icons/storage.svg"; sourceSize.width: 40; sourceSize.height: 40 }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text { Layout.fillWidth: true; text: dr.modelData.name + "  " + dr.modelData.model; color: Theme.text; font.family: Theme.sans; font.pixelSize: 13; elide: Text.ElideRight }
                        Text { Layout.fillWidth: true; text: dr.modelData.kind.toUpperCase() + "  •  " + dr.modelData.use; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 12; elide: Text.ElideRight }
                    }
                    Text { text: dr.modelData.size; color: Theme.text; font.family: Theme.mono; font.pixelSize: 13 }
                }
                Rectangle {
                    visible: dr.index < page.disks.length - 1
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

    SectionTitle { text: "POOLS AND ARRAYS" }
    Card {
        Cell {
            visible: page.pools.length === 0
            last: true
            title: "No pools or arrays yet"
            subtitle: "kwick-storage pool create, array setup or raid create, or use Cockpit"
        }
        Repeater {
            model: page.pools
            delegate: Cell {
                required property var modelData
                required property int index
                last: index === page.pools.length - 1
                title: modelData.kind + "  " + modelData.name
                subtitle: modelData.detail
                Rectangle { width: 8; height: 8; radius: 4; color: page.healthColor(modelData.health) }
                Text { text: modelData.health; color: page.healthColor(modelData.health); font.family: Theme.sans; font.pixelSize: 12 }
            }
        }
    }

    SectionTitle { text: "SHARES"; visible: page.shares.length > 0 }
    Card {
        visible: page.shares.length > 0
        Repeater {
            model: page.shares
            delegate: Cell {
                required property var modelData
                required property int index
                last: index === page.shares.length - 1
                title: modelData.proto + "  " + modelData.name
                subtitle: modelData.path
            }
        }
    }

    SectionTitle { text: "WEB CONSOLE" }
    Card {
        Cell {
            last: true
            title: "Cockpit"
            subtitle: page.webUrl !== "" ? page.webUrl + (page.webState === "active" ? "" : "  (not running)") : "Install the Cockpit web console module below to manage this machine from a browser"
            Btn {
                text: "Open Cockpit"
                primary: true
                enabled: page.webUrl !== ""
                onClicked: Sys.run("xdg-open https://localhost:9090")
            }
        }
    }

    SectionTitle { text: "STORAGE MODULES" }
    Card {
        Repeater {
            model: page.catalog
            delegate: Item {
                id: gr
                required property var modelData
                required property int index
                readonly property var info: page.mods[modelData.id] || ({ state: "no", desc: "", note: "" })
                readonly property bool have: info.state === "yes"
                readonly property bool part: info.state === "part"
                readonly property bool gone: info.state === "na"
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
                        color: gr.modelData.color
                        opacity: gr.gone ? 0.4 : 1
                        Image { anchors.centerIn: parent; width: 22; height: 22; source: "icons/storage.svg"; sourceSize.width: 44; sourceSize.height: 44 }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text { Layout.fillWidth: true; text: gr.modelData.name; color: Theme.text; font.family: Theme.sans; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Text {
                            Layout.fillWidth: true
                            text: gr.have ? "Installed" : gr.part ? "Partly installed" : gr.gone ? "Unavailable: " + gr.info.note : gr.info.desc
                            color: gr.have ? Theme.good : gr.part ? Theme.accent : Theme.sub
                            font.family: Theme.sans
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }
                    Btn { visible: gr.have || gr.part; text: "Remove"; danger: true; onClicked: page.act("remove", gr.modelData.id) }
                    Btn { visible: !gr.have; enabled: !gr.gone && page.available; text: gr.part ? "Repair" : "Install"; primary: true; onClicked: page.act("install", gr.modelData.id) }
                }
                Rectangle {
                    visible: gr.index < page.catalog.length - 1
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

    Btn { Layout.alignment: Qt.AlignRight; text: "Refresh status"; onClicked: page.load() }
}
