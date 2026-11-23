pragma Singleton
import QtQuick
import org.kde.plasma.plasma5support as P5

QtObject {
    id: s

    readonly property string bin: "/usr/lib/kwick/store/backend"
    readonly property string pkg: "/usr/lib/kwick/store/kwick-store-pkg"
    property int counter: 0
    property var callbacks: ({})

    property var sources: ({})
    property bool sourcesLoaded: false
    property var marks: ({})
    property var ops: ({})
    property var queue: []
    property string active: ""
    property string toast: ""
    property bool toastBad: false
    property int revision: 0

    property var updates: ({ apps: [], system: [], arch: [] })
    property bool updatesLoaded: false
    property bool updatesLoading: false
    property var installed: []
    property bool installedLoaded: false
    property bool installedLoading: false
    property var job: ({})
    property bool checking: false

    readonly property bool archOn: !!(sources.arch && sources.arch.installed && sources.arch.enabled)
    readonly property bool archInstalled: !!(sources.arch && sources.arch.installed)
    readonly property bool archAvailable: !!(sources.arch && !sources.arch.installed && sources.arch.available)
    readonly property bool agentsOn: !!(sources.agents && sources.agents.installed)
    readonly property int updateCount: (updates.apps || []).length + (updates.arch || []).length + ((updates.system || []).length > (updates.apps || []).filter(function (a) { return a.src === "apt" }).length ? 1 : 0)
    readonly property bool busy: active !== "" || queue.length > 0

    signal changed(string key)

    readonly property QtObject source: P5.DataSource {
        engine: "executable"
        onNewData: (src, data) => {
            disconnectSource(src)
            var f = s.callbacks[src]
            if (f) {
                delete s.callbacks[src]
                f(String(data["stdout"]), data["exit code"])
            }
        }
    }

    readonly property QtObject poll: Timer {
        interval: 600
        repeat: true
        running: s.active !== "" || s.checking
        onTriggered: s.call("job", function (j) { if (j) s.onJob(j) })
    }

    function run(cmd, cb) {
        var src = cmd + " #" + (s.counter++)
        if (cb)
            s.callbacks[src] = cb
        s.source.connectSource(src)
    }

    function q(x) {
        return "'" + String(x).replace(/'/g, "'\\''") + "'"
    }

    function call(args, cb) {
        s.run(s.bin + " " + args, function (out, code) {
            var j = null
            try { j = JSON.parse(out) } catch (e) { j = null }
            if (cb) cb(j, code, out)
        })
    }

    function elevated(cmd) {
        return "if sudo -n true 2>/dev/null; then sudo -n " + cmd + " 2>&1; else pkexec " + cmd + " 2>&1; fi"
    }

    function say(msg, bad) {
        s.toastBad = !!bad
        s.toast = ""
        s.toast = msg
    }

    function isInstalled(app) {
        if (!app) return false
        if (s.marks[app.key] !== undefined) return s.marks[app.key]
        return !!app.installed
    }

    function op(key) {
        return s.ops[key] || null
    }

    function setOp(key, o) {
        var m = Object.assign({}, s.ops)
        if (o) m[key] = o
        else delete m[key]
        s.ops = m
    }

    function mark(key, v) {
        var m = Object.assign({}, s.marks)
        m[key] = v
        s.marks = m
    }

    function loadSources(cb) {
        s.call("sources", function (j) {
            if (j && !j.error) {
                s.sources = j
                s.sourcesLoaded = true
            }
            if (cb) cb()
        })
    }

    function loadInstalled() {
        if (s.installedLoading) return
        s.installedLoading = true
        s.call("installed", function (j) {
            s.installedLoading = false
            if (j && j.items) {
                s.installed = j.items
                s.installedLoaded = true
            }
        })
    }

    function loadUpdates() {
        if (s.updatesLoading) return
        s.updatesLoading = true
        s.call("updates", function (j) {
            s.updatesLoading = false
            if (j && !j.error) {
                s.updates = j
                s.updatesLoaded = true
            }
        })
    }

    function checkUpdates() {
        s.checking = true
        s.run(s.elevated("/usr/sbin/kwick-update check --quiet"), function (out, code) {
            s.checking = false
            if (code === 126 || code === 127) s.say("Authorization was cancelled.", true)
            else if (code !== 0) s.say(s.lastLine(out) || "Could not check for updates.", true)
            s.loadUpdates()
        })
    }

    function lastLine(out) {
        var l = String(out || "").split("\n").filter(function (x) { return x.trim() !== "" && !/^(sudo:|__rc|Error executing command)/.test(x) })
        return l.length ? l[l.length - 1].replace(/^kwick-(store|update|arch|agents):\s*/, "") : ""
    }

    function command(o) {
        var a = o.app
        var src = a.src
        var id = a.src === "apt" ? (a.pkg || a.id) : a.id
        if (o.kind === "updateall")
            return s.elevated("/usr/sbin/kwick-update upgrade all --quiet")
        if (o.kind === "updatesys")
            return s.elevated("/usr/sbin/kwick-update upgrade system --quiet")
        if (src === "flathub") {
            if (o.kind === "install") return s.elevated(s.pkg + " install flatpak " + s.q(a.remote || "flathub") + " " + s.q(id))
            if (a.scope === "user") return s.bin + " userjob flatpak " + (o.kind === "remove" ? "remove " : "update ") + s.q(id)
            return s.elevated(s.pkg + " " + o.kind + " flatpak " + s.q(id))
        }
        if (src === "apt")
            return s.elevated(s.pkg + " " + o.kind + " apt " + s.q(id))
        if (src === "model" || (src === "agent" && id === "inference")) {
            if (!/^[A-Za-z0-9._:\/-]+$/.test(String(id))) return "false"
            if (src === "agent") return "kwick-agents inference " + (o.kind === "remove" ? "remove" : "install")
            return "kwick-agents inference model " + (o.kind === "remove" ? "rm " : "pull ") + s.q(id)
        }
        if (src === "agent")
            return s.elevated(s.pkg + " " + (o.kind === "remove" ? "remove" : "install") + " agent " + s.q(id))
        if (src === "arch" || src === "aur") {
            if (o.kind === "update") return s.bin + " userjob arch upgrade"
            if (o.kind === "remove") return s.bin + " userjob arch remove " + s.q(id)
            return s.bin + " userjob arch install " + s.q(id) + (src === "aur" ? " --aur" : "") + (o.allowVulnerable ? " --allow-vulnerable" : "") + (src === "aur" && o.commit ? " " + s.q("--commit=" + o.commit) : "")
        }
        return ""
    }

    function enqueue(kind, app, extra) {
        if (!app || !app.key) return
        if (s.ops[app.key]) return
        var o = Object.assign({ kind: kind, app: app, progress: -1, message: kind === "remove" ? "Waiting to remove…" : "Waiting…", queued: true }, extra || {})
        s.setOp(app.key, o)
        s.queue = s.queue.concat([app.key])
        s.next()
    }

    function install(app, extra) { s.enqueue("install", app, extra) }
    function remove(app) { s.enqueue("remove", app) }
    function update(app) { s.enqueue("update", app) }

    function updateAll() {
        var a = { key: "__all__", src: "system", name: "All updates" }
        s.enqueue("updateall", a)
        if ((s.updates.arch || []).length)
            s.enqueue("update", { key: "__arch__", src: "arch", id: "*", name: "Arch packages" })
    }

    function next() {
        if (s.active !== "" || s.queue.length === 0) return
        var key = s.queue[0]
        s.queue = s.queue.slice(1)
        var o = s.ops[key]
        if (!o) { s.next(); return }
        s.active = key
        var cmd = s.command(o)
        s.setOp(key, Object.assign({}, o, { queued: false, auth: cmd.indexOf("pkexec") >= 0, message: o.kind === "remove" ? "Removing…" : o.kind === "install" ? "Installing…" : "Updating…" }))
        s.run(cmd, function (out, code) {
            var done = s.ops[key] || o
            s.active = ""
            s.setOp(key, null)
            var uj = null
            if (cmd.indexOf(s.bin + " userjob") === 0) {
                try { uj = JSON.parse(out) } catch (e) { uj = { ok: false, message: out } }
                if (!uj.ok) { code = uj.rc && uj.rc !== 126 && uj.rc !== 127 ? uj.rc : 1; out = uj.message || uj.error || "" }
            }
            if (code === 126 || code === 127) {
                s.say("Authorization was cancelled.", true)
            } else if (code !== 0) {
                s.say((done.app.name || key) + ": " + (s.lastLine(out) || "the task failed"), true)
            } else {
                if (done.kind === "install") { s.mark(key, true); s.say(done.app.name + " is installed.") }
                else if (done.kind === "remove") { s.mark(key, false); s.say(done.app.name + " was removed.") }
                else s.say((done.kind === "updateall" || done.kind === "updatesys") ? "Updates are installed." : (done.app.name + " is up to date."))
            }
            if (done.after) done.after(code === 0)
            s.revision++
            s.changed(key)
            s.installedLoaded = false
            s.loadUpdates()
            if (s.installedLoaded === false) s.loadInstalled()
            s.next()
        })
    }

    function onJob(j) {
        s.job = j
        if (s.active === "") return
        var o = s.ops[s.active]
        if (!o) return
        var p = -1
        var msg = o.message
        if (j.update && j.update.running && (o.kind === "updateall" || o.kind === "updatesys")) {
            p = j.update.progress
            msg = j.update.message || msg
        } else if (j.running) {
            p = j.progress
            msg = j.message || msg
        }
        if (j.running || (j.update && j.update.running)) s.setOp(s.active, Object.assign({}, o, { progress: p, message: msg, auth: false }))
    }

    function launch(app) {
        s.call("launch " + s.q(app.key) + (app.desktop ? " " + s.q(app.desktop) : ""), function (j) {
            if (!j || !j.ok) s.say("Could not open " + app.name + ".", true)
        })
    }

    function archEnable(cb) {
        s.run(s.bin + " userjob arch enable", function (out, code) {
            s.loadSources(cb)
        })
    }

    function archGet(cb) {
        s.install({ key: "apt:kwick-arch", src: "apt", id: "kwick-arch", pkg: "kwick-arch", name: "Arch Linux support" }, { after: function (ok) {
            if (!ok) { if (cb) cb(); return }
            s.loadSources(function () {
                if (s.archInstalled) s.archEnable(cb)
                else if (cb) cb()
            })
        } })
    }

}
