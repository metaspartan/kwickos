import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

ColumnLayout {
    id: page
    spacing: 10

    readonly property string tool: "/usr/sbin/kwick-snapshot"
    readonly property string helper: "sh " + Sys.dir + "helpers/snapshots.sh"
    property var st: ({})
    property var snaps: []
    property string access: "none"
    property string user: ""
    property string home: ""
    property bool loaded: false
    property bool authWait: false
    property string working: ""
    property string note: ""
    property bool noteBad: false
    property string cfg: "root"
    property var action: null
    property var request: null
    property bool restartPending: false

    readonly property bool supported: !!st.supported
    readonly property var conf: st.config || ({})
    readonly property bool busy: page.authWait || page.working !== ""
    readonly property var items: page.build(page.snaps, page.cfg)
    readonly property var days: page.dayMarks(page.items)
    readonly property int rootCount: page.snaps.filter(function (s) { return s.config === "root" }).length
    readonly property int homeCount: page.snaps.filter(function (s) { return s.config === "home" }).length
    readonly property var bootIds: page.snaps.filter(function (s) { return s.config === "root" }).map(function (s) { return s.id }).sort(function (a, b) { return b - a }).slice(0, page.conf.boot_entries || 10)

    function q(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    function bytes(n) {
        if (!n) return "0 bytes"
        if (n >= 1e12) return (n / 1e12).toFixed(1) + " TB"
        if (n >= 1e9) return (n / 1e9).toFixed(1) + " GB"
        if (n >= 1e6) return (n / 1e6).toFixed(1) + " MB"
        if (n >= 1e3) return Math.round(n / 1e3) + " KB"
        return n + " bytes"
    }

    function dayKey(t) {
        var d = new Date(t * 1000)
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate()
    }

    function dayName(t, brief) {
        var d = new Date(t * 1000)
        var n = new Date()
        var y = new Date(n.getFullYear(), n.getMonth(), n.getDate() - 1)
        if (d.toDateString() === n.toDateString()) return "Today"
        if (d.toDateString() === y.toDateString()) return "Yesterday"
        if (brief) return Qt.formatDate(d, d.getFullYear() === n.getFullYear() ? "MMM d" : "MMM d, yyyy")
        if (n - d < 6 * 86400000) return Qt.formatDate(d, "dddd")
        return Qt.formatDate(d, d.getFullYear() === n.getFullYear() ? "dddd, MMMM d" : "MMMM d, yyyy")
    }

    function time(t) {
        return Qt.formatTime(new Date(t * 1000), "h:mm AP")
    }

    function when(t) {
        if (!t) return "never"
        var dn = page.dayName(t, true)
        return (dn === "Today" || dn === "Yesterday" ? dn.toLowerCase() : dn) + " at " + page.time(t)
    }

    function longWhen(t) {
        var d = new Date(t * 1000)
        return Qt.formatDate(d, "dddd, MMMM d, yyyy") + " at " + page.time(t)
    }

    function describe(desc) {
        var m = /^(apt-get|apt|kpkg|aptitude)\s+(\S+)\s*(.*)$/.exec(desc || "")
        if (!m) return desc || "Software change"
        var what = m[3].trim().split(/\s+/).filter(function (w) { return w !== "" && w.indexOf("=") < 0 && w.charAt(0) !== "-" }).map(function (w) {
            return /\.deb$/.test(w) ? w.replace(/^.*\//, "").replace(/\.deb$/, "").split("_")[0] : w
        })
        var list = what.slice(0, 3).join(", ") + (what.length > 3 ? " and " + (what.length - 3) + " more" : "")
        switch (m[2]) {
        case "install": case "reinstall": return list ? "Installed " + list : "Installed software"
        case "remove": case "purge": return list ? "Removed " + list : "Removed software"
        case "autoremove": return "Removed unused software"
        case "upgrade": case "full-upgrade": case "dist-upgrade": return "Updated software"
        default: return desc
        }
    }

    function shape(s, post) {
        var o = { key: s.config + "-" + s.id, id: s.id, post: post ? post.id : 0, date: s.date, date2: post ? post.date : 0, config: s.config,
                  important: s.important, booted: s.booted || (post && post.booted), kernel: s.kernel, desc: s.desc, type: s.type, changes: post ? post.changes : false }
        var d = s.desc || ""
        if (post) {
            o.title = page.describe(d)
            o.sub = "Before " + page.time(s.date) + "  ·  after " + page.time(post.date)
            o.glyph = "icons/snap-update.svg"
            o.tint = "#0a84ff"
        } else if (s.type === "pre") {
            o.title = page.describe(d)
            o.sub = "Before the change, which did not finish"
            o.glyph = "icons/snap-update.svg"
            o.tint = "#0a84ff"
        } else if (s.type === "post") {
            o.title = page.describe(d)
            o.sub = "After the change"
            o.glyph = "icons/snap-update.svg"
            o.tint = "#0a84ff"
        } else if (s.cleanup === "timeline") {
            o.title = s.config === "home" ? "Home folders" : "Hourly snapshot"
            o.sub = "Automatic"
            o.glyph = "icons/snap-clock.svg"
            o.tint = "#8e8e93"
        } else if (d === "Fresh install") {
            o.title = "Fresh Install"
            o.sub = "KwickOS as it was installed"
            o.glyph = "icons/snap-install.svg"
            o.tint = "#30d158"
        } else if (/^Before rollback to /.test(d)) {
            o.title = "Before Restoring the System"
            o.sub = "The system as it was before going back to snapshot " + d.replace(/^Before rollback to /, "")
            o.glyph = "icons/snap-shield.svg"
            o.tint = "#ff9f0a"
        } else if (/^Before restoring files/.test(d)) {
            o.title = "Before Restoring Files"
            o.sub = "Taken automatically"
            o.glyph = "icons/snap-shield.svg"
            o.tint = "#ff9f0a"
        } else {
            o.title = d === "" || d === "Manual snapshot" ? "Snapshot" : d
            o.sub = "Taken by you"
            o.glyph = "icons/snap-manual.svg"
            o.tint = "#bf5af2"
        }
        return o
    }

    function build(list, c) {
        var mine = list.filter(function (s) { return s.config === c })
        var byId = {}
        mine.forEach(function (s) { byId[s.id] = s })
        var used = {}
        var out = []
        mine.forEach(function (s) {
            if (used[s.id]) return
            if (s.type === "pre" && s.post && byId[s.post]) {
                used[s.post] = true
                out.push(page.shape(s, byId[s.post]))
            } else if (s.type === "post" && s.pre && byId[s.pre]) {
                return
            } else {
                out.push(page.shape(s, null))
            }
        })
        out.sort(function (a, b) { return b.date - a.date || b.id - a.id })
        var last = ""
        out.forEach(function (o) {
            var k = page.dayKey(o.date)
            o.head = k !== last ? page.dayName(o.date, false) : ""
            last = k
        })
        return out
    }

    function dayMarks(list) {
        var out = []
        var last = ""
        list.forEach(function (o, i) {
            var k = page.dayKey(o.date)
            if (k !== last) out.push({ label: page.dayName(o.date, true), index: i, date: o.date })
            last = k
        })
        return out
    }

    function snapDir(c, id) {
        return "/.snapshots/" + c + "/" + id + "/snapshot"
    }

    function liveOf(c, rel) {
        if (c === "home") return "/home" + (rel === "/" ? "" : rel)
        return rel
    }

    function parse(out) {
        var s = Sys.sections(out)
        if (s.status !== undefined) {
            try { page.st = JSON.parse(s.status.join("")) } catch (e) { page.st = {} }
        }
        if (s.list !== undefined) {
            try { page.snaps = JSON.parse(s.list.join("")) } catch (e2) { page.snaps = [] }
        }
        if (s.access && s.access.length) page.access = s.access[0].trim()
        if (s.user && s.user.length) page.user = s.user[0].trim()
        if (s.home && s.home.length) page.home = s.home[0].trim()
        page.loaded = true
        if (viewer.opened) viewer.resync()
    }

    function load() {
        Sys.run(page.helper, page.parse)
    }

    function priv(args, label, cb) {
        page.note = ""
        page.authWait = true
        Sys.run(Sys.elevated(page.tool + " " + args), function (out, code) {
            page.authWait = false
            page.working = ""
            if (code === 126 || code === 127) page.say("Authorization was cancelled.", true)
            else if (code !== 0) page.say(page.lastLine(out) || "That did not work.", true)
            page.load()
            if (cb) cb(out, code)
        })
        page.working = label || ""
    }

    function lastLine(out) {
        var l = String(out).split("\n").filter(function (x) { return x.trim() !== "" && !/^(sudo:|\{)/.test(x) })
        try {
            var j = JSON.parse(String(out).split("\n").filter(function (x) { return /^\{/.test(x) }).pop() || "{}")
            if (j.error) return j.error
        } catch (e) { }
        return l.length ? l[l.length - 1].replace(/^kwick-snapshot: /, "") : ""
    }

    function say(t, bad) {
        page.note = t
        page.noteBad = !!bad
        noteTimer.restart()
    }

    function ask(o) {
        page.action = o.run
        confirm.title = o.title
        confirm.body = o.body
        confirm.confirmText = o.ok
        confirm.danger = !!o.danger
        confirm.open()
    }

    function snapshotNow() {
        page.priv("create -c " + page.cfg + " -d " + page.q("Manual snapshot") + " --json", "Taking a snapshot…", function (out, code) {
            if (code === 0) page.say("Snapshot taken.", false)
        })
    }

    function rollback(o) {
        page.ask({
            title: "Restore the system to " + page.dayName(o.date, true).replace(/^(Today|Yesterday)$/, function (m) { return m.toLowerCase() }) + " at " + page.time(o.date) + "?",
            body: "KwickOS starts as it was then. Apps, settings and updates added since are undone. Files in home folders are not touched. The system as it is now is kept as a snapshot, so this can be undone.",
            ok: "Restore and Restart",
            danger: true,
            run: function () {
                page.priv("rollback " + o.id + " --yes --json", "Restoring the system…", function (out, code) {
                    if (code === 0) {
                        viewer.close()
                        page.restartPending = true
                        page.restart()
                    }
                })
            }
        })
    }

    function bootOnce(o) {
        page.ask({
            title: "Start from this snapshot once?",
            body: "At the next restart KwickOS starts as it was " + page.when(o.date) + ", read-only: anything you change is gone after the restart that follows. Nothing on the disk changes, so it is a safe way to look around before restoring.",
            ok: "Restart into Snapshot",
            run: function () {
                page.priv("boot-once " + o.id, "Preparing the boot menu…", function (out, code) {
                    if (code === 0) page.restart()
                })
            }
        })
    }

    function remove(o) {
        var ids = o.post ? o.id + " " + o.post : String(o.id)
        page.ask({
            title: "Delete this snapshot?",
            body: o.title + " from " + page.when(o.date) + " is removed for good. Other snapshots and your files are not affected.",
            ok: "Delete",
            danger: true,
            run: function () {
                page.priv("delete -c " + o.config + " " + ids + " --json", "Deleting…", function (out, code) {
                    if (code === 0) { viewer.close(); page.say("Snapshot deleted.", false) }
                })
            }
        })
    }

    function setConf(key, value) {
        var c = Object.assign({}, page.conf)
        c[key] = value
        page.st = Object.assign({}, page.st, { config: c })
        var v = value === true ? "on" : value === false ? "off" : String(value)
        page.priv("config set " + key.replace("boot_entries", "boot-entries") + " " + v + " --json", "Saving…")
    }

    function restart() {
        Sys.run("dbus-send --session --print-reply --type=method_call --dest=org.kde.Shutdown /Shutdown org.kde.Shutdown.logoutAndReboot || gnome-session-quit --reboot --no-prompt || " + Sys.elevated("reboot"))
    }

    function openItem(o, rel, select) {
        viewer.item = o
        viewer.tab = o.config === "root" && (o.post || o.type !== "single" || o.desc !== "") && !rel ? "changes" : "files"
        if (o.config === "home" || rel) viewer.tab = "files"
        viewer.rel = rel || (o.config === "home" ? (page.user !== "" ? "/" + page.user : "/") : "/")
        viewer.select = select || ""
        viewer.open()
        viewer.refresh()
    }

    function handleRequest(out) {
        var s = Sys.sections(out)
        if (!s.request || !s.request.length) return
        var p = s.request[0].trim()
        if (p === "" || !page.supported) return
        var c = /^\/home(\/|$)/.test(p) && page.st.home ? "home" : "root"
        page.cfg = c
        var rel = c === "home" ? p.replace(/^\/home/, "") : p
        var dir = rel.replace(/\/[^\/]*$/, "") || "/"
        var name = rel.replace(/^.*\//, "")
        var list = page.build(page.snaps, c)
        if (list.length) page.openItem(list[0], dir, name)
    }

    Component.onCompleted: {
        Sys.run(page.helper, function (out) {
            page.parse(out)
            Sys.run(page.helper + " request", page.handleRequest)
        })
    }

    Timer {
        interval: page.busy ? 1500 : 8000
        repeat: true
        running: Qt.application.state === Qt.ApplicationActive
        onTriggered: page.load()
    }

    Timer {
        id: noteTimer
        interval: 6000
        onTriggered: page.note = ""
    }

    Sheet {
        id: confirm
        icon: "icons/obj-snapshots.svg"
        onConfirmed: if (page.action) page.action()
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

    component Tile: Rectangle {
        property string glyph
        property real glyphSize: 17
        implicitWidth: 30
        implicitHeight: 30
        radius: 8
        Image { anchors.centerIn: parent; width: parent.glyphSize; height: parent.glyphSize; source: parent.glyph; sourceSize.width: 48; sourceSize.height: 48 }
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

    component Bar: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 6
        radius: 3
        color: Theme.track
        clip: true
        Rectangle {
            id: sweep
            height: parent.height
            width: parent.width * 0.28
            radius: 3
            color: Theme.accent
            NumberAnimation on x { running: sweep.visible; loops: Animation.Infinite; from: -sweep.width; to: sweep.parent.width; duration: 1300; easing.type: Easing.InOutQuad }
        }
    }

    component Glyph: Item {
        property string kind: "f"
        implicitWidth: 20
        implicitHeight: 20
        Image {
            anchors.fill: parent
            source: parent.kind === "d" ? "icons/snap-folder.svg" : "icons/snap-file.svg"
            sourceSize.width: 40
            sourceSize.height: 40
        }
    }

    component SetRow: Item {
        id: sr
        property string label
        property string hint
        property bool last: false
        property bool dim: false
        default property alias trailing: srSlot.data
        Layout.fillWidth: true
        implicitHeight: Math.max(40, srText.implicitHeight + 16)
        ColumnLayout {
            id: srText
            anchors.left: parent.left
            anchors.right: srSlot.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text { Layout.fillWidth: true; text: sr.label; color: sr.dim ? Theme.faint : Theme.text; font.family: Theme.sans; font.pixelSize: 13 }
            Text { Layout.fillWidth: true; visible: sr.hint !== ""; text: sr.hint; color: Theme.faint; font.family: Theme.sans; font.pixelSize: 11; wrapMode: Text.WordWrap }
        }
        RowLayout { id: srSlot; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter }
        Rectangle { visible: !sr.last; anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
    }

    Sheet {
        id: options
        title: "Snapshot Options"
        body: "Snapshots take almost no space at first: Btrfs only keeps what changes. The oldest go first when the disk runs low."
        icon: "icons/obj-snapshots.svg"
        cancelText: ""
        confirmText: "Done"
        width: 520
        SetRow {
            label: "Before and after software changes"
            hint: "Every update, install and removal, from Software Update, the terminal or any app store"
            Toggle { enabled: !page.busy; checked: !!page.conf.apt; onToggled: function (v) { page.setConf("apt", v) } }
        }
        SetRow {
            label: "Every hour: the system"
            Toggle { enabled: !page.busy; checked: !!page.conf.timeline; onToggled: function (v) { page.setConf("timeline", v) } }
        }
        SetRow {
            label: "Every hour: home folders"
            hint: page.st.home ? "Lets you get back earlier versions of your own files" : "Home folders are not on a Btrfs subvolume on this computer"
            dim: !page.st.home
            Toggle { enabled: !page.busy && !!page.st.home; checked: !!page.conf.home && !!page.st.home; onToggled: function (v) { page.setConf("home", v) } }
        }
        SetRow {
            label: "Keep hourly"
            Seg { options: [{ id: "10", label: "10" }, { id: "24", label: "24" }, { id: "48", label: "48" }]; current: String(page.conf.hourly); onPicked: function (id) { page.setConf("hourly", parseInt(id)) } }
        }
        SetRow {
            label: "Keep daily"
            Seg { options: [{ id: "7", label: "7" }, { id: "14", label: "14" }, { id: "30", label: "30" }]; current: String(page.conf.daily); onPicked: function (id) { page.setConf("daily", parseInt(id)) } }
        }
        SetRow {
            label: "Keep weekly"
            Seg { options: [{ id: "4", label: "4" }, { id: "8", label: "8" }, { id: "12", label: "12" }]; current: String(page.conf.weekly); onPicked: function (id) { page.setConf("weekly", parseInt(id)) } }
        }
        SetRow {
            label: "Keep monthly"
            Seg { options: [{ id: "0", label: "None" }, { id: "3", label: "3" }, { id: "12", label: "12" }]; current: String(page.conf.monthly); onPicked: function (id) { page.setConf("monthly", parseInt(id)) } }
        }
        SetRow {
            label: "Keep software changes"
            Seg { options: [{ id: "5", label: "5" }, { id: "10", label: "10" }, { id: "20", label: "20" }]; current: String(page.conf.number); onPicked: function (id) { page.setConf("number", parseInt(id)) } }
        }
        SetRow {
            label: "Always leave free"
            last: true
            Seg { options: [{ id: "10", label: "10%" }, { id: "20", label: "20%" }, { id: "30", label: "30%" }]; current: String(page.conf.free); onPicked: function (id) { page.setConf("free", parseInt(id)) } }
        }
    }

    Sheet {
        id: restoreSheet
        property string name
        property string mode: "both"
        property var go: null
        title: "Restore “" + name + "”?"
        body: mode === "both" ? "The version from the snapshot is copied next to the current one, so you keep both." : "The version from the snapshot replaces the current one, which moves to the Trash."
        icon: "icons/obj-snapshots.svg"
        confirmText: "Restore"
        Item {
            Layout.fillWidth: true
            Layout.topMargin: 6
            implicitHeight: modeSeg.implicitHeight
            Seg {
                id: modeSeg
                anchors.horizontalCenter: parent.horizontalCenter
                options: [{ id: "both", label: "Keep Both" }, { id: "replace", label: "Replace" }]
                current: restoreSheet.mode
                onPicked: function (id) { restoreSheet.mode = id }
            }
        }
        onConfirmed: if (go) go(mode)
    }

    Card {
        visible: page.loaded
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
                        source: "icons/obj-snapshots.svg"
                        sourceSize.width: 128
                        sourceSize.height: 128
                        opacity: page.supported ? 1 : 0.45
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        Text {
                            Layout.fillWidth: true
                            text: !page.supported ? (page.st.setup ? "Snapshots Are Off" : "Snapshots Need Btrfs")
                                  : page.restartPending ? "Restart to Finish Restoring"
                                  : page.working !== "" ? page.working
                                  : page.authWait ? "Waiting for Authorization…"
                                  : (page.conf.timeline || page.conf.apt) ? "Snapshots Are On" : "Automatic Snapshots Are Off"
                            color: Theme.text
                            font.family: Theme.sans
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: !page.supported ? (page.st.reason || "")
                                  : page.restartPending ? "KwickOS starts from the restored system after the restart."
                                  : page.authWait ? "Enter your password in the dialog to continue."
                                  : "Latest " + page.when(Math.max(page.st.last ? page.st.last.root : 0, page.st.last ? page.st.last.home : 0)) + "  ·  " + (page.rootCount + page.homeCount) + " snapshots"
                            color: Theme.sub
                            font.family: Theme.sans
                            font.pixelSize: 12
                            wrapMode: page.supported ? Text.NoWrap : Text.WordWrap
                            elide: page.supported ? Text.ElideRight : Text.ElideNone
                        }
                    }
                    Btn {
                        visible: !page.supported && !!page.st.setup
                        text: "Turn On…"
                        primary: true
                        enabled: !page.busy
                        onClicked: page.priv("setup", "Setting up snapshots…")
                    }
                    Btn {
                        visible: page.supported && !page.restartPending
                        text: "Options…"
                        enabled: !page.busy
                        onClicked: options.open()
                    }
                    Btn {
                        visible: page.supported && !page.restartPending && !page.st.booted
                        text: "Take Snapshot"
                        primary: true
                        enabled: !page.busy && (page.cfg === "root" || !!page.st.home)
                        onClicked: page.snapshotNow()
                    }
                    Btn {
                        visible: page.restartPending
                        text: "Restart…"
                        primary: true
                        onClicked: page.restart()
                    }
                }
                Bar { visible: page.busy }
                Text {
                    visible: page.note !== ""
                    Layout.fillWidth: true
                    text: page.note
                    color: page.noteBad ? Theme.bad : Theme.good
                    font.family: Theme.sans
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }
        }

        Item {
            visible: !!page.st.booted
            Layout.fillWidth: true
            implicitHeight: bootedRow.implicitHeight + 24
            Rectangle { anchors.fill: parent; color: Theme.warnBg; radius: 0 }
            Rectangle { width: parent.width; height: 1; color: Theme.line }
            RowLayout {
                id: bootedRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12
                Tile { color: Theme.warn; glyph: "icons/snap-clock.svg" }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { Layout.fillWidth: true; text: "Running from a snapshot of " + page.when(page.st.booted_date); color: Theme.text; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Text { Layout.fillWidth: true; text: "Nothing you change now is kept. Restore it to make this the system from now on, or restart to go back."; color: Theme.warnText; font.family: Theme.sans; font.pixelSize: 12; wrapMode: Text.WordWrap }
                }
                Btn {
                    text: "Restore This Version…"
                    primary: true
                    enabled: !page.busy
                    onClicked: {
                        var s = page.snaps.filter(function (x) { return x.config === "root" && x.id === page.st.booted })[0]
                        if (s) page.rollback(page.shape(s, null))
                    }
                }
            }
        }

        Item {
            id: rbItem
            readonly property var rb: page.st.rolled_back || ({})
            visible: !page.st.booted && !!rb.id && Date.now() / 1000 - (rb.date || 0) < 7 * 86400
            Layout.fillWidth: true
            implicitHeight: rbRow.implicitHeight + 24
            Rectangle { width: parent.width; height: 1; color: Theme.line }
            RowLayout {
                id: rbRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12
                Tile { color: Theme.good; glyph: "icons/snap-shield.svg" }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { Layout.fillWidth: true; text: "The system was restored " + page.when(rbItem.rb.date || 0); color: Theme.text; font.family: Theme.sans; font.pixelSize: 13 }
                    Text { Layout.fillWidth: true; text: "It went back to how it was " + page.when(rbItem.rb.snapshot_date || 0) + "."; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 12; wrapMode: Text.WordWrap }
                }
            }
        }
    }

    RowLayout {
        visible: page.supported
        Layout.fillWidth: true
        Layout.topMargin: 6
        spacing: 10
        Seg {
            options: [{ id: "root", label: "System" }, { id: "home", label: "Home Folders" }]
            current: page.cfg
            onPicked: function (id) { page.cfg = id }
        }
        Item { Layout.fillWidth: true }
        Text {
            text: page.items.length === 1 ? "1 snapshot" : page.items.length + " snapshots"
            color: Theme.sub
            font.family: Theme.sans
            font.pixelSize: 12
        }
    }

    Card {
        visible: page.supported
        Item {
            Layout.fillWidth: true
            implicitHeight: page.items.length ? Math.min(470, Math.max(160, list.contentHeight + 2)) : 200

            ColumnLayout {
                anchors.centerIn: parent
                visible: page.items.length === 0
                width: parent.width - 80
                spacing: 6
                Image {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    source: "icons/obj-snapshots.svg"
                    sourceSize.width: 96
                    sourceSize.height: 96
                    opacity: 0.55
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: page.cfg === "home" && !page.st.home ? "Home folders can’t be snapshotted on this computer" : "No snapshots yet"
                    color: Theme.text
                    font.family: Theme.sans
                    font.pixelSize: 14
                    font.weight: Font.Medium
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: page.cfg === "home" && !page.st.home ? "/home is not a Btrfs subvolume of the system disk." : page.cfg === "home" ? (page.conf.home ? "The first one is taken within the hour." : "Turn on hourly snapshots of home folders in Options.") : "One is taken before the next software change" + (page.conf.timeline ? " and every hour." : ".")
                    color: Theme.sub
                    font.family: Theme.sans
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }

            ListView {
                id: list
                visible: page.items.length > 0
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: ruler.left
                clip: true
                model: page.items
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: list.contentHeight > list.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                delegate: Column {
                    id: row
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    Item {
                        visible: row.modelData.head !== ""
                        width: parent.width
                        height: visible ? (row.index === 0 ? 34 : 40) : 0
                        Text {
                            x: 16
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 6
                            text: row.modelData.head
                            color: Theme.sub
                            font.family: Theme.sans
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 0.4
                        }
                    }
                    Rectangle {
                        width: parent.width
                        height: 56
                        color: rowArea.containsMouse ? Theme.hover : "transparent"
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 12
                            spacing: 12
                            Tile { color: row.modelData.tint; glyph: row.modelData.glyph }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Row {
                                    id: titleRow
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Text {
                                        width: Math.min(implicitWidth, titleRow.width - (runBadge.visible ? runBadge.width + 6 : 0))
                                        text: row.modelData.title
                                        color: Theme.text
                                        font.family: Theme.sans
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                    }
                                    Badge { id: runBadge; visible: !!row.modelData.booted; label: "Running Now"; tint: Theme.warn }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: (row.modelData.post ? "" : page.time(row.modelData.date) + "  ·  ") + row.modelData.sub
                                    color: Theme.sub
                                    font.family: Theme.sans
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                            }
                            Btn {
                                visible: rowArea.containsMouse || browseArea.containsMouse
                                text: "Browse"
                                onClicked: page.openItem(row.modelData, page.cfg === "root" ? "/" : "")
                                MouseArea { id: browseArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                            }
                            Text {
                                text: "›"
                                color: Theme.faint
                                font.family: Theme.sans
                                font.pixelSize: 18
                            }
                        }
                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            z: -1
                            onClicked: page.openItem(row.modelData)
                        }
                        Rectangle {
                            visible: row.index < page.items.length - 1 && page.items[row.index + 1].head === ""
                            anchors.bottom: parent.bottom
                            x: 56
                            width: parent.width - 56
                            height: 1
                            color: Theme.line
                        }
                    }
                }
            }

            Item {
                id: ruler
                visible: page.items.length > 0
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 96
                readonly property int at: {
                    var i = list.indexAt(10, list.contentY + 20)
                    return i < 0 ? 0 : i
                }
                Rectangle { width: 1; anchors.top: parent.top; anchors.bottom: parent.bottom; color: Theme.line }
                Rectangle {
                    x: 64
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: 18
                    anchors.bottomMargin: 18
                    width: 2
                    radius: 1
                    color: Theme.line
                }
                Column {
                    anchors.top: parent.top
                    anchors.topMargin: 10
                    width: parent.width
                    spacing: 0
                    Item {
                        width: parent.width
                        height: 26
                        Text { anchors.right: parent.right; anchors.rightMargin: 40; anchors.verticalCenter: parent.verticalCenter; text: "Now"; color: Theme.accent; font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold }
                        Rectangle { x: 60; anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; radius: 5; color: Theme.accent }
                    }
                    Repeater {
                        model: page.days.slice(0, Math.max(1, Math.floor((ruler.height - 50) / 24)))
                        delegate: Item {
                            id: dm
                            required property var modelData
                            required property int index
                            readonly property bool here: {
                                var next = dm.index + 1 < page.days.length ? page.days[dm.index + 1].index : 1e9
                                return ruler.at >= dm.modelData.index && ruler.at < next
                            }
                            width: ruler.width
                            height: 24
                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 40
                                anchors.verticalCenter: parent.verticalCenter
                                text: dm.modelData.label
                                color: dm.here ? Theme.text : dmArea.containsMouse ? Theme.text : Theme.sub
                                font.family: Theme.sans
                                font.pixelSize: 11
                                font.weight: dm.here ? Font.DemiBold : Font.Normal
                            }
                            Rectangle {
                                x: dm.here ? 58 : 60
                                anchors.verticalCenter: parent.verticalCenter
                                width: dm.here ? 14 : 10
                                height: 2
                                radius: 1
                                color: dm.here ? Theme.accent : Theme.faint
                            }
                            MouseArea { id: dmArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: list.positionViewAtIndex(dm.modelData.index, ListView.Beginning) }
                        }
                    }
                }
            }
        }
    }

    Text {
        visible: page.supported
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.topMargin: 2
        text: "Snapshots live on the same disk as the system. They undo updates and bring back files, but they can’t help if the disk itself fails, so keep a copy of important files on another drive."
        color: Theme.faint
        font.family: Theme.sans
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }

    Card {
        visible: page.loaded && page.supported
        Cell {
            title: "Start the computer from a snapshot"
            subtitle: page.st.boot_menu ? "Press Esc (GRUB) or Space (systemd-boot) while KwickOS starts and pick one under KwickOS snapshots. It runs read-only until you restore it." : "This computer starts without a boot menu (" + (page.st.bootloader || "unknown") + "). If KwickOS does not start, boot the KwickOS live USB and run kwick-snapshot --device auto rollback N."
        }
        Cell {
            last: true
            title: "Storage"
            subtitle: page.bytes((page.st.free_kb || 0) * 1024) + " available of " + page.bytes((page.st.size_kb || 0) * 1024) + ". Snapshots are removed oldest first when less than " + (page.conf.free || 20) + "% is free."
        }
    }

    Popup {
        id: viewer
        property var item: ({})
        property string tab: "files"
        property string rel: "/"
        property string select: ""
        property var all: []
        property bool showHidden: false
        readonly property var entries: showHidden ? all : all.filter(function (x) { return x.name.charAt(0) !== "." })
        property bool listing: false
        property var pkgs: []
        property var changes: []
        property bool changesLoaded: false
        property bool pkgsLoaded: false
        property bool changesNeedRoot: false
        readonly property string base: page.snapDir(item.config || "root", item.id || 0)
        readonly property var crumbs: {
            var out = [{ label: item.config === "home" ? "Home" : "Computer", rel: "/" }]
            var acc = ""
            rel.split("/").filter(function (x) { return x !== "" }).forEach(function (p) { acc += "/" + p; out.push({ label: p, rel: acc }) })
            return out
        }

        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(860, parent ? parent.width - 60 : 860)
        height: Math.min(640, parent ? parent.height - 60 : 640)
        modal: true
        focus: true
        padding: 0
        closePolicy: Popup.CloseOnEscape
        Overlay.modal: Rectangle { color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.6) }
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 } NumberAnimation { property: "scale"; from: 0.97; to: 1; duration: 170; easing.type: Easing.OutCubic } }
        exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 110 } }
        background: Rectangle { radius: 14; color: Theme.cardHi; border.width: 1; border.color: Theme.lineStrong }

        function refresh() {
            if (tab === "files") list_()
            else changes_()
        }

        function resync() {
            var still = page.snaps.some(function (s) { return s.config === viewer.item.config && s.id === viewer.item.id })
            if (!still) viewer.close()
        }

        function list_() {
            listing = true
            Sys.run(page.helper + " files " + page.q(base + (rel === "/" ? "" : rel)) + " " + page.q(page.liveOf(item.config, rel)), function (out) {
                var s = Sys.sections(out)
                var e = []
                ;(s.files || []).forEach(function (l) {
                    var p = l.split("\t")
                    if (p.length >= 6) e.push({ t: p[0], size: parseInt(p[1]) || 0, mtime: parseInt(p[2]) || 0, state: p[3], readable: p[4] === "1", name: p.slice(5).join("\t") })
                })
                e.sort(function (a, b) { return (a.t === "d" ? 0 : 1) - (b.t === "d" ? 0 : 1) || a.name.toLowerCase().localeCompare(b.name.toLowerCase()) })
                if (viewer.select.charAt(0) === ".") viewer.showHidden = true
                viewer.all = e
                viewer.listing = false
                if (viewer.select !== "") {
                    var shown = viewer.entries
                    for (var i = 0; i < shown.length; i++) if (shown[i].name === viewer.select) { files.currentIndex = i; files.positionViewAtIndex(i, ListView.Center) }
                    viewer.select = ""
                } else {
                    files.currentIndex = -1
                }
            })
        }

        function changes_() {
            if (item.config !== "root") return
            pkgsLoaded = false
            changesLoaded = false
            changesNeedRoot = false
            Sys.run(page.helper + " pkgs " + item.id + " " + (item.post || "current"), function (out) {
                var s = Sys.sections(out)
                try { viewer.pkgs = JSON.parse((s.pkgs || []).join("")) } catch (e) { viewer.pkgs = [] }
                viewer.pkgsLoaded = true
            })
            if (item.post) {
                Sys.run(page.helper + " changes root " + item.id + " " + item.post, function (out) {
                    var s = Sys.sections(out)
                    try { viewer.changes = JSON.parse((s.changes || []).join("")) } catch (e) { viewer.changes = []; viewer.changesNeedRoot = true }
                    viewer.changesLoaded = true
                })
            } else {
                viewer.changes = []
                viewer.changesLoaded = true
                viewer.changesNeedRoot = true
            }
        }

        function compareNow() {
            page.priv("diff -c root " + item.id + " --json", "Comparing with now…", function (out, code) {
                if (code !== 0) return
                try {
                    viewer.changes = JSON.parse(String(out).split("\n").filter(function (x) { return /^\[/.test(x) }).join(""))
                    viewer.changesNeedRoot = false
                } catch (e) { }
            })
        }

        function enterDir(name) {
            rel = (rel === "/" ? "" : rel) + "/" + name
            list_()
        }

        function go(r) {
            rel = r
            list_()
        }

        function restoreEntry(e) {
            var src = base + (rel === "/" ? "" : rel) + "/" + e.name
            var live = page.liveOf(item.config, rel)
            var dst = (live === "/" ? "" : live) + "/" + e.name
            var mine = page.home !== "" && (dst + "/").indexOf(page.home + "/") === 0
            restoreSheet.name = e.name
            restoreSheet.mode = e.state === "gone" ? "replace" : "both"
            restoreSheet.go = function (mode) {
                if (mine) {
                    page.working = "Restoring…"
                    Sys.run(page.helper + " restore " + page.q(src) + " " + page.q(dst) + " " + mode, function (out, code) {
                        page.working = ""
                        if (code === 0) page.say("Restored “" + e.name + "” to " + live + ".", false)
                        else page.say("“" + e.name + "” could not be restored.", true)
                        viewer.list_()
                    })
                } else {
                    page.priv("restore -c " + item.config + " " + item.id + " " + page.q(dst) + (mode === "both" ? " --keep-both" : "") + " --json", "Restoring…", function (out, code) {
                        if (code === 0) page.say("Restored “" + e.name + "” to " + live + ".", false)
                        viewer.list_()
                    })
                }
            }
            restoreSheet.open()
        }

        contentItem: ColumnLayout {
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 18
                Layout.bottomMargin: 12
                spacing: 12
                Tile { color: viewer.item.tint || Theme.accent; glyph: viewer.item.glyph || "icons/snap-clock.svg"; implicitWidth: 38; implicitHeight: 38; radius: 10; glyphSize: 21 }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { Layout.fillWidth: true; text: viewer.item.title || ""; color: Theme.text; font.family: Theme.sans; font.pixelSize: 15; font.weight: Font.DemiBold; elide: Text.ElideRight }
                    Text {
                        Layout.fillWidth: true
                        text: viewer.item.date ? page.longWhen(viewer.item.date) + (viewer.item.kernel ? "  ·  Linux " + viewer.item.kernel.replace(/-kwick.*$/, "") : "") + "  ·  #" + viewer.item.id : ""
                        color: Theme.sub
                        font.family: Theme.sans
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }
                Seg {
                    visible: viewer.item.config === "root"
                    options: [{ id: "changes", label: "Changes" }, { id: "files", label: "Files" }]
                    current: viewer.tab
                    onPicked: function (id) { viewer.tab = id; viewer.refresh() }
                }
                Rectangle {
                    implicitWidth: 26
                    implicitHeight: 26
                    radius: 13
                    color: closeArea.containsMouse ? Theme.hover : "transparent"
                    Text { anchors.centerIn: parent; text: "✕"; color: Theme.sub; font.pixelSize: 12 }
                    MouseArea { id: closeArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: viewer.close() }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.line }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    visible: viewer.tab === "files"
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.rightMargin: 18
                        spacing: 10
                        Flickable {
                            Layout.fillWidth: true
                            Layout.leftMargin: 14
                            implicitHeight: 40
                            contentWidth: crumbRow.implicitWidth
                            clip: true
                            flickableDirection: Flickable.HorizontalFlick
                            boundsBehavior: Flickable.StopAtBounds
                            Row {
                                id: crumbRow
                                height: 40
                                spacing: 2
                                Repeater {
                                    model: viewer.crumbs
                                    delegate: Row {
                                        id: cr
                                        required property var modelData
                                        required property int index
                                        height: 40
                                        spacing: 2
                                        Text { visible: cr.index > 0; anchors.verticalCenter: parent.verticalCenter; text: "›"; color: Theme.faint; font.pixelSize: 15 }
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: crt.implicitWidth + 14
                                            height: 24
                                            radius: 6
                                            color: crArea.containsMouse ? Theme.hover : "transparent"
                                            Text {
                                                id: crt
                                                anchors.centerIn: parent
                                                text: cr.modelData.label
                                                color: cr.index === viewer.crumbs.length - 1 ? Theme.text : Theme.sub
                                                font.family: Theme.sans
                                                font.pixelSize: 12
                                                font.weight: cr.index === viewer.crumbs.length - 1 ? Font.DemiBold : Font.Normal
                                            }
                                            MouseArea { id: crArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: viewer.go(cr.modelData.rel) }
                                        }
                                    }
                                }
                            }
                        }
                        Text {
                            text: "Show hidden files"
                            color: Theme.sub
                            font.family: Theme.sans
                            font.pixelSize: 12
                        }
                        Toggle {
                            scale: 0.8
                            checked: viewer.showHidden
                            onToggled: function (v) { viewer.showHidden = v; files.currentIndex = -1 }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 26
                        color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.03)
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 50
                            anchors.rightMargin: 108
                            spacing: 10
                            Text { Layout.fillWidth: true; text: "Name"; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 11 }
                            Text { Layout.preferredWidth: 150; text: "Modified"; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 11 }
                            Text { Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight; text: "Size"; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 11 }
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                    }

                    ListView {
                        id: files
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: viewer.entries
                        currentIndex: -1
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { }
                        delegate: Rectangle {
                            id: fe
                            required property var modelData
                            required property int index
                            readonly property bool sel: files.currentIndex === fe.index
                            width: ListView.view.width
                            height: 34
                            color: sel ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Theme.light ? 0.14 : 0.28) : feArea.containsMouse ? Theme.hover : (fe.index % 2 ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.025) : "transparent")
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 20
                                anchors.rightMargin: 12
                                spacing: 10
                                Glyph { kind: fe.modelData.t; opacity: fe.modelData.readable ? 1 : 0.45 }
                                Row {
                                    id: nameRow
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.min(implicitWidth, nameRow.width - (stateBadge.visible ? stateBadge.width + 8 : 0))
                                        text: fe.modelData.name + (fe.modelData.t === "l" ? "  →" : "")
                                        color: fe.modelData.readable ? Theme.text : Theme.faint
                                        font.family: Theme.sans
                                        font.pixelSize: 13
                                        elide: Text.ElideMiddle
                                    }
                                    Badge {
                                        id: stateBadge
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: fe.modelData.state !== "same"
                                        label: fe.modelData.state === "gone" ? "Not on this computer now" : "Changed since"
                                        tint: fe.modelData.state === "gone" ? Theme.warn : Theme.info
                                        implicitHeight: 16
                                    }
                                }
                                Text { Layout.preferredWidth: 150; text: fe.modelData.mtime ? Qt.formatDateTime(new Date(fe.modelData.mtime * 1000), "MMM d, yyyy  h:mm AP") : ""; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 12; elide: Text.ElideRight }
                                Text { Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight; text: fe.modelData.t === "d" ? "--" : page.bytes(fe.modelData.size); color: Theme.sub; font.family: Theme.sans; font.pixelSize: 12 }
                                Item {
                                    Layout.preferredWidth: 86
                                    implicitHeight: 26
                                    Btn {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: (feArea.containsMouse || fe.sel) && fe.modelData.readable && !page.busy && !page.st.booted
                                        text: "Restore"
                                        implicitHeight: 24
                                        onClicked: viewer.restoreEntry(fe.modelData)
                                    }
                                }
                            }
                            MouseArea {
                                id: feArea
                                anchors.fill: parent
                                hoverEnabled: true
                                z: -1
                                onClicked: files.currentIndex = fe.index
                                onDoubleClicked: if (fe.modelData.t === "d" && fe.modelData.readable) viewer.enterDir(fe.modelData.name)
                            }
                        }
                    }

                    ColumnLayout {
                        visible: !viewer.listing && viewer.entries.length === 0
                        Layout.fillWidth: true
                        Layout.bottomMargin: 120
                        spacing: 4
                        Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: "This folder is empty in the snapshot"; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 13 }
                        Text { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: "Or it can only be opened by its owner."; color: Theme.faint; font.family: Theme.sans; font.pixelSize: 12 }
                    }
                }

                Flickable {
                    id: chFlick
                    anchors.fill: parent
                    visible: viewer.tab === "changes"
                    clip: true
                    contentWidth: width
                    contentHeight: chCol.implicitHeight + 30
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { }

                    ColumnLayout {
                        id: chCol
                        x: 18
                        y: 14
                        width: chFlick.width - 36
                        spacing: 10

                        Text {
                            Layout.fillWidth: true
                            text: viewer.item.post ? "What changed from before to after." : "What is different on this computer now, compared with this snapshot."
                            color: Theme.sub
                            font.family: Theme.sans
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }

                        Repeater {
                            model: [
                                { s: "u", title: "Updated", tint: Theme.info },
                                { s: "+", title: "Installed", tint: Theme.good },
                                { s: "-", title: "Removed", tint: Theme.bad }
                            ]
                            delegate: ColumnLayout {
                                id: pg
                                required property var modelData
                                readonly property var rows: viewer.pkgs.filter(function (p) { return p.s === pg.modelData.s })
                                visible: rows.length > 0
                                Layout.fillWidth: true
                                spacing: 6
                                RowLayout {
                                    spacing: 8
                                    Text { text: pg.modelData.title.toUpperCase() + " SOFTWARE"; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.4 }
                                    Badge { label: String(pg.rows.length); tint: pg.modelData.tint; implicitHeight: 16 }
                                }
                                Card {
                                    Repeater {
                                        model: pg.rows.slice(0, 300)
                                        delegate: Item {
                                            id: pr
                                            required property var modelData
                                            required property int index
                                            Layout.fillWidth: true
                                            implicitHeight: 34
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 14
                                                anchors.rightMargin: 14
                                                spacing: 10
                                                Rectangle { implicitWidth: 7; implicitHeight: 7; radius: 3.5; color: pg.modelData.tint }
                                                Text { Layout.fillWidth: true; text: pr.modelData.name; color: Theme.text; font.family: Theme.sans; font.pixelSize: 12; elide: Text.ElideRight }
                                                Text {
                                                    text: pr.modelData.s === "u" ? pr.modelData.from + "  →  " + pr.modelData.to : pr.modelData.s === "+" ? pr.modelData.to : pr.modelData.from
                                                    color: Theme.sub
                                                    font.family: Theme.mono
                                                    font.pixelSize: 11
                                                    Layout.maximumWidth: 360
                                                    elide: Text.ElideMiddle
                                                }
                                            }
                                            Rectangle { visible: pr.index < Math.min(pg.rows.length, 300) - 1; anchors.bottom: parent.bottom; x: 14; width: parent.width - 14; height: 1; color: Theme.line }
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            visible: viewer.pkgsLoaded && viewer.pkgs.length === 0
                            Layout.fillWidth: true
                            text: "No software was installed, updated or removed."
                            color: Theme.text
                            font.family: Theme.sans
                            font.pixelSize: 13
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 6
                            spacing: 8
                            Text { text: "CHANGED FILES"; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.4 }
                            Badge { visible: !viewer.changesNeedRoot; label: String(viewer.changes.length); tint: Theme.info; implicitHeight: 16 }
                            Item { Layout.fillWidth: true }
                            Btn { visible: viewer.changesNeedRoot; text: "Compare Files with Now…"; enabled: !page.busy; onClicked: viewer.compareNow() }
                        }

                        Card {
                            visible: !viewer.changesNeedRoot && viewer.changes.length > 0
                            Repeater {
                                model: viewer.changes.slice(0, 400)
                                delegate: Item {
                                    id: cf
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    implicitHeight: 28
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 14
                                        spacing: 10
                                        Text {
                                            Layout.preferredWidth: 14
                                            horizontalAlignment: Text.AlignHCenter
                                            text: cf.modelData.s === "+" ? "+" : cf.modelData.s === "-" ? "−" : "•"
                                            color: cf.modelData.s === "+" ? Theme.good : cf.modelData.s === "-" ? Theme.bad : Theme.info
                                            font.family: Theme.mono
                                            font.pixelSize: 13
                                            font.weight: Font.DemiBold
                                        }
                                        Text { Layout.fillWidth: true; text: cf.modelData.path; color: Theme.text; font.family: Theme.mono; font.pixelSize: 11; elide: Text.ElideMiddle }
                                    }
                                }
                            }
                        }

                        Text {
                            visible: !viewer.changesNeedRoot && viewer.changes.length > 400
                            text: "and " + (viewer.changes.length - 400) + " more"
                            color: Theme.faint
                            font.family: Theme.sans
                            font.pixelSize: 11
                        }

                        Text {
                            visible: viewer.changesNeedRoot
                            Layout.fillWidth: true
                            text: "Comparing system files needs an administrator."
                            color: Theme.faint
                            font.family: Theme.sans
                            font.pixelSize: 12
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.line }

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 14
                spacing: 8
                Btn {
                    text: "Delete…"
                    danger: true
                    enabled: !page.busy && !viewer.item.booted
                    onClicked: page.remove(viewer.item)
                }
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    text: page.working !== "" ? page.working : page.note
                    color: page.noteBad ? Theme.bad : page.working !== "" ? Theme.sub : Theme.good
                    font.family: Theme.sans
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
                Btn {
                    visible: viewer.tab === "files" && viewer.rel !== "/" && !page.st.booted
                    text: "Restore “" + viewer.rel.replace(/^.*\//, "") + "”…"
                    enabled: !page.busy
                    onClicked: {
                        var parts = viewer.rel.split("/")
                        var name = parts.pop()
                        var parentRel = parts.join("/") || "/"
                        var keep = viewer.rel
                        viewer.rel = parentRel
                        viewer.restoreEntry({ name: name, state: "changed" })
                        viewer.rel = keep
                    }
                }
                Btn {
                    visible: viewer.item.config === "root" && !!page.st.boot_menu && !page.st.booted && !viewer.item.booted && page.bootIds.indexOf(viewer.item.id) >= 0
                    text: "Start from It Once…"
                    enabled: !page.busy
                    onClicked: page.bootOnce(viewer.item)
                }
                Btn {
                    visible: viewer.item.config === "root" && !!page.st.rollback
                    text: viewer.item.post ? "Undo This Change…" : "Restore System…"
                    primary: true
                    enabled: !page.busy
                    onClicked: page.rollback(viewer.item)
                }
            }
        }
    }
}
