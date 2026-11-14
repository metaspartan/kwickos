pragma Singleton
import QtQuick
import org.kde.plasma.plasma5support as P5

QtObject {
    id: inst

    signal navNext()
    signal navBack()
    signal navTo(int index)
    signal requestInstall()
    signal quitRequested()

    readonly property string dir: Qt.resolvedUrl(".").toString().replace("file://", "")
    property int counter: 0
    property var callbacks: ({})

    property int modal: 0
    property bool dryRun: false
    property string backend: "/usr/sbin/kwick-install"
    property bool backendMissing: false
    property string themeArg: ""

    property var locales: []
    property var keymaps: []
    property var timezones: []
    property var disks: []
    property bool disksLoaded: false
    property string disksError: ""
    property string firmware: ""
    property var bootloaders: []
    property string bootDefault: ""
    property var bootDesc: ({})
    property bool bootTouched: false
    property var keymapLabels: ({})
    property var partitions: []

    property string locale: "en_US.UTF-8"
    property string keymap: "us"
    property bool keymapTouched: false
    property string timezone: "UTC"
    property string layout: "macos"
    property string disk: ""
    property string mode: "erase"
    property string fs: "ext4"
    property bool encrypt: false
    property string passphrase: ""
    property string passphrase2: ""
    property string bootloader: ""
    property string swap: "zram"
    property string rootPart: ""
    property string efiPart: ""
    property string homePart: ""
    property string fullname: ""
    property string user: ""
    property bool userEdited: false
    property string password: ""
    property string password2: ""
    property string hostname: ""
    property bool hostEdited: false
    property bool autologin: false
    property var reservedUsers: ["root", "daemon", "bin", "sys", "sync", "games", "man", "lp", "mail", "news", "uucp", "proxy", "www-data", "backup", "list", "irc", "nobody", "systemd-network", "systemd-resolve", "messagebus", "sddm", "polkitd", "avahi", "kwick", "admin", "sudo", "adm", "users", "video", "audio", "input", "render"]

    property var plan: null
    property string planError: ""
    property string planWarn: ""
    property bool planBlocking: false
    property bool planLoading: false

    property string tmp: ""
    property bool running: false
    property bool finished: false
    property bool succeeded: false
    property real progress: 0
    property string stepTitle: ""
    property string statusText: ""
    property string error: ""
    property int readOffset: 0
    property string partial: ""
    property real startedAt: 0
    property string eta: ""
    property ListModel log: ListModel { }

    readonly property var langNames: ({
        "af": "Afrikaans", "ar": "العربية", "ast": "Asturianu", "be": "Беларуская", "bg": "Български", "bn": "বাংলা", "bs": "Bosanski",
        "ca": "Català", "cs": "Čeština", "cy": "Cymraeg", "da": "Dansk", "de": "Deutsch", "el": "Ελληνικά", "en": "English",
        "eo": "Esperanto", "es": "Español", "et": "Eesti", "eu": "Euskara", "fa": "فارسی", "fi": "Suomi", "fil": "Filipino",
        "fr": "Français", "ga": "Gaeilge", "gl": "Galego", "gu": "ગુજરાતી", "he": "עברית", "hi": "हिन्दी", "hr": "Hrvatski",
        "hu": "Magyar", "hy": "Հայերեն", "id": "Bahasa Indonesia", "is": "Íslenska", "it": "Italiano", "ja": "日本語",
        "ka": "ქართული", "kk": "Қазақ", "km": "ខ្មែរ", "kn": "ಕನ್ನಡ", "ko": "한국어", "ku": "Kurdî", "lt": "Lietuvių",
        "lv": "Latviešu", "mk": "Македонски", "ml": "മലയാളം", "mr": "मराठी", "ms": "Bahasa Melayu", "mt": "Malti",
        "nb": "Norsk bokmål", "ne": "नेपाली", "nl": "Nederlands", "nn": "Norsk nynorsk", "pa": "ਪੰਜਾਬੀ", "pl": "Polski",
        "pt": "Português", "ro": "Română", "ru": "Русский", "si": "සිංහල", "sk": "Slovenčina", "sl": "Slovenščina",
        "sq": "Shqip", "sr": "Српски", "sv": "Svenska", "sw": "Kiswahili", "ta": "தமிழ்", "te": "తెలుగు", "th": "ไทย",
        "tr": "Türkçe", "uk": "Українська", "ur": "اردو", "uz": "Oʻzbek", "vi": "Tiếng Việt", "zh": "中文", "C": "Technical (C)"
    })
    readonly property var countryNames: ({
        "AR": "Argentina", "AT": "Austria", "AU": "Australia", "BE": "Belgium", "BG": "Bulgaria", "BR": "Brazil", "BY": "Belarus",
        "CA": "Canada", "CH": "Switzerland", "CL": "Chile", "CN": "China", "CO": "Colombia", "CZ": "Czechia", "DE": "Germany",
        "DK": "Denmark", "EE": "Estonia", "EG": "Egypt", "ES": "Spain", "FI": "Finland", "FR": "France", "GB": "United Kingdom",
        "GR": "Greece", "HK": "Hong Kong", "HR": "Croatia", "HU": "Hungary", "ID": "Indonesia", "IE": "Ireland", "IL": "Israel",
        "IN": "India", "IR": "Iran", "IS": "Iceland", "IT": "Italy", "JP": "Japan", "KR": "South Korea", "KZ": "Kazakhstan",
        "LT": "Lithuania", "LU": "Luxembourg", "LV": "Latvia", "MX": "Mexico", "MY": "Malaysia", "NG": "Nigeria", "NL": "Netherlands",
        "NO": "Norway", "NZ": "New Zealand", "PE": "Peru", "PH": "Philippines", "PK": "Pakistan", "PL": "Poland", "PT": "Portugal",
        "RO": "Romania", "RS": "Serbia", "RU": "Russia", "SA": "Saudi Arabia", "SE": "Sweden", "SG": "Singapore", "SI": "Slovenia",
        "SK": "Slovakia", "TH": "Thailand", "TR": "Türkiye", "TW": "Taiwan", "UA": "Ukraine", "US": "United States", "VE": "Venezuela",
        "VN": "Vietnam", "ZA": "South Africa"
    })
    readonly property var keymapNames: ({
        "us": "U.S.", "gb": "British", "uk": "British", "de": "German", "fr": "French", "es": "Spanish", "it": "Italian",
        "pt": "Portuguese", "br": "Brazilian", "ch": "Swiss", "at": "Austrian", "be": "Belgian", "nl": "Dutch", "dk": "Danish",
        "no": "Norwegian", "se": "Swedish", "fi": "Finnish", "is": "Icelandic", "ie": "Irish", "pl": "Polish", "cz": "Czech",
        "sk": "Slovak", "hu": "Hungarian", "ro": "Romanian", "bg": "Bulgarian", "ru": "Russian", "ua": "Ukrainian", "by": "Belarusian",
        "gr": "Greek", "tr": "Turkish", "il": "Hebrew", "ara": "Arabic", "ir": "Persian", "in": "Indian", "jp": "Japanese",
        "kr": "Korean", "cn": "Chinese", "tw": "Taiwanese", "th": "Thai", "vn": "Vietnamese", "latam": "Latin American",
        "ca": "Canadian", "cf": "Canadian French", "dvorak": "Dvorak", "colemak": "Colemak", "et": "Estonian", "ee": "Estonian",
        "lt": "Lithuanian", "lv": "Latvian", "si": "Slovenian", "hr": "Croatian", "rs": "Serbian", "mk": "Macedonian",
        "al": "Albanian", "ge": "Georgian", "am": "Armenian", "kz": "Kazakh", "mt": "Maltese", "epo": "Esperanto",
        "fr_CH": "Swiss French", "de_CH": "Swiss German", "sg": "Swiss German", "sf": "Swiss French", "la": "Latin American",
        "qwerty": "QWERTY", "azerty": "AZERTY", "qwertz": "QWERTZ", "mac": "Apple", "jis": "Japanese"
    })
    readonly property var bootInfo: ({
        "grub": { name: "GRUB", sub: "Works everywhere and can start other operating systems" },
        "systemd-boot": { name: "systemd-boot", sub: "A simple, fast boot menu for UEFI computers" },
        "efistub": { name: "EFI stub", sub: "The firmware starts KwickOS directly, with no menu" },
        "limine": { name: "Limine", sub: "A modern, minimal boot loader for UEFI and BIOS" }
    })

    readonly property QtObject source: P5.DataSource {
        engine: "executable"
        onNewData: (src, data) => {
            disconnectSource(src)
            var f = inst.callbacks[src]
            if (f) {
                delete inst.callbacks[src]
                f(String(data["stdout"] || ""), data["exit code"], String(data["stderr"] || ""))
            }
        }
    }

    readonly property Timer poller: Timer {
        interval: 400
        repeat: true
        running: inst.running && inst.tmp !== ""
        onTriggered: inst.poll()
    }

    function run(cmd, cb) {
        var src = cmd + " #" + (inst.counter++)
        if (cb)
            inst.callbacks[src] = cb
        inst.source.connectSource(src)
    }

    function q(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    function helper(name) {
        return "sh " + q(dir + "helpers/" + name)
    }

    function parseArgs() {
        var a = Qt.application.arguments
        for (var i = 0; i < a.length; i++) {
            var s = String(a[i])
            if (s === "--dry-run") inst.dryRun = true
            else if (s.indexOf("--backend=") === 0) inst.backend = s.slice(10)
            else if (s.indexOf("--theme=") === 0) inst.themeArg = s.slice(8)
        }
        if (inst.themeArg === "light") Theme.dark = false
        else if (inst.themeArg === "dark") Theme.dark = true
        else Theme.dark = Qt.styleHints.colorScheme !== Qt.ColorScheme.Light
    }

    function lines(text) {
        return text.split("\n").map(function (l) { return l.trim() }).filter(function (l) { return l.length > 0 && l.charAt(0) !== "#" })
    }

    function load() {
        parseArgs()
        run(helper("sysinfo.sh"), function (out) {
            out.split("\n").forEach(function (l) {
                var i = l.indexOf("=")
                if (i < 0) return
                var k = l.slice(0, i), v = l.slice(i + 1).trim()
                if (v === "") return
                if (k === "timezone") inst.timezone = v
                else if (k === "keymap") inst.keymap = v
                else if (k === "lang" && /^[a-zA-Z]{2,3}(_[A-Z]{2})?/.test(v)) inst.locale = v.replace(/\.utf-?8/i, ".UTF-8")
                else if (k === "firmware" && inst.firmware === "") inst.firmware = v
            })
            run("test -x " + q(inst.backend) + " && echo yes", function (o) {
                inst.backendMissing = o.trim() !== "yes"
                if (!inst.backendMissing) loadBackend()
            })
        })
    }

    function loadBackend() {
        run(q(inst.backend) + " locales", function (out) {
            var seen = {}
            var l = lines(out).filter(function (x) {
                var k = x.split(/\s+/)[0]
                if (seen[k]) return false
                seen[k] = true
                return /utf-?8/i.test(k) || k.indexOf(".") < 0
            }).map(function (x) { return x.split(/\s+/)[0] })
            l.sort(function (a, b) { return localeName(a).localeCompare(localeName(b)) })
            inst.locales = l
            if (l.length && l.indexOf(inst.locale) < 0) {
                var m = l.filter(function (x) { return x.toLowerCase().replace("utf8", "utf-8") === inst.locale.toLowerCase() })
                inst.locale = m.length ? m[0] : (l.indexOf("en_US.UTF-8") >= 0 ? "en_US.UTF-8" : l[0])
            }
        })
        run(q(inst.backend) + " keymaps --names", function (out) {
            var names = {}
            var l = lines(out).map(function (x) {
                var p = x.split("\t")
                var k = p[0].trim().split(/\s+/)[0]
                if (p.length > 1 && p[1].trim() !== "") names[k] = p[1].trim()
                return k
            })
            inst.keymapLabels = names
            l.sort(function (a, b) { return keymapName(a).localeCompare(keymapName(b)) })
            inst.keymaps = l
            if (l.length && l.indexOf(inst.keymap) < 0) inst.keymap = l.indexOf("us") >= 0 ? "us" : l[0]
        })
        run(q(inst.backend) + " timezones", function (out) {
            var l = lines(out).map(function (x) { return x.split(/\s+/)[0] })
            inst.timezones = l
            if (l.length && l.indexOf(inst.timezone) < 0) {
                var alt = ["Etc/UTC", "UTC", "Europe/London"].filter(function (z) { return l.indexOf(z) >= 0 })
                inst.timezone = alt.length ? alt[0] : l[0]
            }
        })
        loadDisks()
        loadBoot()
    }

    function loadBoot() {
        var a = " bootloaders --json --fs " + q(inst.fs) + (inst.encrypt && inst.mode === "erase" ? " --encrypt" : "")
        run(helper("priv.sh") + " " + q(inst.backend) + a, function (out) { parseBoot(out) })
    }

    onFsChanged: if (!inst.backendMissing && inst.disksLoaded) loadBoot()
    onEncryptChanged: if (!inst.backendMissing && inst.disksLoaded) loadBoot()

    function loadDisks() {
        inst.disksLoaded = false
        run(helper("priv.sh") + " " + q(inst.backend) + " disks --json", function (out, code, err) {
            var arr = []
            try {
                var j = JSON.parse(out)
                arr = Array.isArray(j) ? j : (j.disks || [])
                inst.disksError = ""
            } catch (e) {
                inst.disksError = (err || out).trim().split("\n")[0] || "The list of disks could not be read."
            }
            inst.disks = arr.map(function (d) {
                return {
                    path: String(d.path || ""),
                    size: Number(d.size_bytes || 0),
                    sizeHuman: String(d.size_human || ""),
                    model: String(d.model || "").trim(),
                    transport: String(d.transport || "").toLowerCase(),
                    removable: d.removable === true || d.removable === 1 || d.removable === "1" || d.removable === "true",
                    live: d.is_live_medium === true || d.is_live_medium === 1 || d.is_live_medium === "true"
                }
            })
            inst.disksLoaded = true
            var ok = inst.disks.filter(function (d) { return usable(d) })
            if (!ok.some(function (d) { return d.path === inst.disk }))
                inst.disk = ok.length === 1 ? ok[0].path : ""
        })
    }

    function parseBoot(out) {
        var j = {}
        try { j = JSON.parse(out) } catch (e) { j = {} }
        var fw = j.firmware || j.mode || j.boot_mode || ""
        if (fw) inst.firmware = String(fw).toLowerCase()
        var list = j.available || j.bootloaders || j.options || []
        if (!Array.isArray(list)) list = Object.keys(list)
        var desc = {}
        var ids = list.map(function (b) {
            if (typeof b === "string") return b
            var k = String(b.id || b.name || "")
            if (b.description) desc[k] = String(b.description)
            if (b.name) desc[k + "#name"] = String(b.name)
            return k
        }).filter(function (b) { return b !== "" && (typeof b !== "object") })
        list.forEach(function (b) {
            if (typeof b === "object" && b.available === false) {
                var k = String(b.id || b.name || "")
                ids = ids.filter(function (x) { return x !== k })
            }
        })
        var def = String(j["default"] || j.recommended || (ids.length ? ids[0] : ""))
        if (def && ids.indexOf(def) < 0) ids.unshift(def)
        ids.sort(function (a, b) { return (a === def ? 0 : 1) - (b === def ? 0 : 1) })
        inst.bootDesc = desc
        inst.bootDefault = def
        inst.bootloaders = ids
        if (!inst.bootTouched || inst.bootloader === "" || ids.indexOf(inst.bootloader) < 0) inst.bootloader = def
    }

    function loadPartitions() {
        if (inst.disk === "") { inst.partitions = []; return }
        run(helper("parts.sh") + " " + q(inst.disk), function (out) {
            var parts = []
            try {
                var j = JSON.parse(out)
                var walk = function (n) {
                    (n || []).forEach(function (b) {
                        if (b.type === "part") parts.push({
                            path: String(b.path || ""),
                            size: Number(b.size || 0),
                            fstype: String(b.fstype || ""),
                            parttype: String(b.parttype || "").toLowerCase(),
                            label: String(b.partlabel || b.label || "")
                        })
                        walk(b.children)
                    })
                }
                walk(j.blockdevices)
            } catch (e) { }
            inst.partitions = parts
            var paths = parts.map(function (p) { return p.path })
            if (paths.indexOf(inst.efiPart) < 0) {
                var esp = parts.filter(function (p) { return p.parttype === "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" || p.parttype === "0xef" })
                if (!esp.length) esp = parts.filter(function (p) { return p.fstype === "vfat" && p.size < 4e9 })
                inst.efiPart = esp.length ? esp[0].path : ""
            }
            if (paths.indexOf(inst.rootPart) < 0) {
                var cand = parts.filter(function (p) { return p.path !== inst.efiPart && p.fstype !== "swap" })
                cand.sort(function (a, b) { return b.size - a.size })
                inst.rootPart = cand.length ? cand[0].path : ""
            }
            if (paths.indexOf(inst.homePart) < 0) inst.homePart = ""
        })
    }

    function usable(d) {
        return !d.live && d.size >= minDiskBytes
    }
    readonly property real minDiskBytes: 8e9

    function diskByPath(p) {
        for (var i = 0; i < inst.disks.length; i++)
            if (inst.disks[i].path === p) return inst.disks[i]
        return null
    }

    function diskTitle(d) {
        if (!d) return ""
        return d.model !== "" ? d.model : d.path.replace("/dev/", "")
    }

    function bytes(n) {
        if (!n || n <= 0) return ""
        var u = ["bytes", "KB", "MB", "GB", "TB", "PB"]
        var i = 0
        while (n >= 1000 && i < u.length - 1) { n /= 1000; i++ }
        var s = n >= 100 || i === 0 ? Math.round(n).toString() : n.toFixed(1).replace(/\.0$/, "")
        return s + " " + u[i]
    }

    function transportName(d) {
        var t = d.transport
        if (t === "nvme") return "NVMe"
        if (t === "usb") return "USB"
        if (t === "sata" || t === "ata") return "SATA"
        if (t === "virtio") return "Virtual disk"
        if (t === "mmc") return "SD card"
        if (t === "scsi" || t === "sas") return "SCSI"
        return t ? t.toUpperCase() : (d.removable ? "Removable" : "Internal")
    }

    function localeName(code) {
        var base = String(code).split(".")[0].split("@")[0]
        var p = base.split("_")
        var lang = langNames[p[0]] || p[0]
        if (p.length > 1) return lang + " (" + (countryNames[p[1]] || p[1]) + ")"
        return lang
    }

    function keymapName(code) {
        var c = String(code)
        if (keymapLabels[c]) return keymapLabels[c]
        if (keymapNames[c]) return keymapNames[c]
        var p = c.split(/[-:(_]/)
        var base = keymapNames[p[0]] || p[0].toUpperCase()
        var rest = c.slice(p[0].length).replace(/^[-:(_]/, "").replace(/\)$/, "").replace(/[-_:]/g, " ").trim()
        return rest ? base + " – " + rest : base
    }

    function zoneCity(z) {
        var p = String(z).split("/")
        return p[p.length - 1].replace(/_/g, " ")
    }

    function zoneRegion(z) {
        var p = String(z).split("/")
        return p.length > 1 ? p.slice(0, p.length - 1).join(" / ").replace(/_/g, " ") : "Universal"
    }

    function layoutName(l) {
        return l === "windows" ? "Windows 11" : l === "linux" ? "Linux" : "macOS"
    }

    function fsName(f) {
        return f === "btrfs" ? "Btrfs" : f === "xfs" ? "XFS" : "ext4"
    }

    function swapName(s) {
        if (s === "none") return "No swap"
        if (s === "zram") return "Compressed memory (zram)"
        return "Swap file, " + s.replace("file:", "")
    }

    function bootName(b) {
        return bootInfo[b] ? bootInfo[b].name : (bootDesc[b + "#name"] || b)
    }

    function bootSub(b) {
        return bootDesc[b] || (bootInfo[b] ? bootInfo[b].sub : "")
    }

    function deriveUser(name) {
        var s = String(name)
        try { s = s.normalize("NFD") } catch (e) { }
        s = s.replace(/[̀-ͯ]/g, "").toLowerCase()
        var w = s.split(/\s+/).filter(function (x) { return x.length > 0 })
        var u = (w.length ? w[0] : "").replace(/[^a-z0-9_-]/g, "")
        u = u.replace(/^[^a-z_]+/, "")
        if (reservedUsers.indexOf(u) >= 0) u = u + (w.length > 1 ? w[1].replace(/[^a-z0-9]/g, "").charAt(0) : "1")
        return u.slice(0, 32)
    }

    function deriveHost(u) {
        var base = String(u).toLowerCase().replace(/[^a-z0-9-]/g, "")
        return (base ? base + "-" : "") + "kwickos"
    }

    function userError() {
        if (inst.user === "") return "Enter an account name."
        if (!/^[a-z_][a-z0-9_-]*$/.test(inst.user)) return "Use lowercase letters, digits, - and _, starting with a letter."
        if (inst.user.length > 32) return "Use 32 characters or fewer."
        if (reservedUsers.indexOf(inst.user) >= 0) return "“" + inst.user + "” is reserved by the system."
        return ""
    }

    function hostError() {
        if (inst.hostname === "") return "Enter a computer name."
        if (inst.hostname.length > 63) return "Use 63 characters or fewer."
        if (!/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/i.test(inst.hostname)) return "Use letters, digits and hyphens. It can’t start or end with a hyphen."
        return ""
    }

    function strength(p) {
        if (!p) return 0
        var cls = 0
        if (/[a-z]/.test(p)) cls++
        if (/[A-Z]/.test(p)) cls++
        if (/[0-9]/.test(p)) cls++
        if (/[^a-zA-Z0-9]/.test(p)) cls++
        var s = 0
        if (p.length >= 8) s++
        if (p.length >= 12) s++
        if (cls >= 3) s++
        if (p.length >= 16 && cls >= 2) s++
        if (/^(.)\1+$/.test(p) || /^(password|12345678|qwerty|letmein|kwickos)/i.test(p)) s = 0
        return Math.max(1, Math.min(4, s))
    }

    function accountValid() {
        return inst.fullname.trim() !== "" && userError() === "" && hostError() === ""
            && inst.password !== "" && inst.password === inst.password2
    }

    function diskValid() {
        var d = diskByPath(inst.disk)
        if (!d || !usable(d)) return false
        if (inst.mode === "manual") {
            if (inst.rootPart === "") return false
            if (inst.firmware === "uefi" && inst.efiPart === "") return false
            if (inst.homePart !== "" && (inst.homePart === inst.rootPart || inst.homePart === inst.efiPart)) return false
            if (inst.rootPart === inst.efiPart) return false
        }
        if (inst.encrypt && inst.mode === "erase" && (inst.passphrase.length < 8 || inst.passphrase !== inst.passphrase2)) return false
        return true
    }

    function opts() {
        var a = ["--disk", inst.disk, "--mode", inst.mode]
        if (inst.mode === "manual") {
            a.push("--root-part", inst.rootPart)
            if (inst.efiPart !== "") a.push("--efi-part", inst.efiPart)
            if (inst.homePart !== "") a.push("--home-part", inst.homePart)
        }
        a.push("--fs", inst.fs)
        if (inst.encrypt && inst.mode === "erase") a.push("--encrypt")
        if (inst.bootloader !== "") a.push("--bootloader", inst.bootloader)
        a.push("--hostname", inst.hostname, "--user", inst.user, "--fullname", inst.fullname.trim(),
               "--autologin", inst.autologin ? "yes" : "no", "--timezone", inst.timezone, "--locale", inst.locale,
               "--keymap", inst.keymap, "--edition", "desktop", "--layout", inst.layout, "--swap", inst.swap)
        if (inst.dryRun) a.push("--dry-run")
        return a
    }

    function quoted(a) {
        return a.map(function (x) { return q(x) }).join(" ")
    }

    function loadPlan() {
        inst.planLoading = true
        inst.plan = null
        inst.planError = ""
        inst.planWarn = ""
        inst.planBlocking = false
        run(helper("priv.sh") + " " + q(inst.backend) + " plan " + quoted(opts()), function (out, code, err) {
            inst.planLoading = false
            var j = null
            try { j = JSON.parse(out) } catch (e) { j = null }
            if (j) {
                inst.plan = j
                var e = j.error || (Array.isArray(j.errors) && j.errors.length ? j.errors.join("\n") : "")
                if (!e && j.ok === false) e = "The installer can’t use these settings."
                if (e) { inst.planError = String(e); inst.planBlocking = true }
                else if (Array.isArray(j.warnings) && j.warnings.length) {
                    var w = String(j.warnings.join(". "))
                    inst.planWarn = w.charAt(0).toUpperCase() + w.slice(1) + "."
                }
            } else if (code !== 0) {
                var m = (err + "\n" + out).split("\n").map(function (x) { return x.replace(/^ERROR\s+/, "").trim() }).filter(function (x) { return x !== "" })
                inst.planError = m.length ? m[0] : "The installation plan could not be checked."
                inst.planBlocking = false
            }
        })
    }

    function planNotes() {
        var p = inst.plan
        if (!p) return []
        var src = p.summary || p.steps || p.actions || p.notes || []
        if (!Array.isArray(src)) return []
        return src.map(function (s) {
            if (typeof s === "string") return s
            return String(s.title || s.description || s.text || s.name || JSON.stringify(s))
        }).slice(0, 12)
    }

    function applyKeymap() {
        run(helper("keymap.sh") + " " + q(inst.keymap))
    }

    function writeSecret(path, text, cb) {
        var x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState === XMLHttpRequest.DONE) cb()
        }
        x.open("PUT", "file://" + path)
        x.send(text)
    }

    function fail(msg) {
        inst.error = msg
        inst.running = false
        inst.finished = true
        inst.succeeded = false
    }

    function start() {
        inst.log.clear()
        inst.progress = 0
        inst.stepTitle = "Preparing…"
        inst.statusText = ""
        inst.error = ""
        inst.finished = false
        inst.succeeded = false
        inst.readOffset = 0
        inst.partial = ""
        inst.eta = ""
        inst.startedAt = Date.now()
        inst.running = true
        inst.tmp = ""
        var needLuks = inst.encrypt && inst.mode === "erase"
        run(helper("mktemp.sh"), function (out, code) {
            var d = out.trim()
            if (code !== 0 || d === "") { fail("A private working folder could not be created."); return }
            writeSecret(d + "/pw", inst.password + "\n", function () {
                var next = function () {
                    run(helper("checksecrets.sh") + " " + q(d) + (needLuks ? " luks" : ""), function (o, c) {
                        if (c !== 0) {
                            run("rm -rf " + q(d))
                            fail("Your password could not be handed to the installer safely.")
                            return
                        }
                        var a = opts()
                        a.push("--password-file", d + "/pw")
                        if (needLuks) a.push("--passphrase-file", d + "/luks")
                        inst.tmp = d
                        run("setsid " + helper("run.sh") + " " + q(inst.backend) + " " + q(d) + " " + quoted(a) + " </dev/null >/dev/null 2>&1 &")
                    })
                }
                if (needLuks) writeSecret(d + "/luks", inst.passphrase + "\n", next)
                else next()
            })
        })
    }

    function addLog(t) {
        inst.log.append({ line: t })
        if (inst.log.count > 4000) inst.log.remove(0, 500)
    }

    function handle(l) {
        var m
        if ((m = /^PROGRESS\s+(\d+(?:\.\d+)?)\s*(.*)$/.exec(l))) {
            inst.progress = Math.max(inst.progress, Math.min(1, parseFloat(m[1]) / 100))
            if (m[2]) inst.statusText = m[2]
            updateEta()
        } else if ((m = /^STEP\s+(\S+)\s*(.*)$/.exec(l))) {
            inst.stepTitle = m[2] || m[1]
            inst.statusText = ""
            addLog("▸ " + inst.stepTitle)
        } else if ((m = /^LOG\s?(.*)$/.exec(l))) {
            addLog(m[1])
        } else if ((m = /^ERROR\s*(.*)$/.exec(l))) {
            inst.error = m[1] || "The installation failed."
            addLog("Error: " + inst.error)
        } else if (l === "DONE") {
            inst.progress = 1
            inst.succeeded = inst.error === ""
        } else if ((m = /^EXIT\s+(\d+)$/.exec(l))) {
            var rc = parseInt(m[1])
            if (rc !== 0 && inst.error === "") inst.error = "The installer stopped unexpectedly (code " + rc + ")."
            if (rc === 0 && inst.error === "") { inst.succeeded = true; inst.progress = 1 }
            if (rc !== 0) inst.succeeded = false
            inst.running = false
            inst.finished = true
            run("rm -rf " + q(inst.tmp))
        } else if (l !== "") {
            addLog(l)
        }
    }

    function updateEta() {
        var el = (Date.now() - inst.startedAt) / 1000
        if (inst.progress < 0.08 || el < 20) { inst.eta = ""; return }
        var left = el / inst.progress * (1 - inst.progress)
        if (left < 50) inst.eta = "Less than a minute remaining"
        else inst.eta = "About " + Math.round(left / 60) + " minute" + (Math.round(left / 60) === 1 ? "" : "s") + " remaining"
    }

    function poll() {
        var x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE) return
            var t = String(x.responseText || "")
            if (t.length <= inst.readOffset) return
            var chunk = inst.partial + t.slice(inst.readOffset)
            inst.readOffset = t.length
            var parts = chunk.split("\n")
            inst.partial = parts.pop()
            parts.forEach(function (l) { handle(l.replace(/\r$/, "")) })
        }
        x.open("GET", "file://" + inst.tmp + "/out")
        x.send()
    }

    function reboot() {
        run(helper("reboot.sh"))
    }

    function cleanup(cb) {
        if (inst.tmp !== "" && !inst.running) run("rm -rf " + q(inst.tmp), cb)
        else if (cb) cb()
    }
}
