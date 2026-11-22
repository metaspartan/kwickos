import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: page
    spacing: 10

    property var inUse: ({ camera: [], microphone: [], screen: [] })
    property var perms: []
    property string secureBoot: ""
    property bool encrypted: false
    property bool fwupd: false
    property bool geoclue: false
    property string hsi: ""
    property string hsiNote: ""
    property var devices: []
    property var updates: []
    property bool fwBusy: false
    property bool fwChecked: false

    readonly property var kinds: [
        { id: "camera", name: "Camera", color: "#30d158", glyph: "camera", empty: "No app is using the camera" },
        { id: "microphone", name: "Microphone", color: "#ff9f0a", glyph: "mic", empty: "No app is using the microphone" },
        { id: "screen", name: "Screen & System Audio Recording", color: "#bf5af2", glyph: "screen", empty: "Nothing is recording or sharing the screen" }
    ]
    readonly property var tables: ({
        devices: "Camera",
        location: "Location",
        screenshot: "Screenshots",
        background: "Background activity",
        notifications: "Notifications"
    })

    function refresh() {
        Sys.run("sh " + Sys.dir + "helpers/privacy.sh", function (out) {
            var cams = []
            var mics = []
            var screens = []
            var pr = []
            var add = function (list, name) {
                if (name !== "" && list.indexOf(name) < 0)
                    list.push(name)
            }
            out.split("\n").forEach(function (l) {
                var f = l.split("|")
                if (f[0] === "camera" && f.length >= 3) add(cams, f[1])
                else if (f[0] === "use" && f.length >= 3) add(f[1] === "camera" ? cams : f[1] === "microphone" ? mics : screens, f[2])
                else if (f[0] === "secureboot") page.secureBoot = f[1]
                else if (f[0] === "encryption") page.encrypted = f[1] === "on"
                else if (f[0] === "fwupd") page.fwupd = f[1] === "yes"
                else if (f[0] === "location") page.geoclue = f[1] === "yes"
                else if (f[0] === "perm" && f.length >= 5) pr.push({ table: f[1], object: f[2], app: f[3], value: f[4] })
            })
            page.perms = pr
            page.inUse = { camera: cams, microphone: mics, screen: screens }
            if (page.fwupd && !page.fwChecked)
                page.checkFirmware()
        })
    }

    function checkFirmware() {
        page.fwChecked = true
        page.fwBusy = true
        Sys.run("fwupdmgr security --json --force 2>/dev/null", function (out) {
            try {
                var j = JSON.parse(out)
                page.hsi = j.HostSecurityId || ""
                page.hsiNote = j.Error ? j.Error.Message : ""
            } catch (e) {
                page.hsi = ""
            }
        })
        Sys.run("fwupdmgr get-devices --json 2>/dev/null", function (out) {
            var list = []
            try {
                (JSON.parse(out).Devices || []).forEach(function (d) {
                    if ((d.Flags || []).indexOf("updatable") >= 0 || d.Version)
                        list.push({ name: d.Name || "Device", vendor: d.Vendor || "", version: d.Version || "", updatable: (d.Flags || []).indexOf("updatable") >= 0 })
                })
            } catch (e) {
            }
            page.devices = list
            Sys.run("fwupdmgr get-updates --json 2>/dev/null", function (u) {
                var ups = []
                try {
                    (JSON.parse(u).Devices || []).forEach(function (d) {
                        var rel = (d.Releases || [])[0] || {}
                        ups.push({ name: d.Name || "Device", from: d.Version || "", to: rel.Version || "", summary: rel.Summary || "" })
                    })
                } catch (e) {
                }
                page.updates = ups
                page.fwBusy = false
            })
        })
    }

    function permsFor(table) {
        return page.perms.filter(function (p) { return p.table === table })
    }

    Component.onCompleted: refresh()

    Timer {
        interval: 2500
        running: true
        repeat: true
        onTriggered: page.refresh()
    }

    Text {
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        text: "See which apps are using your camera, microphone and screen right now, and control what sandboxed apps may access."
        color: Theme.sub
        font.family: Theme.sans
        font.pixelSize: 13
        wrapMode: Text.WordWrap
    }

    SectionTitle { text: "IN USE NOW" }
    Card {
        Repeater {
            model: page.kinds
            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property var apps: page.inUse[modelData.id] || []
                Layout.fillWidth: true
                implicitHeight: 60

                Rectangle {
                    id: badge
                    x: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    height: 30
                    radius: 8
                    color: row.modelData.color
                    Canvas {
                        anchors.fill: parent
                        property string glyph: row.modelData.glyph
                        onPaint: {
                            var c = getContext("2d")
                            c.reset()
                            c.strokeStyle = "#ffffff"
                            c.fillStyle = "#ffffff"
                            c.lineWidth = 1.8
                            c.lineCap = "round"
                            c.lineJoin = "round"
                            if (glyph === "camera") {
                                c.beginPath(); c.roundedRect(6, 10, 13, 10, 2.5, 2.5); c.stroke()
                                c.beginPath(); c.moveTo(19, 13.5); c.lineTo(24, 10.5); c.lineTo(24, 19.5); c.lineTo(19, 16.5); c.closePath(); c.stroke()
                            } else if (glyph === "mic") {
                                c.beginPath(); c.roundedRect(12, 6, 6, 11, 3, 3); c.stroke()
                                c.beginPath(); c.arc(15, 14, 6, 0.15 * Math.PI, 0.85 * Math.PI); c.stroke()
                                c.beginPath(); c.moveTo(15, 20); c.lineTo(15, 24); c.stroke()
                            } else {
                                c.beginPath(); c.roundedRect(6, 7, 18, 13, 2, 2); c.stroke()
                                c.beginPath(); c.moveTo(11, 24); c.lineTo(19, 24); c.stroke()
                                c.beginPath(); c.arc(15, 13.5, 2.6, 0, 2 * Math.PI); c.fill()
                            }
                        }
                    }
                }

                ColumnLayout {
                    anchors.left: badge.right
                    anchors.leftMargin: 12
                    anchors.right: state.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text { text: row.modelData.name; color: Theme.text; font.family: Theme.sans; font.pixelSize: 13 }
                    Text {
                        Layout.fillWidth: true
                        text: row.apps.length ? row.apps.join(", ") : row.modelData.empty
                        color: row.apps.length ? Theme.text : Theme.sub
                        font.family: Theme.sans
                        font.pixelSize: 12
                        font.weight: row.apps.length ? Font.Medium : Font.Normal
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    id: state
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: stateText.implicitWidth + 22
                    implicitHeight: 24
                    width: implicitWidth
                    height: implicitHeight
                    radius: 12
                    color: row.apps.length ? (row.modelData.id === "microphone" ? Theme.warnBg : Theme.goodBg) : Theme.line
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Rectangle {
                            visible: row.apps.length > 0
                            anchors.verticalCenter: parent.verticalCenter
                            width: 7
                            height: 7
                            radius: 3.5
                            color: row.modelData.id === "microphone" ? Theme.warn : Theme.good
                        }
                        Text {
                            id: stateText
                            text: row.apps.length ? "In use" : "Off"
                            color: row.apps.length ? (row.modelData.id === "microphone" ? Theme.warn : Theme.good) : Theme.sub
                            font.family: Theme.sans
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                    }
                }

                Rectangle {
                    visible: row.index < page.kinds.length - 1
                    height: 1
                    color: Theme.line
                    anchors.left: parent.left
                    anchors.leftMargin: 58
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                }
            }
        }
    }

    SectionTitle { text: "APP PERMISSIONS" }
    Card {
        Repeater {
            model: Object.keys(page.tables)
            delegate: ColumnLayout {
                id: group
                required property string modelData
                required property int index
                readonly property var rows: page.permsFor(modelData)
                Layout.fillWidth: true
                spacing: 0
                Cell {
                    title: page.tables[group.modelData]
                    subtitle: group.rows.length ? group.rows.length + (group.rows.length === 1 ? " app has asked" : " apps have asked") : "No app has asked yet"
                    last: group.rows.length === 0 && group.index === Object.keys(page.tables).length - 1
                }
                Repeater {
                    model: group.rows
                    delegate: Cell {
                        id: prow
                        required property var modelData
                        required property int index
                        readonly property bool allowed: /yes|true|1/.test(modelData.value)
                        Layout.leftMargin: 24
                        title: modelData.app !== "" ? modelData.app : "Apps without a sandbox"
                        subtitle: modelData.object !== "" && modelData.object !== modelData.table ? modelData.object : ""
                        last: index === group.rows.length - 1 && group.index === Object.keys(page.tables).length - 1
                        Toggle {
                            checked: prow.allowed
                            onToggled: value => Sys.run("flatpak permission-set '" + prow.modelData.table + "' '" + prow.modelData.object + "' '" + prow.modelData.app + "' " + (value ? "yes" : "no"), page.refresh)
                        }
                        Btn {
                            text: "Reset"
                            onClicked: Sys.run("flatpak permission-remove '" + prow.modelData.table + "' '" + prow.modelData.object + "' '" + prow.modelData.app + "'", page.refresh)
                        }
                    }
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        text: "Sandboxed (Flatpak) apps must ask through the desktop portal before using the camera, location or screenshots. Apps installed from Debian packages run without a sandbox."
        color: Theme.sub
        font.family: Theme.sans
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }

    SectionTitle { text: "SECURITY" }
    Card {
        Cell {
            title: "Secure Boot"
            subtitle: page.secureBoot === "on" ? "The firmware only starts signed boot loaders"
                    : page.secureBoot === "off" ? "Turned off in the firmware settings"
                    : page.secureBoot === "bios" ? "Not available: this computer started in legacy BIOS mode"
                    : "Status unknown"
            StatusPill { on: page.secureBoot === "on"; label: page.secureBoot === "on" ? "On" : page.secureBoot === "off" ? "Off" : page.secureBoot === "bios" ? "BIOS" : "Unknown" }
        }
        Cell {
            title: "Disk encryption"
            subtitle: page.encrypted ? "The system disk is encrypted with LUKS" : "The system disk is not encrypted. Choose encryption when installing KwickOS."
            StatusPill { on: page.encrypted; label: page.encrypted ? "On" : "Off" }
        }
        Cell {
            last: true
            title: "Device security"
            subtitle: !page.fwupd ? "Install the firmware updater to check platform security (Host Security ID)"
                    : page.hsi !== "" ? "Host Security ID " + page.hsi.split(" ")[0] + " (HSI:0 is lowest, HSI:4 highest)"
                    : page.hsiNote !== "" ? "Not measured: " + page.hsiNote
                    : "Checking…"
            StatusPill { visible: page.hsi !== ""; on: /HSI:[2-5]/.test(page.hsi); label: page.hsi.split(" ")[0] }
        }
    }

    SectionTitle { text: "FIRMWARE" }
    Card {
        Cell {
            last: page.fwupd ? page.devices.length === 0 && page.updates.length === 0 : true
            title: page.fwupd ? (page.updates.length ? page.updates.length + (page.updates.length === 1 ? " firmware update available" : " firmware updates available") : page.fwBusy ? "Checking for firmware updates…" : "Firmware is up to date") : "Firmware updates"
            subtitle: page.fwupd ? "Updates for UEFI, SSDs, docks, keyboards and other devices from the Linux Vendor Firmware Service (LVFS)" : "Install fwupd to get firmware updates from device makers through the LVFS (about 12 MB)"
            Btn {
                visible: !page.fwupd
                text: "Install"
                primary: true
                onClicked: Sys.terminal(Sys.elevated("apt-get install -y fwupd") + " && echo Done")
            }
            Btn {
                visible: page.fwupd && !page.fwBusy
                text: "Check Now"
                onClicked: Sys.terminal("fwupdmgr refresh --force; fwupdmgr get-updates")
            }
            Btn {
                visible: page.updates.length > 0
                text: "Update"
                primary: true
                onClicked: Sys.terminal("fwupdmgr update")
            }
        }
        Repeater {
            model: page.updates.length ? page.updates : page.devices
            delegate: Cell {
                required property var modelData
                required property int index
                last: index === (page.updates.length ? page.updates.length : page.devices.length) - 1
                title: modelData.name
                subtitle: page.updates.length ? (modelData.from + " → " + modelData.to + (modelData.summary ? "  ·  " + modelData.summary : "")) : ((modelData.vendor ? modelData.vendor + "  ·  " : "") + (modelData.version ? "Version " + modelData.version : ""))
            }
        }
    }

    component StatusPill: Rectangle {
        property bool on: false
        property string label
        implicitWidth: pillText.implicitWidth + 20
        implicitHeight: 24
        radius: 12
        color: on ? Theme.goodBg : Theme.line
        Text {
            id: pillText
            anchors.centerIn: parent
            text: parent.label
            color: parent.on ? Theme.good : Theme.sub
            font.family: Theme.sans
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
    }
}
