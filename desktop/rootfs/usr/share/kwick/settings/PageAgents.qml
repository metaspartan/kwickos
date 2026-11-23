import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

ColumnLayout {
    id: page
    spacing: 10

    property bool available: true
    property bool loaded: false
    property var agents: []
    property var caps: []
    property var grants: ({})
    property var keys: []
    property string backend: ""
    property var audit: []
    property var pending: []
    property var control: []
    property var checks: ({})
    property string selected: ""
    property string keyAgent: ""
    property var keySuggest: []

    readonly property var installed: agents.filter(function (a) { return a.installed && a.kind !== "runtime" })
    readonly property var installable: agents.filter(function (a) { return !a.installed && a.supported && a.kind !== "runtime" })
    readonly property var unavailable: agents.filter(function (a) { return !a.supported && a.kind !== "runtime" })
    readonly property var tint: ({ "claude-code": "#c96442", "codex": "#1a7f64", "gemini-cli": "#3d74e0", "opencode": "#4a4a52", "omp": "#7c4ddb", "openclaw": "#d9483b", "hermes": "#9b51e0", "aider": "#139c8c", "goose": "#d98a0b", "cybara": "#1690c9", "ollama": "#5b5b63", "llama-cpp": "#6aa121", "inference": "#8e8e93" })
    readonly property var capTitles: ({ "system.read": "Read system information", "files.read": "Read files", "files.write": "Change files", "notify": "Notifications", "settings.write": "Change settings", "apps.launch": "Open apps", "screen.capture": "Screenshots", "computer.control": "Use the mouse, keyboard and windows", "packages.manage": "Install software", "snapshots.manage": "Create snapshots" })
    readonly property var levels: [{ id: "allow", label: "Allow" }, { id: "ask", label: "Ask" }, { id: "deny", label: "Deny" }]

    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    function load() {
        Sys.run("sh " + Sys.dir + "helpers/agents.sh", function (out) {
            var d
            try { d = JSON.parse(out) } catch (e) { return }
            page.available = d.available !== false
            page.loaded = true
            if (!page.available) return
            page.agents = (d.list && d.list.agents) || []
            page.caps = (d.grants && d.grants.capabilities) || []
            page.grants = (d.grants && d.grants.agents) || {}
            page.keys = (d.keys && d.keys.keys) || []
            page.backend = (d.keys && d.keys.backend) || ""
            page.audit = ((d.audit && d.audit.entries) || []).slice().reverse()
            page.pending = (d.consent && d.consent.pending) || []
            page.control = (d.control && d.control.sessions) || []
            var c = {}
            ;((d.doctor && d.doctor.checks) || []).forEach(function (x) { c[x.name] = x })
            page.checks = c
        })
    }

    function act(cmd) {
        Sys.run(cmd + " 2>&1", function () { page.load() })
    }

    function keysFor(name) {
        return page.keys.filter(function (k) { return k.agent === name || k.agent === "shared" })
    }

    function ago(iso) {
        var t = new Date(iso)
        var s = Math.max(0, Math.round((Date.now() - t.getTime()) / 1000))
        if (s < 60) return "just now"
        if (s < 3600) return Math.floor(s / 60) + " min ago"
        if (s < 86400) return Math.floor(s / 3600) + " h ago"
        return t.toLocaleDateString()
    }

    function titleOf(name) {
        for (var i = 0; i < page.agents.length; i++)
            if (page.agents[i].name === name) return page.agents[i].title
        return name
    }

    Component.onCompleted: load()

    Timer {
        interval: 4000
        running: page.visible
        repeat: true
        onTriggered: page.load()
    }

    Card {
        visible: page.loaded && !page.available
        Cell {
            last: true
            title: "AI agent support is not installed"
            subtitle: "kwick-agents installs coding agents and local models in sandboxes, keeps their API keys in your keystore and lets them use KwickOS through the MCP server, with your permission."
            Btn { text: "Install"; primary: true; onClicked: { Sys.terminal(Sys.elevated("apt-get install -y kwick-agents"), function () { page.load() }) } }
        }
    }

    SectionTitle { text: "WAITING FOR YOUR ANSWER"; visible: page.pending.length > 0 }
    Card {
        visible: page.pending.length > 0
        Repeater {
            model: page.pending.filter(function (r) { return /^[0-9a-f]{8,64}$/.test(String(r.id)) })
            delegate: Cell {
                required property var modelData
                required property int index
                last: index === page.pending.length - 1
                title: page.titleOf(modelData.agent) + " asks: " + modelData.detail
                subtitle: (page.capTitles[modelData.capability] || modelData.capability) + "  •  " + page.ago(modelData.time)
                Btn { text: "Deny"; onClicked: page.act("kwick-agents consent deny " + page.q(modelData.id)) }
                Btn { text: "Always"; onClicked: page.act("kwick-agents consent always " + page.q(modelData.id)) }
                Btn { text: "Allow once"; primary: true; onClicked: page.act("kwick-agents consent allow " + page.q(modelData.id)) }
            }
        }
    }

    SectionTitle { text: "IN CONTROL OF THIS COMPUTER"; visible: page.control.length > 0 }
    Card {
        visible: page.control.length > 0
        Repeater {
            model: page.control.filter(function (c) { return /^[0-9a-f]{8}$/.test(String(c.id)) })
            delegate: Cell {
                required property var modelData
                required property int index
                last: index === page.control.length - 1
                title: page.titleOf(modelData.agent) + " is using the mouse and keyboard"
                subtitle: "Since " + page.ago(modelData.started) + ", ends by " + Qt.formatTime(new Date(modelData.expires), "HH:mm") + "  •  Meta+Alt+Escape stops every agent"
                Btn { text: "Stop"; danger: true; onClicked: page.act("kwick-agents control stop " + page.q(modelData.id)) }
            }
        }
    }

    Card {
        visible: page.available && page.loaded
        Cell {
            title: "Sandbox"
            subtitle: page.checks.bubblewrap ? (page.checks.bubblewrap.ok ? "Agents run in bubblewrap: they see their own folders and the project you start them in, nothing else of your home." : page.checks.bubblewrap.detail) : ""
            Rectangle { width: 8; height: 8; radius: 4; color: page.checks.bubblewrap && page.checks.bubblewrap.ok ? Theme.good : Theme.bad }
            Text { text: page.checks.bubblewrap && page.checks.bubblewrap.ok ? "Working" : "Not working"; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 12 }
        }
        Cell {
            title: "API keys"
            subtitle: page.backend === "secret-service" ? "Stored in your keyring (KWallet or GNOME Keyring through the Secret Service) and handed to an agent only when it starts." : "Stored in ~/.config/kwick-agents/secrets.json, readable only by you, and handed to an agent only when it starts."
            Text { text: page.keys.length + (page.keys.length === 1 ? " key" : " keys"); color: Theme.sub; font.family: Theme.sans; font.pixelSize: 12 }
        }
        Cell {
            last: true
            title: "KwickOS tools for agents"
            subtitle: "kwick-mcp lets agents read system information, manage software, files and settings, and use the desktop. Anything that changes your system asks you first, and every request is logged below."
            Btn { text: "Agent guide"; onClicked: Sys.run("xdg-open /usr/share/doc/kwickos/AGENTS.md || xdg-open /usr/share/doc/kwick-agents/AGENTS.md") }
        }
    }

    SectionTitle { text: "INSTALLED"; visible: page.available && page.loaded }
    Card {
        visible: page.available && page.loaded
        Cell {
            visible: page.installed.length === 0
            last: true
            title: "No agents installed yet"
            subtitle: "Pick one below. It is installed for you only, pinned to a checked release."
        }
        Repeater {
            model: page.installed
            delegate: ColumnLayout {
                id: ar
                required property var modelData
                required property int index
                readonly property bool open: page.selected === modelData.name
                readonly property var g: page.grants[modelData.name] || ({ caps: {}, folders: [] })
                Layout.fillWidth: true
                spacing: 0

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 64
                    Rectangle { anchors.fill: parent; anchors.margins: 4; radius: 8; color: rowHover.containsMouse && !ar.open ? Theme.hover : "transparent" }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 16
                        spacing: 14
                        Rectangle {
                            width: 38
                            height: 38
                            radius: 10
                            color: page.tint[ar.modelData.name] || Theme.accent
                            Text { anchors.centerIn: parent; text: ar.modelData.title.charAt(0).toUpperCase(); color: "#ffffff"; font.family: Theme.sans; font.pixelSize: 18; font.weight: Font.DemiBold }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text { Layout.fillWidth: true; text: ar.modelData.title; color: Theme.text; font.family: Theme.sans; font.pixelSize: 14; font.weight: Font.DemiBold; elide: Text.ElideRight }
                            Text {
                                Layout.fillWidth: true
                                text: ar.modelData.installed_version + (ar.modelData.update_available ? "  •  update to " + ar.modelData.version : "") + "  •  " + (ar.modelData.sandbox ? "Sandboxed" : "Not sandboxed") + (ar.modelData.sandbox && !ar.modelData.network ? ", offline" : "") + (ar.modelData.mcp_enabled ? "  •  KwickOS tools on" : "")
                                color: ar.modelData.sandbox ? Theme.sub : Theme.warn
                                font.family: Theme.sans
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                        }
                        Btn { text: "Open"; onClicked: Sys.run("kwick-terminal -e kwick-agents run " + ar.modelData.name) }
                        Text { text: ar.open ? "⌃" : "⌄"; color: Theme.sub; font.pixelSize: 16; Layout.preferredWidth: 14 }
                    }
                    MouseArea {
                        id: rowHover
                        anchors.fill: parent
                        anchors.rightMargin: 90
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.selected = ar.open ? "" : ar.modelData.name
                    }
                }

                ColumnLayout {
                    visible: ar.open
                    Layout.fillWidth: true
                    Layout.leftMargin: 66
                    Layout.rightMargin: 16
                    Layout.bottomMargin: 12
                    spacing: 0

                    Text { Layout.topMargin: 2; Layout.bottomMargin: 4; text: ar.modelData.description; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        radius: 10
                        color: Theme.cardHi
                        implicitHeight: opts.implicitHeight
                        ColumnLayout {
                            id: opts
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 0
                            Cell {
                                title: "Run in a sandbox"
                                subtitle: "Recommended. Off means the agent can read and change everything your account can."
                                Toggle { checked: ar.modelData.sandbox; onToggled: (v) => page.act("kwick-agents sandbox " + ar.modelData.name + (v ? " on" : " off")) }
                            }
                            Cell {
                                title: "Network access"
                                subtitle: "Cloud agents need it to reach their model provider."
                                Toggle { checked: ar.modelData.network; enabled: ar.modelData.sandbox; onToggled: (v) => page.act("kwick-agents network " + ar.modelData.name + (v ? " on" : " off")) }
                            }
                            Cell {
                                last: true
                                title: "KwickOS tools (MCP)"
                                subtitle: ar.modelData.mcp_supported ? "Registers kwick-mcp in the agent's own settings." : "This agent has no MCP client."
                                Toggle { checked: ar.modelData.mcp_enabled; enabled: ar.modelData.mcp_supported; onToggled: (v) => page.act("kwick-agents mcp " + (v ? "enable " : "disable ") + ar.modelData.name) }
                            }
                        }
                    }

                    Text { Layout.topMargin: 14; Layout.bottomMargin: 6; text: "Permissions"; color: Theme.text; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Rectangle {
                        Layout.fillWidth: true
                        radius: 10
                        color: Theme.cardHi
                        implicitHeight: perms.implicitHeight
                        ColumnLayout {
                            id: perms
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 0
                            Repeater {
                                model: page.caps
                                delegate: Cell {
                                    required property var modelData
                                    required property int index
                                    last: index === page.caps.length - 1
                                    title: page.capTitles[modelData.name] || modelData.name
                                    subtitle: modelData.description
                                    Seg {
                                        options: page.levels
                                        current: ar.g.caps[modelData.name] || modelData.default
                                        onPicked: (id) => page.act("kwick-agents grant " + ar.modelData.name + " " + modelData.name + " " + id)
                                    }
                                }
                            }
                        }
                    }

                    Text { Layout.topMargin: 14; Layout.bottomMargin: 6; text: "Folders"; color: Theme.text; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Rectangle {
                        Layout.fillWidth: true
                        radius: 10
                        color: Theme.cardHi
                        implicitHeight: fold.implicitHeight
                        ColumnLayout {
                            id: fold
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 0
                            Repeater {
                                model: ar.g.folders || []
                                delegate: Cell {
                                    required property var modelData
                                    title: modelData
                                    Btn { text: "Remove"; danger: true; onClicked: page.act("kwick-agents folders " + ar.modelData.name + " rm " + page.q(modelData)) }
                                }
                            }
                            Cell {
                                last: true
                                title: (ar.g.folders || []).length === 0 ? "Only the folder the agent is started in" : "Add another folder"
                                subtitle: (ar.g.folders || []).length === 0 ? "Folders added here can also be read and changed through the KwickOS tools." : ""
                                Btn {
                                    text: "Add Folder…"
                                    onClicked: page.act("d=$(kdialog --getexistingdirectory \"$HOME\" 2>/dev/null || zenity --file-selection --directory 2>/dev/null) && [ -n \"$d\" ] && kwick-agents folders " + ar.modelData.name + " add \"$d\"")
                                }
                            }
                        }
                    }

                    Text { Layout.topMargin: 14; Layout.bottomMargin: 6; text: "API keys"; color: Theme.text; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Rectangle {
                        Layout.fillWidth: true
                        radius: 10
                        color: Theme.cardHi
                        implicitHeight: keyCol.implicitHeight
                        ColumnLayout {
                            id: keyCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 0
                            Repeater {
                                model: page.keysFor(ar.modelData.name)
                                delegate: Cell {
                                    required property var modelData
                                    title: modelData.var
                                    subtitle: modelData.agent === "shared" ? "Shared with every agent" : "Only for " + ar.modelData.title
                                    Btn { text: "Remove"; danger: true; onClicked: page.act("kwick-agents key rm " + modelData.agent + " " + modelData.var) }
                                }
                            }
                            Cell {
                                last: true
                                title: page.keysFor(ar.modelData.name).length === 0 ? "No keys stored" : "Add another key"
                                subtitle: page.keysFor(ar.modelData.name).length === 0 && ar.modelData.keys.length > 0 ? "This agent reads " + ar.modelData.keys.join(", ") + ". You can also sign in inside the agent instead." : ""
                                Btn {
                                    text: "Add Key…"
                                    onClicked: { page.keyAgent = ar.modelData.name; page.keySuggest = ar.modelData.keys; keyName.text = ar.modelData.keys.length ? ar.modelData.keys[0] : ""; keySheet.open() }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 14
                        spacing: 8
                        Text { Layout.fillWidth: true; text: ar.modelData.license + "  •  " + ar.modelData.source; color: Theme.faint; font.family: Theme.sans; font.pixelSize: 11; elide: Text.ElideMiddle }
                        Btn { visible: ar.modelData.update_available; text: "Update"; primary: true; onClicked: Sys.terminal("kwick-agents update " + ar.modelData.name) }
                        Btn { text: "Remove…"; danger: true; onClicked: { removeSheet.agent = ar.modelData.name; removeSheet.title = "Remove " + ar.modelData.title + "?"; removeSheet.open() } }
                    }
                }

                Rectangle {
                    visible: ar.index < page.installed.length - 1
                    Layout.fillWidth: true
                    Layout.leftMargin: 14
                    implicitHeight: 1
                    color: Theme.line
                }
            }
        }
    }

    SectionTitle { text: "AVAILABLE"; visible: page.installable.length > 0 }
    Card {
        visible: page.installable.length > 0
        Repeater {
            model: page.installable
            delegate: Item {
                id: ir
                required property var modelData
                required property int index
                Layout.fillWidth: true
                implicitHeight: 60
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 16
                    spacing: 14
                    Rectangle {
                        width: 34
                        height: 34
                        radius: 9
                        color: page.tint[ir.modelData.name] || Theme.accent
                        Text { anchors.centerIn: parent; text: ir.modelData.title.charAt(0).toUpperCase(); color: "#ffffff"; font.family: Theme.sans; font.pixelSize: 16; font.weight: Font.DemiBold }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text { Layout.fillWidth: true; text: ir.modelData.title + "  " + ir.modelData.version; color: Theme.text; font.family: Theme.sans; font.pixelSize: 13; elide: Text.ElideRight }
                        Text { Layout.fillWidth: true; text: ir.modelData.vendor + "  •  " + ir.modelData.description; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 12; elide: Text.ElideRight }
                    }
                    Text { visible: ir.modelData.download_size > 0; text: Math.round(ir.modelData.download_size / 1048576) + " MB"; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 12 }
                    Btn { text: "Install"; primary: true; onClicked: Sys.terminal("kwick-agents install " + ir.modelData.name) }
                }
                Rectangle {
                    visible: ir.index < page.installable.length - 1
                    height: 1
                    color: Theme.line
                    anchors.left: parent.left
                    anchors.leftMargin: 62
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                }
            }
        }
    }
    Text {
        visible: page.unavailable.length > 0
        Layout.fillWidth: true
        Layout.leftMargin: 4
        text: "Not available on this computer: " + page.unavailable.map(function (a) { return a.title + " (" + a.unsupported_reason + ")" }).join(", ")
        color: Theme.faint
        font.family: Theme.sans
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }

    SectionTitle { text: page.selected !== "" ? "ACTIVITY OF " + page.titleOf(page.selected).toUpperCase() : "RECENT ACTIVITY"; visible: page.available && page.loaded }
    Card {
        visible: page.available && page.loaded
        readonly property var rows: page.audit.filter(function (a) { return page.selected === "" || a.agent === page.selected }).slice(0, 14)
        id: act
        Cell {
            visible: act.rows.length === 0
            last: true
            title: "Nothing yet"
            subtitle: "Every start of an agent and every request it makes through the KwickOS tools appears here."
        }
        Repeater {
            model: act.rows
            delegate: Item {
                id: er
                required property var modelData
                required property int index
                Layout.fillWidth: true
                implicitHeight: 44
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 10
                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        color: !er.modelData.ok ? Theme.bad : (er.modelData.decision.indexOf("ask") === 0 ? Theme.warn : Theme.good)
                    }
                    Text { Layout.preferredWidth: 110; text: page.titleOf(er.modelData.agent); color: Theme.text; font.family: Theme.sans; font.pixelSize: 12; elide: Text.ElideRight }
                    Text {
                        Layout.fillWidth: true
                        text: (er.modelData.tool === "run" ? "Started: " : er.modelData.tool === "cli" ? "Setting: " : er.modelData.tool + ": ") + (er.modelData.summary || "") + (er.modelData.error ? "  (" + er.modelData.error + ")" : "")
                        color: Theme.sub
                        font.family: Theme.sans
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                    Text { text: er.modelData.decision; color: Theme.faint; font.family: Theme.mono; font.pixelSize: 11 }
                    Text { Layout.preferredWidth: 70; horizontalAlignment: Text.AlignRight; text: page.ago(er.modelData.time); color: Theme.faint; font.family: Theme.sans; font.pixelSize: 11 }
                }
                Rectangle {
                    visible: er.index < act.rows.length - 1
                    height: 1
                    color: Theme.line
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                }
            }
        }
    }
    Btn { Layout.alignment: Qt.AlignRight; visible: page.available && page.loaded; text: "Open Audit Log"; onClicked: Sys.run("xdg-open \"$HOME/.local/state/kwick-agents/audit.jsonl\"") }

    Sheet {
        id: keySheet
        title: "Add an API key for " + page.titleOf(page.keyAgent)
        body: "Name of the environment variable. The value is asked in the next window and goes straight to your keystore."
        confirmText: "Continue"
        icon: "icons/obj-agents.svg"
        onConfirmed: {
            var v = keyName.text.trim()
            if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(v))
                page.act("kwick-agents key set " + (shareKey.checked ? "shared" : page.keyAgent) + " " + v + " --dialog")
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 4
            implicitHeight: 32
            radius: 8
            color: Theme.field
            border.width: 1
            border.color: Theme.lineStrong
            TextInput {
                id: keyName
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text
                font.family: Theme.mono
                font.pixelSize: 13
                selectionColor: Theme.accent
                Text { visible: !keyName.text.length; anchors.verticalCenter: parent.verticalCenter; text: "ANTHROPIC_API_KEY"; color: Theme.faint; font: keyName.font }
            }
        }
        Flow {
            Layout.fillWidth: true
            Layout.topMargin: 8
            spacing: 6
            Repeater {
                model: page.keySuggest
                delegate: Rectangle {
                    required property var modelData
                    width: chip.implicitWidth + 16
                    height: 24
                    radius: 12
                    color: keyName.text === modelData ? Theme.accent : Theme.control
                    border.width: Theme.light ? 1 : 0
                    border.color: Theme.lineStrong
                    Text { id: chip; anchors.centerIn: parent; text: modelData; color: keyName.text === modelData ? "#ffffff" : Theme.onControl; font.family: Theme.mono; font.pixelSize: 11 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: keyName.text = modelData }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 10
            Text { Layout.fillWidth: true; text: "Share with every agent"; color: Theme.text; font.family: Theme.sans; font.pixelSize: 12 }
            Toggle { id: shareKey; checked: false; onToggled: (v) => shareKey.checked = v }
        }
    }

    Sheet {
        id: removeSheet
        property string agent: ""
        body: "The program is removed. Its settings, sign-ins and history in your home folder are kept, and so are your keys."
        confirmText: "Remove"
        danger: true
        icon: "icons/obj-agents.svg"
        onConfirmed: { page.selected = ""; page.act("kwick-agents remove " + removeSheet.agent) }
    }
}
