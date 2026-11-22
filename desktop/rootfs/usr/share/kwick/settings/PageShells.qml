import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: page
    spacing: 10

    property bool loaded: false
    property string user: "kwick"
    property string host: "kwick"
    property string layout: Sys.layout
    property var terminal: ({ shells: [] })
    property var prompts: ({ presets: [], current: "kwick" })
    property var desktop: ({ shells: [] })
    property string busy: ""
    property string message: ""
    property bool failed: false
    property string previewShell: ""

    readonly property var termShells: terminal && terminal.shells ? terminal.shells : []
    readonly property var deskShells: desktop && desktop.shells ? desktop.shells : []
    readonly property string currentTerm: terminal && terminal.current ? terminal.current : Sys.loginShell
    readonly property string shownShell: previewShell !== "" ? previewShell : currentTerm
    readonly property string currentPrompt: prompts && prompts.current ? prompts.current : "kwick"
    readonly property color hi: layout === "windows" ? "#0087d7" : layout === "linux" ? "#5f87ff" : "#0087ff"
    readonly property var tint: ({ zsh: "#2f9e5b", bash: "#3c4048", fish: "#d9762b", ash: "#6b7280", nushell: "#3aa675", elvish: "#5b6cd6", xonsh: "#7a4fd1", powershell: "#2b5797" })
    readonly property var glyph: ({ zsh: "Z", bash: "$_", fish: "fi", ash: "sh", nushell: "nu", elvish: "el", xonsh: "xo", powershell: "PS" })

    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    function load() {
        Sys.run("sh " + Sys.dir + "helpers/shells.sh", function (out) {
            var d
            try { d = JSON.parse(out) } catch (e) { return }
            page.user = d.user || page.user
            page.host = d.host || page.host
            page.layout = d.layout || page.layout
            if (d.terminal) page.terminal = d.terminal
            if (d.prompts) page.prompts = d.prompts
            if (d.desktop) page.desktop = d.desktop
            if (d.terminal && d.terminal.current) Sys.loginShell = d.terminal.current
            page.loaded = true
        })
    }

    function act(id, cmd) {
        page.busy = id
        page.message = ""
        page.failed = false
        Sys.run("{ " + cmd + " ; } 2>&1; echo \"__rc=$?\"", function (out) {
            var m = /__rc=(\d+)\s*$/.exec(out)
            var rc = m ? parseInt(m[1]) : 1
            var lines = out.replace(/__rc=\d+\s*$/, "").trim().split("\n").filter(function (l) { return l.trim() !== "" })
            page.message = lines.length ? lines[lines.length - 1].replace(/^kwick-(shell|desktop|shell-helper): /, "") : ""
            page.failed = rc !== 0
            page.busy = ""
            page.load()
            Sys.refresh()
        })
    }

    function setTerminal(s) {
        var set = "pkexec /usr/lib/kwick/shell-helper set \"$(id -un)\" " + s.name
        var cmd = s.installed ? set : Sys.shellInstall(s.name) + " && " + set
        act("term-" + s.name, "if command -v pkexec >/dev/null; then " + cmd + "; else kwick-shell " + s.name + "; fi")
    }

    function setPrompt(p) {
        page.prompts = Object.assign({}, page.prompts, { current: p })
        var inst = p === "starship" ? "{ [ -x /usr/bin/starship ] || " + Sys.shellInstall("starship") + "; } && " : ""
        act("prompt-" + p, inst + "kwick-shell prompt " + p)
    }

    function setDesktop(s) {
        act("desk-" + s.name, "kwick-desktop shell " + s.name)
    }

    function promptChar(sh) {
        return sh === "zsh" ? "%" : "$"
    }

    function segs(preset, sh, dir, branch) {
        var who = page.user + "@" + page.host
        var dim = Theme.light ? "#6e6e73" : "#8a8a8a"
        var fg = Theme.light ? "#1d1d1f" : "#e5e5e7"
        if (preset === "minimal")
            return [{ t: dir, c: page.hi, b: true }, { t: " ❯ ", c: page.hi }]
        if (preset === "powerline") {
            var out = [{ t: " " + who + " ", c: "#d0d0d0", bg: "#444444" }, { arrow: true, from: "#444444", to: page.hi }, { t: " " + dir + " ", c: "#ffffff", bg: page.hi, b: true }]
            if (branch) {
                out.push({ arrow: true, from: page.hi, to: "#303030" })
                out.push({ t: "  " + branch + " ", c: "#bcbcbc", bg: "#303030" })
                out.push({ arrow: true, from: "#303030", to: "transparent" })
            } else {
                out.push({ arrow: true, from: page.hi, to: "transparent" })
            }
            out.push({ t: " " })
            return out
        }
        if (preset === "starship") {
            var s = [{ t: who, c: dim }, { t: " " }, { t: dir, c: page.hi, b: true }, { t: " " }]
            if (branch) s.push({ t: " " + branch + " ", c: Theme.light ? "#57575c" : "#bcbcbc" })
            s.push({ t: "❯ ", c: page.hi })
            return s
        }
        return [{ t: who, c: dim }, { t: " " }, { t: dir, c: page.hi, b: true }, { t: " " + promptChar(sh) + " ", c: fg }]
    }

    component Badge: Rectangle {
        property string text
        property color fg: Theme.good
        property color bg: Theme.goodBg
        implicitWidth: bl.implicitWidth + 16
        implicitHeight: 20
        radius: 10
        color: bg
        Text { id: bl; anchors.centerIn: parent; text: parent.text; color: parent.fg; font.family: Theme.sans; font.pixelSize: 11; font.weight: Font.Medium }
    }

    component Spinner: Item {
        implicitWidth: 18
        implicitHeight: 18
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: Theme.line
        }
        Rectangle {
            width: 6
            height: 6
            radius: 3
            color: Theme.accent
            x: parent.width / 2 - 3
            y: -1
        }
        RotationAnimation on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: true }
    }

    component PromptLine: Row {
        id: pl
        property var parts: []
        property string cmd: ""
        property bool cursor: false
        height: 22
        Repeater {
            model: pl.parts
            delegate: Item {
                required property var modelData
                width: modelData.arrow ? 11 : tx.implicitWidth
                height: 22
                Rectangle { anchors.fill: parent; visible: !!parent.modelData.bg; color: parent.modelData.bg || "transparent" }
                Canvas {
                    anchors.fill: parent
                    visible: !!parent.modelData.arrow
                    property var md: parent.modelData
                    onMdChanged: requestPaint()
                    onPaint: {
                        var c = getContext("2d")
                        c.reset()
                        if (!md || !md.arrow) return
                        if (md.to !== "transparent") { c.fillStyle = String(md.to); c.fillRect(0, 0, width, height) }
                        c.fillStyle = String(md.from)
                        c.beginPath()
                        c.moveTo(0, 0)
                        c.lineTo(width, height / 2)
                        c.lineTo(0, height)
                        c.closePath()
                        c.fill()
                    }
                }
                Text {
                    id: tx
                    visible: !parent.modelData.arrow
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.modelData.t || ""
                    color: parent.modelData.c || (Theme.light ? "#1d1d1f" : "#e5e5e7")
                    font.family: Theme.mono
                    font.pixelSize: 13
                    font.bold: !!parent.modelData.b
                }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: pl.cmd
            color: Theme.light ? "#1d1d1f" : "#e5e5e7"
            font.family: Theme.mono
            font.pixelSize: 13
        }
        Rectangle {
            visible: pl.cursor
            anchors.verticalCenter: parent.verticalCenter
            width: 8
            height: 16
            color: Theme.light ? "#1d1d1f" : "#e5e5e7"
            SequentialAnimation on opacity { loops: Animation.Infinite; running: pl.cursor; NumberAnimation { to: 0; duration: 500 } NumberAnimation { to: 1; duration: 500 } }
        }
    }

    Component.onCompleted: load()

    Timer {
        interval: 15000
        repeat: true
        running: page.loaded && page.busy === "" && Qt.application.state === Qt.ApplicationActive
        onTriggered: page.load()
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        text: "Pick the desktop you log into and the shell your terminals run. Everything here also works from a terminal with kwick-shell and kwick-desktop shell."
        color: Theme.sub
        font.family: Theme.sans
        font.pixelSize: 12
        wrapMode: Text.WordWrap
    }

    SectionTitle { text: "DESKTOP SHELL" }

    GridLayout {
        Layout.fillWidth: true
        columns: page.width > 1040 ? 3 : page.width > 560 ? 2 : 1
        columnSpacing: 12
        rowSpacing: 12
        Repeater {
            model: page.deskShells
            delegate: Rectangle {
                id: dc
                required property var modelData
                readonly property bool cur: modelData.current
                readonly property bool working: page.busy === "desk-" + modelData.name
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 1
                implicitHeight: dcol.implicitHeight + 24
                radius: 14
                color: Theme.card
                border.width: cur ? 2 : 1
                border.color: cur ? Theme.accent : Theme.line
                ColumnLayout {
                    id: dcol
                    x: 12
                    y: 12
                    width: parent.width - 24
                    spacing: 8
                    ShellPreview {
                        Layout.fillWidth: true
                        Layout.preferredHeight: width * 0.56
                        kind: dc.modelData.name
                        layout: page.layout
                        lightMode: Theme.light
                        opacity: dc.modelData.available ? 1 : 0.45
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 22
                        spacing: 8
                        Text { text: dc.modelData.title; color: Theme.text; font.family: Theme.sans; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Badge { visible: dc.modelData.kind === "quickshell"; text: "Quickshell"; fg: Theme.light ? "#5b3fb5" : "#cdb8ff"; bg: Theme.light ? "#ece5fb" : "#2f2647" }
                        Item { Layout.fillWidth: true }
                        Badge { visible: dc.cur; text: dc.modelData.running ? "In use" : "At next login" }
                        Badge { visible: !dc.cur && dc.modelData.running; text: "Running"; fg: Theme.warnText; bg: Theme.warnBg }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: dc.modelData.toolkit + (dc.modelData.version ? "  ·  " + dc.modelData.version : "") + "  ·  " + dc.modelData.license
                        color: Theme.sub
                        font.family: Theme.sans
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        text: dc.modelData.description
                        color: Theme.text
                        opacity: 0.8
                        font.family: Theme.sans
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            Layout.fillWidth: true
                            text: !dc.modelData.available ? "Not available on " + page.desktop.arch
                                : dc.cur ? (dc.modelData.running ? "This is your desktop" : "Log out to start it")
                                : dc.modelData.live ? "Switches right away" : "Starts at your next login"
                            color: Theme.sub
                            font.family: Theme.sans
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                        Spinner { visible: dc.working }
                        Btn {
                            visible: !dc.cur && dc.modelData.available && !dc.working
                            enabled: page.busy === ""
                            primary: dc.modelData.installed
                            text: dc.modelData.installed ? (dc.modelData.live ? "Switch now" : "Use") : "Install and use"
                            onClicked: page.setDesktop(dc.modelData)
                        }
                    }
                }
            }
        }
    }

    Text {
        Layout.leftMargin: 4
        Layout.fillWidth: true
        visible: page.message !== "" && page.busy === "" && page.failed
        text: page.message
        color: Theme.bad
        font.family: Theme.sans
        font.pixelSize: 12
        wrapMode: Text.WordWrap
    }

    SectionTitle { text: "TERMINAL SHELL" }

    Card {
        Repeater {
            model: page.termShells
            delegate: Item {
                id: tr
                required property var modelData
                required property int index
                readonly property bool cur: modelData.current
                readonly property bool working: page.busy === "term-" + modelData.name
                Layout.fillWidth: true
                implicitHeight: 60
                visible: modelData.available || modelData.installed
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: page.previewShell = tr.modelData.name
                    onExited: if (page.previewShell === tr.modelData.name) page.previewShell = ""
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 16
                    spacing: 12
                    Rectangle {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        radius: 9
                        color: page.tint[tr.modelData.name] || "#555555"
                        Text { anchors.centerIn: parent; text: page.glyph[tr.modelData.name] || ""; color: "#ffffff"; font.family: Theme.mono; font.pixelSize: 13; font.bold: true }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        RowLayout {
                            spacing: 6
                            Text { text: tr.modelData.title; color: Theme.text; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.Medium }
                            Text {
                                text: (tr.modelData.version ? tr.modelData.version.replace(/[-+].*$/, "") + "  ·  " : "") + (tr.modelData.source === "upstream" ? "official release, verified" : tr.modelData.source === "builtin" ? "built in" : "Debian")
                                color: Theme.sub
                                font.family: Theme.sans
                                font.pixelSize: 11
                            }
                        }
                        Text { Layout.fillWidth: true; text: tr.modelData.description; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 12; elide: Text.ElideRight }
                    }
                    Spinner { visible: tr.working }
                    Badge { visible: tr.cur; text: "Login shell" }
                    Btn {
                        visible: !tr.cur && !tr.working
                        enabled: page.busy === ""
                        primary: tr.modelData.installed
                        text: tr.modelData.installed ? "Use" : "Install"
                        onClicked: page.setTerminal(tr.modelData)
                    }
                }
                Rectangle {
                    visible: tr.index < page.termShells.length - 1
                    height: 1
                    color: Theme.line
                    anchors.left: parent.left
                    anchors.leftMargin: 60
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                }
            }
        }
    }
    Text {
        Layout.leftMargin: 4
        Layout.fillWidth: true
        text: "No terminal window opens and no password is needed to switch between installed shells. New terminals use the shell after you log out and back in; type its name to try it now."
        color: Theme.sub
        font.family: Theme.sans
        font.pixelSize: 12
        wrapMode: Text.WordWrap
    }

    SectionTitle { text: "PROMPT" }

    Card {
        Item {
            Layout.fillWidth: true
            implicitHeight: pcol.implicitHeight + 28
            ColumnLayout {
                id: pcol
                x: 16
                y: 14
                width: parent.width - 32
                spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: "The same look in every shell, coloured by your layout."
                        color: Theme.text
                        font.family: Theme.sans
                        font.pixelSize: 13
                    }
                    Spinner { visible: page.busy.indexOf("prompt-") === 0 }
                    Seg {
                        options: (page.prompts.presets || []).map(function (p) { return { id: p.name, label: p.title } })
                        current: page.currentPrompt
                        onPicked: (id) => page.setPrompt(id)
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: term.implicitHeight + 46
                    radius: 10
                    color: Theme.light ? "#ffffff" : "#1c1c1e"
                    border.width: 1
                    border.color: Theme.lineStrong
                    Rectangle {
                        width: parent.width
                        height: 26
                        radius: 10
                        color: Theme.light ? "#ececec" : "#2a2a2c"
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 10; color: parent.color }
                        Row {
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            visible: page.layout === "macos"
                            Repeater { model: ["#ff5f57", "#febc2e", "#28c840"]; Rectangle { width: 10; height: 10; radius: 5; color: modelData } }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: page.user + "@" + page.host + " — " + page.shownShell
                            color: Theme.sub
                            font.family: Theme.sans
                            font.pixelSize: 11
                        }
                    }
                    Column {
                        id: term
                        x: 14
                        y: 36
                        spacing: 2
                        PromptLine { parts: page.segs(page.currentPrompt, page.shownShell, "~", ""); cmd: "cd Projects/kwickos" }
                        PromptLine { parts: page.segs(page.currentPrompt, page.shownShell, "kwickos", "main"); cmd: "kwick-shell prompt " + page.currentPrompt }
                        Text {
                            height: 20
                            verticalAlignment: Text.AlignVCenter
                            text: "kwick-shell: prompt is now " + page.currentPrompt
                            color: Theme.light ? "#57575c" : "#a1a1a6"
                            font.family: Theme.mono
                            font.pixelSize: 13
                        }
                        PromptLine { parts: page.segs(page.currentPrompt, page.shownShell, "kwickos", "main"); cursor: true }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: {
                        var ps = page.prompts.presets || []
                        for (var i = 0; i < ps.length; i++)
                            if (ps[i].name === page.currentPrompt)
                                return ps[i].description + (ps[i].name === "starship" && !ps[i].installed ? ". Starship is installed from Debian when you pick it." : ".")
                        return ""
                    }
                    color: Theme.sub
                    font.family: Theme.sans
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
