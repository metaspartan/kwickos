import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: page
    spacing: 10

    property bool available: true
    property bool loaded: false
    property var st: null
    property var models: []
    property var pulling: ({})
    property bool copied: false
    property string hfError: ""
    property string askCmd: ""

    readonly property bool supported: st !== null
    readonly property var engine: (st && st.engine) || ({})
    readonly property bool installed: supported && !!engine.installed
    readonly property var hw: (st && st.hardware) || ({})
    readonly property var devices: hw.devices || []
    readonly property var bk: (st && st.backend) || ({})
    readonly property var svc: (st && st.service) || ({})
    readonly property var cur: (st && st.model) || null
    readonly property var issues: (st && st.issues) || []
    readonly property bool running: !!svc.running
    readonly property var idRe: /^[A-Za-z0-9._:\/-]+$/
    readonly property var hfRe: /^hf:\/\/[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+(:[A-Za-z0-9._-]+)?$/
    readonly property var nameRe: /^[A-Za-z0-9._-]+$/
    readonly property var backendTitles: ({ "auto": "Automatic", "cpu": "CPU only", "vulkan": "Vulkan", "cuda12": "NVIDIA CUDA 12", "cuda13": "NVIDIA CUDA 13", "rocm": "AMD ROCm" })
    readonly property var backendSubs: ({ "auto": "The best engine for this hardware", "cpu": "Slower, works everywhere", "vulkan": "AMD, Intel and NVIDIA GPUs", "cuda12": "NVIDIA drivers 525 to 579", "cuda13": "NVIDIA drivers 580 and newer", "rocm": "Radeon GPUs with ROCm 7 installed" })
    readonly property var backendOptions: ["auto"].concat(bk.available || []).map(function (id) { return { id: id, label: backendTitles[id] || id, sub: backendSubs[id] || "" } })
    readonly property var contexts: [{ id: "32768", label: "32K" }, { id: "65536", label: "64K" }, { id: "131072", label: "128K" }, { id: "262144", label: "256K" }]
    readonly property var fitTitles: ({ "gpu": "Fits GPU", "moe-offload": "Needs RAM offload", "cpu-split": "Needs RAM offload", "cpu": "Runs on CPU", "no": "Does not fit" })
    readonly property var agentRows: ((st && st.agents) || []).filter(function (a) { return nameRe.test(String(a.name)) })

    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function inf(args) { return "kwick-agents inference " + args }

    function gb(mb) {
        var g = mb / 1024
        return (g >= 10 ? Math.round(g) : Math.round(g * 10) / 10) + " GB"
    }

    function bytes(b) {
        if (b >= 1073741824) return (Math.round(b / 107374182.4) / 10) + " GB"
        return Math.round(b / 1048576) + " MB"
    }

    function ctxLabel(n) {
        return n >= 1024 ? Math.round(n / 1024) + "K" : String(n)
    }

    function backendName(id) {
        return backendTitles[id] || id || ""
    }

    function hardwareLine() {
        var p = []
        var named = devices.filter(function (d) { return d.name })
        if (named.length > 0) {
            p.push(named[0].name + (named.length > 1 ? " + " + (named.length - 1) + " more" : ""))
            if (hw.vram_mb > 0 && !hw.unified) p.push(gb(hw.vram_mb) + " VRAM")
        } else {
            p.push("No supported GPU")
        }
        if (hw.ram_mb > 0) p.push(gb(hw.ram_mb) + (hw.unified ? " unified memory" : " RAM"))
        if (named.length > 0 && named[0].driver_version) p.push("driver " + named[0].driver_version)
        return p.join("  •  ")
    }

    function verdictOf(m) {
        var f = m.fit
        if (!f || !f.verdict) return ""
        if ((f.verdict === "gpu" || f.verdict === "cpu") && f.budget_mb > 0 && f.need_mb > f.budget_mb) return "no"
        return f.verdict
    }

    function fitText(m) {
        var v = verdictOf(m)
        if (v === "") return m.fit_error ? "Not checked yet" : ""
        var t = fitTitles[v] || v
        var f = m.fit
        if (f.need_mb > 0) t += "  •  needs " + gb(f.need_mb) + (f.budget_mb > 0 ? ", " + gb(f.budget_mb) + " available" : "")
        return t
    }

    function metaText(m) {
        var p = []
        if (m.quant) p.push(m.quant)
        if (m.size > 0) p.push(bytes(m.size))
        if (m.license) p.push(m.license + (m.commercial_ok === false ? ", no commercial use" : ""))
        return p.join("  •  ")
    }

    function load() {
        Sys.run("sh " + Sys.dir + "helpers/inference.sh", function (out) {
            var d
            try { d = JSON.parse(out) } catch (e) { return }
            page.available = d.available !== false
            page.loaded = true
            if (!page.available) return
            page.st = d.status && typeof d.status === "object" ? d.status : null
            page.models = ((d.models && d.models.models) || []).filter(function (m) { return idRe.test(String(m.id)) })
        })
    }

    function act(cmd) {
        Sys.run(cmd + " 2>&1", function () { page.load() })
    }

    function confirm(title, body, label, danger, cmd) {
        ask.title = title
        ask.body = body
        ask.confirmText = label
        ask.danger = danger
        page.askCmd = cmd
        ask.open()
    }

    function copyUrl() {
        copier.text = String(svc.url || "")
        copier.selectAll()
        copier.copy()
        page.copied = true
        copiedTimer.restart()
    }

    function setPulling(id, on) {
        var p = Object.assign({}, page.pulling)
        if (on) p[id] = true
        else delete p[id]
        page.pulling = p
    }

    function pull(m) {
        if (!idRe.test(String(m.id))) return
        setPulling(m.id, true)
        Sys.run(inf("model pull " + q(m.id)) + " 2>&1", function () { page.setPulling(m.id, false); page.load() })
    }

    function use(m) {
        if (idRe.test(String(m.id))) act(inf("use " + q(m.id)))
    }

    function setContext(n) {
        if (page.cur && idRe.test(String(page.cur.id))) act(inf("use " + q(page.cur.id) + " --ctx " + n))
    }

    function removeModel(m) {
        if (!idRe.test(String(m.id))) return
        confirm("Remove " + m.title + "?", "The downloaded file is deleted from this computer. You can download it again later.", "Remove", true, inf("model rm " + q(m.id)))
    }

    function connect(a, on) {
        if (!nameRe.test(String(a.name))) return
        act(inf((on ? "connect " : "disconnect ") + q(a.name)))
    }

    function runLocal(a) {
        if (!nameRe.test(String(a.name))) return
        var cmd = "kwick-terminal -e kwick-agents run --local " + q(a.name)
        if (a.name === "claude-code")
            confirm("Run Claude Code on a local model?", "Anthropic does not support Claude Code with models other than Claude. Tool use can fail and answers can be slower or worse. Only this run uses the local model.", "Run Anyway", true, cmd)
        else
            Sys.run(cmd)
    }

    function addHf() {
        var v = hfInput.text.trim()
        if (hfRe.test(v)) {
            page.hfError = ""
            act(inf("model add " + q(v)))
        } else {
            page.hfError = "Use the form hf://owner/name or hf://owner/name:Q4_K_M"
            Qt.callLater(function () { hfSheet.open() })
        }
    }

    function pickBackend(id) {
        if (id !== "auto" && !nameRe.test(id)) return
        Sys.terminal(inf("install" + (id === "auto" ? "" : " --backend " + q(id))), function () { page.load() })
    }

    Component.onCompleted: load()

    Timer {
        interval: page.svc.running && !page.svc.healthy ? 1500 : 4000
        running: page.visible
        repeat: true
        onTriggered: page.load()
    }

    Timer { id: copiedTimer; interval: 1600; onTriggered: page.copied = false }

    TextInput { id: copier; visible: false }

    Card {
        visible: page.loaded && !page.available
        Cell {
            last: true
            title: "AI agent support is not installed"
            subtitle: "Local models run through kwick-agents: it installs the engine, downloads checked models and connects your coding agents to them."
            Btn { text: "Install"; primary: true; onClicked: { Sys.terminal(Sys.elevated("apt-get install -y kwick-agents"), function () { page.load() }) } }
        }
    }

    Card {
        visible: page.loaded && page.available && !page.supported
        Cell {
            last: true
            title: "Local models are not in this version of kwick-agents"
            subtitle: "Update kwick-agents in Software Update to run models on this computer."
            Btn { text: "Software Update…"; onClicked: Sys.run("kwick-settings software-update") }
        }
    }

    SectionTitle { text: "SET UP"; visible: page.loaded && page.supported && !page.installed }
    Card {
        visible: page.loaded && page.supported && !page.installed
        Cell {
            title: "Run AI models on this computer"
            subtitle: "Your prompts and code never leave it. The server is off until you turn it on, only this computer can reach it, and models are checked against published hashes before they are used."
        }
        Cell {
            title: "Detected hardware"
            subtitle: page.hardwareLine()
        }
        Cell {
            title: "Recommended engine"
            subtitle: (page.engine.name || "llama.cpp") + (page.engine.pinned_build ? " " + page.engine.pinned_build : "") + (page.bk.recommended ? " with the " + page.backendName(page.bk.recommended) + " backend" : "") + (page.bk.reason ? ". " + page.bk.reason : "")
            Text { visible: page.bk.download_size > 0; text: page.bytes(page.bk.download_size); color: Theme.sub; font.family: Theme.sans; font.pixelSize: 12 }
        }
        Cell {
            last: true
            title: "Set up local models"
            subtitle: "Downloads and verifies the engine for you only. No models are downloaded yet and nothing needs administrator rights."
            Btn { text: "Set up local models"; primary: true; onClicked: Sys.terminal(page.inf("install"), function () { page.load() }) }
        }
    }

    Card {
        visible: page.installed
        Cell {
            last: true
            title: "Hardware"
            subtitle: page.hardwareLine()
        }
    }

    SectionTitle { text: "ENGINE"; visible: page.installed }
    Card {
        visible: page.installed
        Cell {
            title: (page.engine.name || "llama.cpp") + (page.engine.build ? " " + page.engine.build : "")
            subtitle: page.backendName(page.engine.backend) + " backend" + (page.engine.smoke_ok === false ? "  •  the start-up check failed, see Check Setup below" : "") + (page.engine.update_available ? "  •  " + page.engine.pinned_build + " is available" : "")
            Btn { visible: !!page.engine.update_available; text: "Update"; primary: true; onClicked: Sys.terminal(page.inf("update"), function () { page.load() }) }
        }
        Cell {
            last: true
            title: "Backend"
            subtitle: page.bk.override ? "Fixed by you. Switching downloads that engine." : "Chosen automatically from your hardware. Switching downloads that engine."
            Pick {
                options: page.backendOptions
                current: page.bk.override || "auto"
                onPicked: (id) => page.pickBackend(id)
            }
        }
    }

    SectionTitle { text: "SERVER"; visible: page.installed }
    Card {
        visible: page.installed
        Cell {
            title: "Local model server"
            subtitle: page.running && page.svc.healthy ? "Running on this computer only" + (page.svc.enabled ? ", starts at login" : "") + (page.svc.idle_seconds > 0 ? ", model leaves memory after " + Math.round(page.svc.idle_seconds / 60) + " minutes idle" : "")
                    : page.running ? "Starting and loading the model…"
                    : page.svc.enabled ? "Not running. It should start at login: check the logs under Advanced."
                    : "Off. Turn it on when an agent needs a local model."
            Pill {
                text: page.running && page.svc.healthy ? "Running" : page.running ? "Starting" : page.svc.enabled ? "Stopped" : "Off"
                tone: page.running && page.svc.healthy ? "good" : page.running ? "warn" : page.svc.enabled ? "bad" : "neutral"
            }
            Toggle { checked: page.running || !!page.svc.enabled; onToggled: (v) => page.act(page.inf("service " + (v ? "enable" : "disable"))) }
        }
        Cell {
            title: "Endpoint"
            subtitle: (page.svc.url || "http://127.0.0.1:11435/v1") + "  •  model name " + (page.svc.alias || "local")
            Btn { text: page.copied ? "Copied" : "Copy URL"; onClicked: page.copyUrl() }
        }
        Cell {
            last: true
            title: "API key"
            subtitle: "Kept in your keystore and handed to every agent kwick-agents starts. It is never shown."
            Btn { text: "Rotate Key…"; onClicked: page.confirm("Rotate the API key?", "The server restarts and connected agents get the new key automatically. Anything else that used the old key stops working until you give it the new one.", "Rotate", false, page.inf("key rotate")) }
        }
    }

    Card {
        visible: page.installed && page.issues.length > 0
        Repeater {
            model: page.issues
            delegate: Cell {
                required property var modelData
                required property int index
                last: index === page.issues.length - 1
                title: modelData.message
                titleColor: Theme.warn
            }
        }
    }

    SectionTitle { text: "MODELS"; visible: page.installed }
    Card {
        visible: page.installed
        Cell {
            visible: page.models.length === 0
            title: "No models listed yet"
            subtitle: "Add one from Hugging Face below."
        }
        Repeater {
            model: page.models
            delegate: Item {
                id: mr
                required property var modelData
                required property int index
                readonly property bool busy: !!page.pulling[modelData.id]
                readonly property string verdict: page.verdictOf(modelData)
                Layout.fillWidth: true
                implicitHeight: Math.max(64, rowBody.implicitHeight + 24)

                RowLayout {
                    id: rowBody
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text { Layout.fillWidth: true; text: mr.modelData.title || mr.modelData.id; color: Theme.text; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight }
                        Text { Layout.fillWidth: true; text: page.metaText(mr.modelData); color: Theme.sub; font.family: Theme.sans; font.pixelSize: 12; elide: Text.ElideRight }
                        Text {
                            visible: text !== "" && !mr.busy
                            Layout.fillWidth: true
                            text: page.fitText(mr.modelData)
                            color: mr.verdict === "gpu" ? Theme.good : mr.verdict === "no" ? Theme.bad : mr.verdict === "" ? Theme.sub : Theme.warn
                            font.family: Theme.sans
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        RowLayout {
                            visible: mr.busy
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            spacing: 10
                            Meter { value: -1 }
                            Text { text: "Downloading and verifying " + (mr.modelData.size > 0 ? page.bytes(mr.modelData.size) : "") + "…"; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 12 }
                        }
                    }

                    Btn {
                        visible: !mr.modelData.installed && !mr.busy
                        text: "Download" + (mr.modelData.size > 0 ? "  " + page.bytes(mr.modelData.size) : "")
                        primary: true
                        enabled: mr.verdict !== "no"
                        onClicked: page.pull(mr.modelData)
                    }
                    Pill { visible: mr.modelData.current && mr.modelData.installed; text: "In use"; tone: "good" }
                    Btn { visible: mr.modelData.installed && !mr.modelData.current; text: "Use"; primary: true; onClicked: page.use(mr.modelData) }
                    Btn { visible: mr.modelData.installed; text: "Remove"; danger: true; onClicked: page.removeModel(mr.modelData) }
                }

                Rectangle {
                    height: 1
                    color: Theme.line
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                }
            }
        }
        Cell {
            last: true
            title: "Add from Hugging Face"
            subtitle: "Any public GGUF model, as hf://owner/name or hf://owner/name:Q4_K_M. Its files are pinned and checked against the published hash after they download."
            Btn { text: "Add…"; onClicked: { page.hfError = ""; hfInput.text = ""; hfSheet.open() } }
        }
    }

    SectionTitle { text: "MEMORY"; visible: page.installed && page.running && page.cur !== null && !!page.cur.fit }
    Card {
        visible: page.installed && page.running && page.cur !== null && !!page.cur.fit
        Item {
            id: mem
            Layout.fillWidth: true
            implicitHeight: memCol.implicitHeight + 28
            readonly property real used: page.cur && page.cur.fit ? (page.cur.fit.gpu_mb || 0) : 0
            readonly property real total: page.hw.memory_budget_mb || 0
            ColumnLayout {
                id: memCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                RowLayout {
                    Layout.fillWidth: true
                    Text { Layout.fillWidth: true; text: page.hw.unified ? "Unified memory for the model" : "GPU memory for the model"; color: Theme.text; font.family: Theme.sans; font.pixelSize: 13 }
                    Text { text: "about " + page.gb(mem.used) + " of " + page.gb(mem.total); color: Theme.sub; font.family: Theme.sans; font.pixelSize: 12 }
                }
                Meter {
                    value: mem.total > 0 ? 100 * mem.used / mem.total : 0
                    tint: mem.total > 0 && mem.used / mem.total > 0.9 ? Theme.warn : Theme.accent
                }
                Text {
                    Layout.fillWidth: true
                    text: page.cur && page.cur.fit ? (page.cur.title || page.cur.id) + "  •  context " + page.ctxLabel(page.cur.fit.ctx || 0) + "  •  estimated from the model, not measured" : ""
                    color: Theme.sub
                    font.family: Theme.sans
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }
        }
    }

    SectionTitle { text: "CONNECTED AGENTS"; visible: page.installed }
    Card {
        visible: page.installed
        Repeater {
            model: page.agentRows
            delegate: Cell {
                id: ag
                required property var modelData
                required property int index
                readonly property bool runOnly: modelData.method === "run --local"
                last: index === page.agentRows.length - 1
                title: modelData.title || modelData.name
                subtitle: modelData.name === "claude-code" ? "Unsupported by Anthropic: Claude Code is made for Claude models and may fail with local ones. Only a run started here uses the local model."
                        : runOnly ? "Start it with: kwick-agents run --local " + modelData.name
                        : !modelData.installed ? "Not installed"
                        : !modelData.supported ? "Not available on this computer"
                        : modelData.connected ? "Uses your local models. Its own settings are changed in a way that can be undone."
                        : modelData.note ? modelData.note
                        : "Off. It keeps using its own provider."
                Btn {
                    visible: ag.runOnly
                    enabled: ag.modelData.installed !== false
                    text: "Run"
                    onClicked: page.runLocal(ag.modelData)
                }
                Toggle {
                    visible: !ag.runOnly
                    checked: !!ag.modelData.connected
                    enabled: !!ag.modelData.installed && ag.modelData.supported !== false
                    onToggled: (v) => page.connect(ag.modelData, v)
                }
            }
        }
    }

    SectionTitle { text: "ADVANCED"; visible: page.installed }
    Card {
        visible: page.installed
        Cell {
            visible: page.cur !== null && !!page.cur.installed
            title: "Context size"
            subtitle: "How much text the model can read at once. Larger needs more memory. Applies to " + (page.cur ? page.cur.title : "") + " and restarts the server if it runs."
            Seg { options: page.contexts; current: String(page.cur && page.cur.fit ? page.cur.fit.ctx : 32768); onPicked: (id) => page.setContext(id) }
        }
        Cell {
            title: "Idle unload"
            subtitle: "The model leaves memory after " + Math.round((page.svc.idle_seconds || 900) / 60) + " minutes without requests, which frees GPU memory for games and the desktop. It loads again on the next request."
        }
        Cell {
            title: "Check setup"
            subtitle: "Tests the engine, GPU access, sandbox, key and server."
            Btn { text: "Run Check"; onClicked: Sys.terminal(page.inf("doctor")) }
        }
        Cell {
            title: "Logs"
            subtitle: "Recent output of the server."
            Btn { text: "Open Logs"; onClicked: Sys.terminal(page.inf("service logs -n 200")) }
        }
        Cell {
            last: true
            title: "Remove the engine"
            subtitle: "Deletes the engine. Downloaded models and your keys stay."
            Btn { text: "Remove Engine…"; danger: true; onClicked: page.confirm("Remove the local model engine?", "The engine is deleted and the server stops. Downloaded models and your keys are kept.", "Remove", true, page.inf("remove")) }
        }
    }

    Sheet {
        id: ask
        icon: "icons/obj-agents.svg"
        onConfirmed: page.act(page.askCmd)
    }

    Sheet {
        id: hfSheet
        title: "Add a model from Hugging Face"
        body: "Paste the model as hf://owner/name, optionally with a quantization after a colon."
        confirmText: "Add"
        icon: "icons/obj-agents.svg"
        onConfirmed: page.addHf()
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 4
            implicitHeight: 32
            radius: 8
            color: Theme.field
            border.width: 1
            border.color: page.hfError !== "" ? Theme.bad : Theme.lineStrong
            TextInput {
                id: hfInput
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text
                font.family: Theme.mono
                font.pixelSize: 13
                selectionColor: Theme.accent
                clip: true
                onTextChanged: page.hfError = ""
                onAccepted: { hfSheet.close(); page.addHf() }
                Text { visible: !hfInput.text.length; anchors.verticalCenter: parent.verticalCenter; text: "hf://unsloth/gemma-4-E4B-it-GGUF:Q4_K_M"; color: Theme.faint; font: hfInput.font }
            }
        }
        Text {
            visible: page.hfError !== ""
            Layout.fillWidth: true
            Layout.topMargin: 6
            text: page.hfError
            color: Theme.bad
            font.family: Theme.sans
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }
    }
}
