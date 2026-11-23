import QtQuick
import QtCore
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "file:///usr/share/kwick/qml/menu"

PlasmoidItem {
    id: root

    property bool nmRunning: false
    property var pending: ({})
    property var errors: ({})
    property var wants: ({})
    property var addresses: ({})
    property var seen: ({})
    property var ids: []
    property double now: Date.now()
    property string notice: ""
    property bool noticeBad: false

    readonly property bool useNm: nm.item !== null && nmRunning
    readonly property var backend: useNm ? nm.item : shell
    readonly property var profiles: backend.profiles
    readonly property var kinds: ({ wireguard: "WireGuard", openvpn: "OpenVPN", openconnect: "OpenConnect", vpnc: "Cisco IPsec", l2tp: "L2TP", strongswan: "IPsec", sstp: "SSTP", pptp: "PPTP", fortisslvpn: "Fortinet SSL" })
    readonly property var states: profiles.map(p => statusOf(p))
    readonly property string status: states.some(s => s === "connecting" || s === "disconnecting") ? "connecting" : states.indexOf("connected") >= 0 ? "connected" : "disconnected"
    readonly property string iconName: "network-vpn" + (status === "connected" ? "" : status === "connecting" ? "-acquiring" : "-disconnected") + "-symbolic"
    readonly property bool inTray: (Plasmoid.containmentDisplayHints & PlasmaCore.Types.ContainmentDrawsPlasmoidHeading) !== 0

    function statusOf(p) {
        return pending[p.id] ? pending[p.id].target : p.state
    }

    function profile(id) {
        return profiles.find(p => p.id === id) || { id: id, name: "", type: "", state: "disconnected", ip: "", since: 0 }
    }

    function kind(type) {
        return kinds[type] || (type ? type.charAt(0).toUpperCase() + type.slice(1) : "VPN")
    }

    function clock(ms) {
        const t = Math.max(0, Math.floor((now - ms) / 1000))
        const pad = n => (n < 10 ? "0" : "") + n
        return Math.floor(t / 3600) + ":" + pad(Math.floor(t / 60) % 60) + ":" + pad(t % 60)
    }

    function detail(p) {
        switch (statusOf(p)) {
        case "connected": return "Connected · " + clock(p.since || seen[p.id] || now)
        case "connecting": return "Connecting…"
        case "disconnecting": return "Disconnecting…"
        default: return kind(p.type)
        }
    }

    function address(p) {
        if (p.state !== "connected")
            return ""
        return p.ip || addresses[p.id] || ""
    }

    function patch(map, key, value) {
        const next = Object.assign({}, map)
        if (value === undefined)
            delete next[key]
        else
            next[key] = value
        return next
    }

    function setActive(id, on) {
        errors = patch(errors, id, undefined)
        pending = patch(pending, id, { target: on ? "connecting" : "disconnecting", from: profile(id).state, wanted: on })
        wants = patch(wants, id, on)
        exec.run("kwick-vpn " + (on ? "up " : "down ") + exec.quote(id) + " 2>&1", (out, code) => {
            if (code !== 0 && wants[id] === on)
                fail(id, exec.lastLine(out))
            if (!useNm)
                shell.refresh()
        })
    }

    function fail(id, message) {
        pending = patch(pending, id, undefined)
        errors = patch(errors, id, message || "Could not connect")
    }

    function lookupAddress(id) {
        addresses = patch(addresses, id, "")
        exec.run("nmcli -g IP4.ADDRESS connection show uuid " + exec.quote(id) + " 2>/dev/null", out => {
            addresses = patch(addresses, id, out.trim().split(/[ |]+/)[0].replace(/\/.*/, ""))
        })
    }

    function track() {
        const next = profiles.map(p => p.id)
        if (next.join("\n") !== ids.join("\n"))
            ids = next
        let pend = pending
        let since = seen
        let addr = addresses
        profiles.forEach(p => {
            const w = pend[p.id]
            if (w && p.state !== w.from) {
                pend = patch(pend, p.id, undefined)
                if (w.wanted && p.state === "disconnected" && !errors[p.id])
                    errors = patch(errors, p.id, "Could not connect")
            }
            if (p.state === "connected") {
                if (!since[p.id])
                    since = patch(since, p.id, Date.now())
                if (!p.ip && addr[p.id] === undefined)
                    Qt.callLater(lookupAddress, p.id)
            } else {
                since = patch(since, p.id, undefined)
                addr = patch(addr, p.id, undefined)
            }
        })
        pending = pend
        seen = since
        addresses = addr
    }

    function openSettings() {
        root.expanded = false
        exec.run("kwick-settings vpn >/dev/null 2>&1 &")
    }

    function importFile(path) {
        notice = "Importing " + path.replace(/.*\//, "") + "…"
        noticeBad = false
        exec.run("kwick-vpn import " + exec.quote(path) + " 2>&1", (out, code) => {
            notice = code === 0 ? exec.lastLine(out).replace(/^imported /, "Imported ") : exec.lastLine(out)
            noticeBad = code !== 0
            root.expanded = true
            if (!root.useNm)
                shell.refresh()
        })
    }

    onProfilesChanged: track()
    onExpandedChanged: {
        if (expanded) {
            nmCheck.restart()
            if (!useNm)
                shell.refresh()
        } else if (!noticeBad) {
            notice = ""
        }
    }

    Plasmoid.status: profiles.length > 0 ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.HiddenStatus
    Plasmoid.icon: iconName
    Plasmoid.title: "VPN"
    toolTipMainText: "VPN"
    toolTipSubText: {
        const on = profiles.filter(p => statusOf(p) === "connected").map(p => p.name)
        const wait = profiles.filter(p => statusOf(p) === "connecting").map(p => p.name)
        if (wait.length)
            return "Connecting to " + wait[0] + "…"
        return on.length ? "Connected to " + on.join(", ") : "Not Connected"
    }

    PlasmaCore.Action {
        id: settingsAction
        text: "VPN Settings…"
        icon.name: "configure"
        onTriggered: root.openSettings()
    }

    Component.onCompleted: Plasmoid.setInternalAction("configure", settingsAction)

    Exec {
        id: exec
    }

    Loader {
        id: nm
        source: "NmBackend.qml"
    }

    ShellBackend {
        id: shell
        exec: exec
        active: !root.useNm
        watching: root.expanded
    }

    Timer {
        id: nmCheck
        interval: root.expanded ? (root.nmRunning ? 30000 : 4000) : 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: exec.run("nmcli -t -f RUNNING general 2>/dev/null", out => root.nmRunning = out.trim() === "running")
    }

    Timer {
        interval: 1000
        running: root.expanded && root.status !== "disconnected"
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }

    FileDialog {
        id: picker
        title: "Import VPN Configuration"
        nameFilters: ["VPN configurations (*.conf *.ovpn)", "All files (*)"]
        currentFolder: StandardPaths.writableLocation(StandardPaths.DownloadLocation)
        onAccepted: root.importFile(decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, "")))
    }

    compactRepresentation: MouseArea {
        id: compact
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        Kirigami.Icon {
            anchors.fill: parent
            source: root.iconName
            fallback: "network-vpn-symbolic"
            active: compact.containsMouse

            SequentialAnimation on opacity {
                running: root.status === "connecting"
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 0.45; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
            }
        }
    }

    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 17
        Layout.preferredWidth: Layout.minimumWidth
        Layout.maximumWidth: Layout.minimumWidth
        Layout.minimumHeight: menu.implicitHeight
        Layout.preferredHeight: menu.implicitHeight
        Layout.maximumHeight: menu.implicitHeight

        ColumnLayout {
            id: menu
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 0

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.topMargin: 2
                Layout.bottomMargin: 4
                visible: !root.inTray
                text: "VPN"
                font.weight: Font.Bold
            }

            Repeater {
                model: root.ids
                delegate: ProfileRow {
                    required property string modelData
                    readonly property var profile: root.profile(modelData)
                    name: profile.name
                    status: root.statusOf(profile)
                    detail: root.detail(profile)
                    address: root.address(profile)
                    error: root.errors[modelData] || ""
                    onToggled: on => root.setActive(modelData, on)
                }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.margins: 10
                visible: root.ids.length === 0
                text: "No VPN Configurations"
                opacity: 0.55
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                Layout.topMargin: 4
                visible: root.notice !== ""
                text: root.notice
                color: root.noticeBad ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                opacity: root.noticeBad ? 1 : 0.7
                font: Kirigami.Theme.smallFont
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                Layout.topMargin: 5
                Layout.bottomMargin: 5
                implicitHeight: 1
                color: Kirigami.Theme.textColor
                opacity: 0.12
            }

            MenuRow {
                text: "Import Configuration…"
                onClicked: {
                    root.expanded = false
                    picker.open()
                }
            }

            MenuRow {
                text: "VPN Settings…"
                onClicked: root.openSettings()
            }
        }
    }
}
