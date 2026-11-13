pragma Singleton
import QtQuick
import org.kde.plasma.plasma5support as P5

QtObject {
    id: sys

    readonly property string dir: Qt.resolvedUrl(".").toString().replace("file://", "")
    property int counter: 0
    property var callbacks: ({})

    property string layout: "macos"
    property string preset: "subtle"
    property string backend: "kde"
    property string switchMode: "slide"
    property string tabboxMode: "windows"
    property var fx: ({})
    property string compositor: "none"
    property string compositorType: ""
    property string gpuInfo: ""
    property var sessions: ({})
    property var fonts: []
    property var apps: []
    property var gaming: ({})
    property string accentName: "blue"

    property bool dockAvailable: false
    property bool dockFloatingSupported: false
    property string dockPosition: "bottom"
    property int dockSize: 56
    property bool dockAutohide: false
    property bool dockFloating: true
    property var pinned: []

    readonly property var accents: [
        { name: "blue", rgb: "10,132,255", hex: "#0a84ff" },
        { name: "purple", rgb: "175,82,222", hex: "#af52de" },
        { name: "pink", rgb: "255,55,95", hex: "#ff375f" },
        { name: "red", rgb: "255,69,58", hex: "#ff453a" },
        { name: "orange", rgb: "255,159,10", hex: "#ff9f0a" },
        { name: "yellow", rgb: "255,214,10", hex: "#ffd60a" },
        { name: "green", rgb: "48,209,88", hex: "#30d158" },
        { name: "graphite", rgb: "152,152,157", hex: "#98989d" }
    ]

    readonly property QtObject source: P5.DataSource {
        engine: "executable"
        onNewData: (src, data) => {
            disconnectSource(src)
            var f = sys.callbacks[src]
            if (f) {
                delete sys.callbacks[src]
                f(String(data["stdout"]), data["exit code"])
            }
        }
    }

    function run(cmd, cb) {
        var src = cmd + " #" + (sys.counter++)
        if (cb)
            sys.callbacks[src] = cb
        sys.source.connectSource(src)
    }

    function elevated(cmd) {
        return "sudo -n " + cmd + " 2>&1 || pkexec " + cmd
    }

    function terminal(cmd) {
        run("konsole --hold -e sh -c '" + cmd.replace(/'/g, "'\\''") + "'")
    }

    function sections(text) {
        var out = {}
        var cur = ""
        text.split("\n").forEach(function (l) {
            var m = /^\[([a-z]+)\]$/.exec(l)
            if (m) {
                cur = m[1]
                out[cur] = []
            } else if (cur !== "" && l.trim() !== "") {
                out[cur].push(l)
            }
        })
        return out
    }

    function parseState(text) {
        var s = sections(text)
        if (s.layout && s.layout.length) sys.layout = s.layout[0].trim()
        if (s.preset && s.preset.length) sys.preset = s.preset[0].trim()
        var f = {}
        ;(s.status || []).forEach(function (l) {
            var p = l.trim().split(/\s+/)
            if (p.length === 2) f[p[0]] = p[1]
        })
        sys.fx = f
        if (s.backend && s.backend.length) sys.backend = s.backend[0].trim()
        if (s.switch && s.switch.length) sys.switchMode = s.switch[0].trim()
        if (s.tabbox && s.tabbox.length) sys.tabboxMode = s.tabbox[0].trim()
        if (s.check && s.check.length) sys.compositor = s.check[0].trim()
        if (s.type && s.type.length) sys.compositorType = s.type[0].trim()
        sys.gpuInfo = (s.gpu || []).join("\n")
        var ss = {}
        ;(s.sessions || []).forEach(function (l) {
            var p = l.trim().split(/\s+/)
            if (p.length >= 2) ss[p[0]] = p.slice(1).join(" ")
        })
        sys.sessions = ss
        if (s.accent && s.accent.length) {
            var rgb = s.accent[0].trim()
            for (var i = 0; i < sys.accents.length; i++) {
                if (sys.accents[i].rgb === rgb) {
                    sys.accentName = sys.accents[i].name
                    Theme.accent = sys.accents[i].hex
                }
            }
        }
    }

    function parseDock(text) {
        var s = sections(text)
        sys.dockAvailable = !!(s.have && s.have.length)
        var help = (s.help || []).join(" ")
        sys.dockFloatingSupported = /floating/i.test(help)
        ;(s.conf || []).forEach(function (l) {
            var i = l.indexOf("=")
            if (i < 0) return
            var k = l.slice(0, i).trim().toLowerCase()
            var v = l.slice(i + 1).trim().replace(/^"|"$/g, "")
            if (k === "position") sys.dockPosition = v
            else if (k === "size") sys.dockSize = parseInt(v) || 56
            else if (k === "autohide") sys.dockAutohide = /^(on|true|1|yes)$/i.test(v)
            else if (k === "floating") { sys.dockFloating = /^(on|true|1|yes)$/i.test(v); sys.dockFloatingSupported = true }
        })
        var ids = (s.list || []).join(" ").match(/[A-Za-z0-9_.\-]+\.desktop/g)
        sys.pinned = ids ? ids : []
    }

    function parseApps(text) {
        var out = []
        text.split("\n").forEach(function (l) {
            var p = l.split("|")
            if (p.length >= 2 && p[0] !== "")
                out.push({ id: p[0], name: p[1], icon: p[2] || "" })
        })
        sys.apps = out
    }

    function parseFonts(text) {
        var out = []
        text.split("\n").forEach(function (l) {
            var p = l.split("|")
            if (p.length >= 5 && p[1].length < 40 && p[2].length < 40)
                out.push({ layout: p[0], ui: p[1], mono: p[2], uiOk: p[3] === "yes", monoOk: p[4] === "yes" })
        })
        sys.fonts = out
    }

    function parseGaming(text) {
        var g = {}
        text.split("\n").forEach(function (l) {
            var p = l.split("|")
            if (p.length === 2) g[p[0]] = p[1].trim() === "yes"
        })
        sys.gaming = g
    }

    function refresh() {
        run("sh " + dir + "helpers/state.sh", parseState)
    }

    function refreshAll() {
        refresh()
        run("sh " + dir + "helpers/dock.sh", parseDock)
        run("sh " + dir + "helpers/apps.sh", parseApps)
        run("sh " + dir + "helpers/fonts.sh", parseFonts)
        run("sh " + dir + "helpers/gaming.sh", parseGaming)
    }

    function setLayout(l) {
        sys.layout = l
        run("kwick-layout " + l, refresh)
    }

    function setAccent(a) {
        sys.accentName = a.name
        Theme.accent = a.hex
        run("kwriteconfig6 --file kdeglobals --group General --key AccentColor '" + a.rgb + "'; plasma-apply-colorscheme --accent-color '" + a.hex + "'", refresh)
    }

    function setPreset(p) {
        sys.preset = p
        run("kwick-effects " + p, refresh)
    }

    function setSwitch(m) {
        sys.switchMode = m
        sys.preset = "custom"
        run("kwick-effects switch " + m, refresh)
    }

    function setTabbox(m) {
        sys.tabboxMode = m
        run("kwick-effects tabbox " + m, refresh)
    }

    function has(name) {
        return (sys.fx[name] || "na") !== "na"
    }

    function setEffect(name, on) {
        var f = Object.assign({}, sys.fx)
        f[name] = on ? "on" : "off"
        sys.fx = f
        sys.preset = "custom"
        run("kwick-effects set " + name + " " + (on ? "on" : "off"), refresh)
    }

    function dockRun(args) {
        run("kwick-dock " + args + " && kwick-dock apply", function () { run("sh " + dir + "helpers/dock.sh", parseDock) })
    }

    function setDockPosition(p) { sys.dockPosition = p; dockRun("position " + p) }
    function setDockSize(n) { sys.dockSize = n; dockRun("size " + n) }
    function setDockAutohide(on) { sys.dockAutohide = on; dockRun("autohide " + (on ? "on" : "off")) }
    function setDockFloating(on) { sys.dockFloating = on; dockRun("floating " + (on ? "on" : "off")) }
    function pin(id) {
        if (sys.pinned.indexOf(id) < 0) sys.pinned = sys.pinned.concat([id])
        dockRun("pin " + id)
    }
    function unpin(id) {
        sys.pinned = sys.pinned.filter(function (x) { return x !== id })
        dockRun("unpin " + id)
    }
    function movePinned(i, delta) {
        var j = i + delta
        if (j < 0 || j >= sys.pinned.length) return
        var l = sys.pinned.slice()
        var t = l[i]; l[i] = l[j]; l[j] = t
        var old = sys.pinned
        sys.pinned = l
        var cmd = old.map(function (x) { return "kwick-dock unpin " + x }).concat(l.map(function (x) { return "kwick-dock pin " + x })).join("; ")
        run(cmd + "; kwick-dock apply", function () { run("sh " + dir + "helpers/dock.sh", parseDock) })
    }

    function appInfo(id) {
        for (var i = 0; i < sys.apps.length; i++)
            if (sys.apps[i].id === id) return sys.apps[i]
        return { id: id, name: id.replace(/\.desktop$/, ""), icon: "" }
    }

    function setDefaultSession(d) {
        run(elevated("kwick-desktop switch " + d), refresh)
    }
}
