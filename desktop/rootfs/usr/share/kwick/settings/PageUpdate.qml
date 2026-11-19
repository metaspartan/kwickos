import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: page
    spacing: 10

    readonly property string tool: "/usr/sbin/kwick-update"
    property var st: ({})
    property var kern: ({})
    property string access: "none"
    property bool loaded: false
    property bool available: true
    property bool authWait: false
    property bool wasBusy: false
    property bool autoChecked: false
    property string note: ""
    property bool showLog: false
    property string logText: ""
    property var open: ({})
    property var action: null

    readonly property bool busy: !!(st.job && st.job.running)
    readonly property var updates: st.updates || []
    readonly property var system: updates.filter(function (u) { return u.kind === "system" })
    readonly property var apps: updates.filter(function (u) { return u.kind === "apps" })
    readonly property int security: system.filter(function (u) { return u.security }).length
    readonly property bool hasUpdates: updates.length > 0 || !!st.release_available
    readonly property var auto: st.auto || ({})
    readonly property var kernels: kern.installed || []
    readonly property var offered: (kern.available || []).filter(function (k) { return !k.installed && (String(kern.running).indexOf(k.flavor + "-") === 0 || kernels.some(function (i) { return i.flavor === k.flavor })) })
    readonly property bool canTry: ["efistub", "grub", "systemd-boot", "uboot"].indexOf(kern.boot) >= 0
    readonly property bool restartNeeded: !!kern.trial || (!!kern.default && kern.default !== kern.running)
    readonly property var flavors: ({ generic: "Generic", virt: "Virtual", k1: "SpacemiT K1", k1mainline: "K1 Mainline", gb10: "GB10", rpi: "Raspberry Pi", apple: "Apple Silicon" })
    readonly property var bootNames: ({ efistub: "UEFI, no boot loader", grub: "GRUB", "systemd-boot": "systemd-boot", uboot: "U-Boot", rpi: "Raspberry Pi firmware", apple: "Apple Silicon boot", none: "Direct kernel boot" })

    function q(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    function bytes(n) {
        if (!n) return ""
        if (n >= 1e9) return (n / 1e9).toFixed(1) + " GB"
        if (n >= 1e6) return (n / 1e6).toFixed(1) + " MB"
        if (n >= 1e3) return Math.round(n / 1e3) + " KB"
        return n + " bytes"
    }

    function total(list) {
        return list.reduce(function (a, u) { return a + (u.size || 0) }, 0)
    }

    function plural(n, one, many) {
        return n + " " + (n === 1 ? one : many)
    }

    function summary(list, extra) {
        var parts = [page.plural(list.length, "update", "updates")]
        var b = page.bytes(page.total(list))
        if (b !== "") parts.push(b)
        if (extra) parts.push(extra)
        return parts.join(" · ")
    }

    function when(t) {
        if (!t) return "never"
        var d = new Date(t * 1000)
        var n = new Date()
        var time = Qt.formatTime(d, "h:mm AP")
        var y = new Date(n.getFullYear(), n.getMonth(), n.getDate() - 1)
        if (d.toDateString() === n.toDateString()) return "today at " + time
        if (d.toDateString() === y.toDateString()) return "yesterday at " + time
        return Qt.formatDate(d, "MMM d") + " at " + time
    }

    function kname(id) {
        if (!id) return ""
        var i = id.indexOf("-")
        var fl = id.slice(0, i)
        return "Linux " + id.slice(i + 1) + " (" + (page.flavors[fl] || fl) + ")"
    }

    function autoText() {
        if (!page.auto.check) return "Off"
        var parts = []
        if (page.auto.system) parts.push("system")
        if (page.auto.apps) parts.push("app")
        if (page.auto.security && !page.auto.system) parts.push("security")
        if (parts.length) return "Install " + parts.join(" and ") + " updates"
        return page.auto.download ? "Download only" : "Check only"
    }

    function jobTitle() {
        var k = page.st.job ? page.st.job.kind : ""
        if (k === "check") return "Checking for Updates…"
        if (k === "download") return "Downloading Updates…"
        if (k === "kernel") return "Updating Kernels…"
        return "Installing Updates…"
    }

    function lastLine(out) {
        var l = out.split("\n").filter(function (x) { return x.trim() !== "" && !/^(sudo:|__rc)/.test(x) })
        return l.length ? l[l.length - 1].replace(/^kwick-(update|kernel): /, "") : ""
    }

    function parse(out) {
        var s = Sys.sections(out)
        if (s.status !== undefined) {
            try {
                page.st = JSON.parse(s.status.join(""))
                page.available = true
            } catch (e) {
                page.available = false
            }
        }
        if (s.kernel && s.kernel.length) {
            try { page.kern = JSON.parse(s.kernel.join("")) } catch (e2) { }
        }
        if (s.status === undefined) return
        if (s.access && s.access.length) page.access = s.access[0].trim()
        page.loaded = true
        if (page.wasBusy && !page.busy) load(true)
        page.wasBusy = page.busy
        if (!page.autoChecked && s.access !== undefined) {
            page.autoChecked = true
            var stale = Date.now() / 1000 - (page.st.checked || 0) > 6 * 3600
            if (page.available && stale && !page.busy && page.access !== "none") page.check()
        }
    }

    function load(all) {
        Sys.run("sh " + Sys.dir + "helpers/update.sh" + (all ? "" : " status"), page.parse)
    }

    function priv(args, cb) {
        page.note = ""
        page.authWait = true
        Sys.run(Sys.elevated(page.tool + " " + args), function (out, code) {
            page.authWait = false
            if (code === 126 || code === 127) page.note = "Authorization was cancelled."
            else if (code !== 0 && !page.busy) page.note = page.lastLine(out)
            page.load(true)
            if (cb) cb(code)
        })
    }

    function check() { page.priv("check") }
    function upgrade(what) { page.priv("upgrade " + what) }
    function kernel(args) { page.priv("kernel " + args) }

    function setAuto(key, on) {
        var a = Object.assign({}, page.auto)
        a[key] = on
        page.st = Object.assign({}, page.st, { auto: a })
        page.priv("auto set " + key + " " + (on ? "on" : "off"))
    }

    function setEvery(h) {
        var a = Object.assign({}, page.auto)
        a.interval = h
        page.st = Object.assign({}, page.st, { auto: a })
        page.priv("auto interval " + h)
    }

    function toggle(key) {
        page.open = Object.assign({}, page.open, { [key]: !page.open[key] })
    }

    function ask(o) {
        page.action = o.run
        confirm.title = o.title
        confirm.body = o.body
        confirm.confirmText = o.ok
        confirm.danger = !!o.danger
        confirm.open()
    }

    function restart() {
        Sys.run("dbus-send --session --print-reply --type=method_call --dest=org.kde.Shutdown /Shutdown org.kde.Shutdown.logoutAndReboot || gnome-session-quit --reboot --no-prompt || " + Sys.elevated("reboot"))
    }

    function readLog() {
        Sys.run(page.tool + " log 80", function (out) { page.logText = out.replace(/\s+$/, "") })
    }

    Component.onCompleted: {
        load(true)
        Sys.run("sh " + Sys.dir + "helpers/update.sh kernel", page.parse)
    }

    Timer {
        interval: page.busy || page.authWait ? 700 : 5000
        repeat: true
        running: Qt.application.state === Qt.ApplicationActive || page.busy || page.authWait
        onTriggered: { page.load(false); if (page.showLog) page.readLog() }
    }

    Sheet {
        id: confirm
        icon: "icons/obj-update.svg"
        onConfirmed: if (page.action) page.action()
    }

    Sheet {
        id: autoSheet
        title: "Automatic Updates"
        body: "KwickOS checks in the background about every " + (page.auto.interval || 12) + " hours. Updates are not installed while the computer runs on battery, and new kernels always start once before they become the default."
        icon: "icons/obj-update.svg"
        cancelText: ""
        confirmText: "Done"
        width: 480
        Repeater {
            model: [
                { key: "check", label: "Check for updates" },
                { key: "download", label: "Download new updates when available" },
                { key: "system", label: "Install system updates" },
                { key: "security", label: "Install security updates" },
                { key: "apps", label: "Install app updates from Flathub" },
                { key: "notify", label: "Notify me about new updates" }
            ]
            delegate: Item {
                id: ar
                required property var modelData
                required property int index
                readonly property bool live: ar.modelData.key === "check" || !!page.auto.check
                Layout.fillWidth: true
                implicitHeight: 38
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: ar.index > 0 ? 18 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: ar.modelData.label
                    color: ar.live ? Theme.text : Theme.faint
                    font.family: Theme.sans
                    font.pixelSize: 13
                }
                Toggle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    enabled: ar.live && !page.authWait
                    checked: !!page.auto[ar.modelData.key] && ar.live
                    onToggled: function (v) { page.setAuto(ar.modelData.key, v) }
                }
                Rectangle { visible: ar.index < 5; anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 10
            Text { Layout.fillWidth: true; text: "Check every"; color: page.auto.check ? Theme.text : Theme.faint; font.family: Theme.sans; font.pixelSize: 13 }
            Seg {
                opacity: page.auto.check ? 1 : 0.4
                enabled: !!page.auto.check
                options: [{ id: "6", label: "6 hours" }, { id: "12", label: "12 hours" }, { id: "24", label: "Day" }]
                current: String(page.auto.interval || 12)
                onPicked: function (id) { page.setEvery(parseInt(id)) }
            }
        }
    }

    Card {
        visible: page.loaded && !page.available
        Cell {
            last: true
            title: "kwick-update is not installed"
            subtitle: "Software Update needs /usr/sbin/kwick-update, which ships with KwickOS 0.6.3 and later images."
        }
    }

    Card {
        visible: page.available
        Cell {
            title: "Automatic Updates"
            last: true
            Text { text: page.autoText(); color: Theme.sub; font.family: Theme.sans; font.pixelSize: 13 }
            InfoButton { onClicked: autoSheet.open() }
        }
    }

    component InfoButton: Rectangle {
        signal clicked()
        implicitWidth: 20
        implicitHeight: 20
        radius: 10
        color: "transparent"
        border.width: 1.2
        border.color: infoArea.containsMouse ? Theme.text : Theme.sub
        Text { anchors.centerIn: parent; anchors.verticalCenterOffset: -0.5; text: "i"; color: infoArea.containsMouse ? Theme.text : Theme.sub; font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.DemiBold }
        MouseArea { id: infoArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
    }

    component Bar: Rectangle {
        property real value: -1
        Layout.fillWidth: true
        implicitHeight: 6
        radius: 3
        color: Theme.track
        clip: true
        Rectangle {
            visible: parent.value >= 0
            height: parent.height
            radius: 3
            color: Theme.accent
            width: parent.width * Math.max(0.02, Math.min(1, parent.value / 100))
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
        Rectangle {
            id: sweep
            visible: parent.value < 0
            height: parent.height
            width: parent.width * 0.28
            radius: 3
            color: Theme.accent
            NumberAnimation on x { running: sweep.visible; loops: Animation.Infinite; from: -sweep.width; to: sweep.parent.width; duration: 1300; easing.type: Easing.InOutQuad }
        }
    }

    component Badge: Rectangle {
        property string label
        property color tint: Theme.accent
        implicitWidth: bl.implicitWidth + 12
        implicitHeight: 18
        radius: 5
        color: Qt.rgba(tint.r, tint.g, tint.b, 0.18)
        Text { id: bl; anchors.centerIn: parent; text: parent.label; color: parent.tint; font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold }
    }

    component Chevron: Text {
        property bool down: false
        text: "›"
        rotation: down ? 90 : 0
        color: Theme.sub
        font.family: Theme.sans
        font.pixelSize: 18
        Behavior on rotation { NumberAnimation { duration: 140 } }
    }

    component Tile: Rectangle {
        property string glyph
        property real glyphSize: 19
        implicitWidth: 32
        implicitHeight: 32
        radius: 8
        Image { anchors.centerIn: parent; width: parent.glyphSize; height: parent.glyphSize; source: parent.glyph; sourceSize.width: 48; sourceSize.height: 48 }
    }

    component Group: Item {
        id: grp
        property string key
        property string title
        property string subtitle
        property string glyph
        property color tint
        property string action
        property var items: []
        property var host
        readonly property bool expanded: !!(grp.host && grp.host.open[key])
        Layout.fillWidth: true
        implicitHeight: head.height + (expanded ? rows.implicitHeight : 0)
        clip: true
        Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Rectangle { width: parent.width; height: 1; color: Theme.line; anchors.top: parent.top; anchors.leftMargin: 16; anchors.left: parent.left }
        Item {
            id: head
            width: parent.width
            height: 58
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: grp.host.toggle(grp.key) }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 16
                spacing: 12
                Tile { color: grp.tint; glyph: grp.glyph }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { Layout.fillWidth: true; text: grp.title; color: Theme.text; font.family: Theme.sans; font.pixelSize: 13 }
                    Text { Layout.fillWidth: true; text: grp.subtitle; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 12 }
                }
                Btn { text: "Install"; enabled: !grp.host.busy && !grp.host.authWait; onClicked: grp.host.upgrade(grp.action) }
                Chevron { down: grp.expanded }
            }
        }
        ColumnLayout {
            id: rows
            y: head.height
            width: parent.width
            spacing: 0
            Repeater {
                model: grp.expanded ? grp.items.slice(0, 200) : []
                delegate: Item {
                    id: pr
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 40
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 60
                        anchors.rightMargin: 16
                        spacing: 10
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            RowLayout {
                                spacing: 6
                                Text { text: pr.modelData.name; color: Theme.text; font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.Medium }
                                Badge { visible: pr.modelData.security; label: "Security"; tint: Theme.warn; implicitHeight: 15 }
                            }
                            Text { Layout.fillWidth: true; text: pr.modelData.summary; visible: text !== ""; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 11; elide: Text.ElideRight }
                        }
                        Text {
                            text: (pr.modelData.from ? pr.modelData.from + "  →  " : "new  ") + pr.modelData.to
                            color: Theme.sub
                            font.family: Theme.mono
                            font.pixelSize: 11
                            Layout.maximumWidth: 300
                            elide: Text.ElideMiddle
                        }
                        Text { Layout.preferredWidth: 64; horizontalAlignment: Text.AlignRight; text: grp.host.bytes(pr.modelData.size); color: Theme.sub; font.family: Theme.sans; font.pixelSize: 11 }
                    }
                    Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.leftMargin: 60; anchors.right: parent.right; height: 1; color: Theme.line }
                }
            }
        }
    }

    Card {
        visible: page.available && page.loaded
        Item {
            Layout.fillWidth: true
            implicitHeight: hero.implicitHeight + 36
            ColumnLayout {
                id: hero
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 18
                spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    Image {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 64
                        source: "icons/app.svg"
                        sourceSize.width: 128
                        sourceSize.height: 128
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        Text {
                            Layout.fillWidth: true
                            text: page.busy ? page.jobTitle() : page.authWait ? "Waiting for Authorization…" : page.hasUpdates ? "Updates Available" : "KwickOS is up to date"
                            color: Theme.text
                            font.family: Theme.sans
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: page.busy ? (page.st.job.message || "") : page.authWait ? "Enter your password in the dialog to continue." : page.hasUpdates ? page.summary(page.updates, page.security ? page.plural(page.security, "security fix", "security fixes") : "") : "KwickOS " + (page.st.release || "") + "  ·  Last checked " + page.when(page.st.checked)
                            color: Theme.sub
                            font.family: Theme.sans
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        Text {
                            visible: page.hasUpdates && !page.busy && !page.authWait
                            text: "Last checked " + page.when(page.st.checked)
                            color: Theme.faint
                            font.family: Theme.sans
                            font.pixelSize: 11
                        }
                    }
                    Btn {
                        visible: !page.busy && !page.authWait
                        text: page.hasUpdates ? "Check Again" : "Check Now"
                        onClicked: page.check()
                    }
                    Btn {
                        visible: page.hasUpdates && !page.busy && !page.authWait
                        text: "Update Now"
                        primary: true
                        onClicked: page.upgrade("all")
                    }
                    Btn {
                        visible: page.busy || page.showLog
                        text: page.showLog ? "Hide Details" : "Details"
                        onClicked: { page.showLog = !page.showLog; if (page.showLog) page.readLog() }
                    }
                }
                ColumnLayout {
                    visible: page.busy || page.authWait
                    Layout.fillWidth: true
                    spacing: 6
                    Bar { value: page.busy ? page.st.job.progress : -1 }
                    Text {
                        visible: page.busy
                        text: page.busy ? page.st.job.progress + "%" + (page.st.job.kind === "upgrade" ? "  ·  Keep the computer on until this finishes." : "") : ""
                        color: Theme.faint
                        font.family: Theme.sans
                        font.pixelSize: 11
                    }
                }
                Text {
                    readonly property string err: page.note !== "" ? page.note : (!page.busy && page.st.result && !page.st.result.ok && page.st.result.kind) ? page.st.result.message || "The last task did not finish." : (!page.busy && page.st.error) ? "Could not reach every update server: " + page.st.error : ""
                    visible: err !== "" && !page.authWait
                    Layout.fillWidth: true
                    text: err
                    color: Theme.bad
                    font.family: Theme.sans
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
                Rectangle {
                    visible: page.showLog
                    Layout.fillWidth: true
                    implicitHeight: Math.min(260, logView.implicitHeight + 20)
                    radius: 8
                    color: Theme.bg
                    border.width: 1
                    border.color: Theme.line
                    clip: true
                    Text {
                        id: logView
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 10
                        text: page.logText !== "" ? page.logText : "No output yet."
                        color: Theme.sub
                        font.family: Theme.mono
                        font.pixelSize: 11
                        wrapMode: Text.WrapAnywhere
                        lineHeight: 1.2
                    }
                }
                RowLayout {
                    visible: !page.busy && !page.showLog && !!page.st.result && page.st.result.kind !== "" && page.st.result.kind !== "check"
                    spacing: 6
                    Text {
                        text: page.st.result ? ((page.st.result.ok ? "Last task: " : "Failed: ") + page.when(page.st.result.time)) : ""
                        color: Theme.faint
                        font.family: Theme.sans
                        font.pixelSize: 11
                    }
                    Text {
                        text: "Show Log"
                        color: Theme.accent
                        font.family: Theme.sans
                        font.pixelSize: 11
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { page.showLog = true; page.readLog() } }
                    }
                }
            }
        }

        Item {
            visible: !!page.st.release_available
            Layout.fillWidth: true
            implicitHeight: 58
            Rectangle { width: parent.width - 16; x: 16; height: 1; color: Theme.line }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 16
                spacing: 12
                Tile { color: Theme.bg; glyph: "icons/app.svg"; glyphSize: 24 }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { text: "KwickOS " + (page.st.release_latest || ""); color: Theme.text; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Text { Layout.fillWidth: true; text: "A new KwickOS release. Update Now installs " + (page.st.release_pkg || "it") + " " + (page.st.release_latest || "") + " with the other updates."; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 12; wrapMode: Text.WordWrap }
                }
                Text {
                    text: "Release Notes"
                    color: Theme.accent
                    font.family: Theme.sans
                    font.pixelSize: 12
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Qt.openUrlExternally("https://github.com/metaspartan/kwickos/releases") }
                }
            }
        }

        Group {
            visible: page.system.length > 0
            key: "system"
            title: "System Updates"
            subtitle: page.summary(page.system, page.security ? page.plural(page.security, "security fix", "security fixes") : "")
            glyph: "icons/app.svg"
            tint: Theme.track
            action: "system"
            items: page.system
            host: page
        }

        Group {
            visible: page.apps.length > 0
            key: "apps"
            title: "App Updates"
            subtitle: page.summary(page.apps, "Flathub")
            glyph: "icons/dock.svg"
            tint: Theme.accent
            action: "apps"
            items: page.apps
            host: page
        }

        Item {
            visible: page.restartNeeded && !page.busy
            Layout.fillWidth: true
            implicitHeight: Math.max(58, rs.implicitHeight + 22)
            Rectangle { width: parent.width - 16; x: 16; height: 1; color: Theme.line }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 16
                spacing: 12
                Tile { color: Theme.warn; glyph: "icons/gpu.svg" }
                ColumnLayout {
                    id: rs
                    Layout.fillWidth: true
                    spacing: 2
                    Text { Layout.fillWidth: true; text: "Restart Required"; color: Theme.text; font.family: Theme.sans; font.pixelSize: 13 }
                    Text {
                        Layout.fillWidth: true
                        text: page.kern.trial ? page.kname(page.kern.trial) + " starts once at the next restart." : page.kname(page.kern.default) + " starts at the next restart."
                        color: Theme.sub
                        font.family: Theme.sans
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                }
                Btn {
                    text: "Restart…"
                    primary: true
                    onClicked: page.ask({
                        title: "Restart now?",
                        body: "Open apps are closed. " + (page.kern.trial ? page.kname(page.kern.trial) + " starts once; if it does not come up, turn the computer off and on to start " + page.kname(page.kern.default) + "." : page.kname(page.kern.default) + " starts."),
                        ok: "Restart",
                        run: page.restart
                    })
                }
            }
        }
    }

    SectionTitle { visible: page.available && page.kernels.length > 0; text: "KERNEL" }

    Card {
        visible: page.available && page.kernels.length > 0
        Cell {
            title: "Running now"
            Text { text: page.kname(page.kern.running); color: Theme.sub; font.family: Theme.sans; font.pixelSize: 13 }
        }
        Cell {
            title: "Starts by default"
            subtitle: page.kern.default && page.kern.default !== page.kern.running ? "Takes effect at the next restart" : ""
            Text { text: page.kern.default ? page.kname(page.kern.default) : "Unknown"; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 13 }
        }
        Cell {
            visible: !!page.kern.previous
            title: "Previous kernel"
            subtitle: page.kname(page.kern.previous)
            Btn {
                text: "Roll Back…"
                enabled: !page.busy && !page.authWait
                onClicked: page.ask({
                    title: "Go back to " + page.kname(page.kern.previous) + "?",
                    body: page.kname(page.kern.previous) + " becomes the default again from the next restart. " + page.kname(page.kern.default) + " stays installed.",
                    ok: "Roll Back",
                    run: function () { page.kernel("rollback") }
                })
            }
        }
        Item {
            visible: !!page.kern.trial
            Layout.fillWidth: true
            implicitHeight: tr.implicitHeight + 24
            Rectangle { anchors.fill: parent; color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.08) }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12
                ColumnLayout {
                    id: tr
                    Layout.fillWidth: true
                    spacing: 3
                    RowLayout {
                        spacing: 8
                        Text { text: "Trial boot pending"; color: Theme.text; font.family: Theme.sans; font.pixelSize: 13 }
                        Badge { label: page.kern.trial_mode === "promote" ? "Becomes default if it starts" : "One time only"; tint: Theme.warn }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: page.kname(page.kern.trial) + " starts once at the next restart. If it does not come up, turn the computer off and on and " + page.kname(page.kern.default) + " starts as before."
                        color: Theme.sub
                        font.family: Theme.sans
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                }
                Btn { text: "Cancel Trial"; enabled: !page.busy && !page.authWait; onClicked: page.kernel("try --cancel") }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
        }
        Item {
            readonly property var res: (page.kern.last_result || "").split(" ")
            visible: !page.kern.trial && res.length > 2
            Layout.fillWidth: true
            implicitHeight: 46
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 8
                Rectangle { width: 8; height: 8; radius: 4; color: parent.parent.res[0] === "ok" ? Theme.good : Theme.bad }
                Text {
                    Layout.fillWidth: true
                    readonly property var r: parent.parent.res
                    text: r[0] === "ok" ? "The trial of " + page.kname(r[1]) + " started and was confirmed." : "The trial of " + page.kname(r[1]) + " did not start, so KwickOS went back to " + page.kname(r[6] || page.kern.default) + "."
                    color: Theme.sub
                    font.family: Theme.sans
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }
            Rectangle { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.leftMargin: 16; anchors.right: parent.right; height: 1; color: Theme.line }
        }
        Cell {
            title: "Keep"
            subtitle: "The running, default and newest kernels of each flavor stay installed"
            Seg {
                options: [{ id: "2", label: "2" }, { id: "3", label: "3" }, { id: "5", label: "5" }]
                current: String(page.kern.keep || 3)
                onPicked: function (id) { if (!page.busy) page.kernel("keep " + id) }
            }
        }
        Cell {
            title: "Boot method"
            last: true
            Text { text: page.bootNames[page.kern.boot] || page.kern.boot || "Unknown"; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 13 }
        }
    }

    SectionTitle { visible: page.available && page.kernels.length > 0; text: "INSTALLED KERNELS" }

    Card {
        visible: page.available && page.kernels.length > 0
        Repeater {
            model: page.kernels
            delegate: Item {
                id: kr
                required property var modelData
                required property int index
                Layout.fillWidth: true
                implicitHeight: 60
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 16
                    spacing: 12
                    Tile { color: kr.modelData.running ? Theme.good : Theme.track; glyph: "icons/gpu.svg" }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        RowLayout {
                            spacing: 6
                            Text { text: "Linux " + kr.modelData.version; color: Theme.text; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.Medium }
                            Badge { label: page.flavors[kr.modelData.flavor] || kr.modelData.flavor; tint: Theme.sub }
                            Badge { visible: kr.modelData.running; label: "Running"; tint: Theme.good }
                            Badge { visible: kr.modelData.default; label: "Default"; tint: Theme.accent }
                            Badge { visible: kr.modelData.previous; label: "Previous"; tint: Theme.sub }
                            Badge { visible: kr.modelData.trial; label: "Trial"; tint: Theme.warn }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: kr.modelData.release + "  ·  " + Math.max(1, Math.round(kr.modelData.size_kb / 1024)) + " MB" + (kr.modelData.origin === "retained" ? "  ·  kept copy" : "")
                            color: Theme.sub
                            font.family: Theme.sans
                            font.pixelSize: 11
                        }
                    }
                    Btn {
                        visible: !kr.modelData.default && page.canTry && !kr.modelData.trial
                        enabled: !page.busy && !page.authWait
                        text: "Try Once…"
                        onClicked: page.ask({
                            title: "Try " + page.kname(kr.modelData.id) + " once?",
                            body: "It starts one time at the next restart and becomes the default only if that boot comes up. If it does not, turn the computer off and on and " + page.kname(page.kern.default) + " starts as before.",
                            ok: "Try Once",
                            run: function () { page.kernel("try " + kr.modelData.id + " --promote") }
                        })
                    }
                    Btn {
                        visible: !kr.modelData.default
                        enabled: !page.busy && !page.authWait
                        text: "Make Default…"
                        onClicked: page.ask({
                            title: "Start " + page.kname(kr.modelData.id) + " from now on?",
                            body: "It becomes the default at the next restart. " + page.kname(page.kern.default) + " stays installed and Roll Back returns to it." + (page.canTry ? " Trying it once first is the safer choice." : ""),
                            ok: "Make Default",
                            run: function () { page.kernel("default " + kr.modelData.id) }
                        })
                    }
                    Btn {
                        visible: kr.modelData.removable
                        enabled: !page.busy && !page.authWait
                        text: "Remove…"
                        danger: true
                        onClicked: page.ask({
                            title: "Remove " + page.kname(kr.modelData.id) + "?",
                            body: "Deletes this kept kernel and its modules. The running and default kernels are never removed.",
                            ok: "Remove",
                            danger: true,
                            run: function () { page.kernel("remove " + kr.modelData.id) }
                        })
                    }
                }
                Rectangle {
                    visible: kr.index < page.kernels.length - 1
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.leftMargin: 58
                    anchors.right: parent.right
                    height: 1
                    color: Theme.line
                }
            }
        }
    }

    SectionTitle { visible: page.available && page.offered.length > 0; text: "AVAILABLE FROM KWICKOS" }

    Card {
        visible: page.available && page.offered.length > 0
        Repeater {
            model: page.offered
            delegate: Item {
                id: ofr
                required property var modelData
                required property int index
                readonly property string id: modelData.flavor + "-" + modelData.version
                Layout.fillWidth: true
                implicitHeight: 54
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 16
                    spacing: 12
                    Tile { color: Theme.accent; glyph: "icons/gpu.svg" }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        RowLayout {
                            spacing: 6
                            Text { text: "Linux " + ofr.modelData.version; color: Theme.text; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.Medium }
                            Badge { label: page.flavors[ofr.modelData.flavor] || ofr.modelData.flavor; tint: Theme.sub }
                            Badge { visible: ofr.modelData.newer; label: "Newer"; tint: Theme.accent }
                        }
                        Text { Layout.fillWidth: true; text: ofr.modelData.package + " " + ofr.modelData.package_version; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 11 }
                    }
                    Btn {
                        text: "Install…"
                        enabled: !page.busy && !page.authWait
                        onClicked: page.ask({
                            title: "Install " + page.kname(ofr.id) + "?",
                            body: page.canTry ? "It is downloaded now and starts once at the next restart. It becomes the default only after that boot comes up; otherwise " + page.kname(page.kern.default) + " keeps starting." : "It is downloaded now and becomes the default at the next restart. Roll Back returns to " + page.kname(page.kern.default) + ".",
                            ok: "Install",
                            run: function () { page.kernel("install " + ofr.modelData.version + ":" + ofr.modelData.flavor) }
                        })
                    }
                }
                Rectangle {
                    visible: ofr.index < page.offered.length - 1
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.leftMargin: 58
                    anchors.right: parent.right
                    height: 1
                    color: Theme.line
                }
            }
        }
    }

    Text {
        visible: page.available && page.kernels.length > 0
        Layout.fillWidth: true
        Layout.topMargin: 2
        text: page.canTry ? "New kernels, from Update Now or Install, start once before they become the default. A kernel that does not come up never strands the computer: the next power cycle starts the default again." : "This boot method cannot start a kernel just once, so new kernels become the default directly. The previous kernel stays installed and Roll Back returns to it."
        color: Theme.sub
        font.family: Theme.sans
        font.pixelSize: 11
        wrapMode: Text.WordWrap
        lineHeight: 1.15
    }
}
