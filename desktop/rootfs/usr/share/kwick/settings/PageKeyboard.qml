import QtQuick
import QtCore
import QtQuick.Layouts
import QtQuick.Dialogs

ColumnLayout {
    id: page
    spacing: 10

    property var km: ({ actions: [], categories: [], layout: "macos", session: "kde" })
    property bool loaded: false
    property string query: ""
    property string recording: ""
    property var held: []
    property string busy: ""
    property var pending: null
    property var errors: ({})
    property string note: ""
    property bool noteBad: false
    property bool confirmReset: false

    readonly property bool mac: km.layout === "macos"
    readonly property var conflicted: km.actions.filter(function (a) { return a.conflicts && a.conflicts.length })
    readonly property var groups: {
        var q = page.query.trim().toLowerCase()
        var out = []
        km.categories.forEach(function (c) {
            var rows = km.actions.filter(function (a) {
                if (a.category !== c.id)
                    return false
                if (q === "")
                    return true
                var hay = [a.title, a.subtitle, a.keywords, c.title, a.chords.join(" "), a.caps.map(function (x) { return x.join(" ") }).join(" ")].join(" ").toLowerCase()
                return q.split(/\s+/).every(function (w) { return hay.indexOf(w) >= 0 })
            })
            if (rows.length)
                out.push({ id: c.id, title: c.title, rows: rows })
        })
        return out
    }

    function quote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    function helper(args) {
        return "sh " + Sys.dir + "helpers/keys.sh " + args
    }

    function load() {
        Sys.run(helper("list"), function (out) {
            try {
                page.km = JSON.parse(out)
                page.loaded = true
            } catch (e) {
                page.note = out.trim() !== "" ? out.trim() : "Couldn't read the shortcuts"
                page.noteBad = true
            }
        })
    }

    function sessionName(s) {
        return ({ kde: "Plasma", gnome: "GNOME", hyprland: "Hyprland", sway: "sway" })[s] || s
    }

    function modCaps(mods) {
        var order = page.mac ? ["Ctrl", "Alt", "Shift", "Meta"] : ["Meta", "Ctrl", "Alt", "Shift"]
        var names = page.mac ? { Meta: "⌘", Ctrl: "⌃", Alt: "⌥", Shift: "⇧" }
                  : km.layout === "windows" ? { Meta: "Win", Ctrl: "Ctrl", Alt: "Alt", Shift: "Shift" }
                  : { Meta: "Super", Ctrl: "Ctrl", Alt: "Alt", Shift: "Shift" }
        return order.filter(function (m) { return mods.indexOf(m) >= 0 }).map(function (m) { return names[m] })
    }

    function modsOf(event) {
        var m = []
        if (event.modifiers & Qt.MetaModifier) m.push("Meta")
        if (event.modifiers & Qt.ControlModifier) m.push("Ctrl")
        if (event.modifiers & Qt.AltModifier) m.push("Alt")
        if (event.modifiers & Qt.ShiftModifier) m.push("Shift")
        return m
    }

    function keyName(event) {
        var k = event.key
        if (k >= Qt.Key_A && k <= Qt.Key_Z) return String.fromCharCode(k)
        if (k >= Qt.Key_0 && k <= Qt.Key_9) return String.fromCharCode(k)
        if (k >= Qt.Key_F1 && k <= Qt.Key_F24) return "F" + (k - Qt.Key_F1 + 1)
        var shifted = {}
        shifted[Qt.Key_Exclam] = "1"; shifted[Qt.Key_At] = "2"; shifted[Qt.Key_NumberSign] = "3"; shifted[Qt.Key_Dollar] = "4"
        shifted[Qt.Key_Percent] = "5"; shifted[Qt.Key_AsciiCircum] = "6"; shifted[Qt.Key_Ampersand] = "7"; shifted[Qt.Key_Asterisk] = "8"
        shifted[Qt.Key_ParenLeft] = "9"; shifted[Qt.Key_ParenRight] = "0"
        if ((event.modifiers & Qt.ShiftModifier) && shifted[k] !== undefined) return shifted[k]
        var named = {}
        named[Qt.Key_Space] = "Space"; named[Qt.Key_Return] = "Return"; named[Qt.Key_Enter] = "Return"; named[Qt.Key_Tab] = "Tab"
        named[Qt.Key_Backtab] = "Tab"; named[Qt.Key_Backspace] = "Backspace"; named[Qt.Key_Insert] = "Ins"; named[Qt.Key_Delete] = "Del"
        named[Qt.Key_Home] = "Home"; named[Qt.Key_End] = "End"; named[Qt.Key_Left] = "Left"; named[Qt.Key_Right] = "Right"
        named[Qt.Key_Up] = "Up"; named[Qt.Key_Down] = "Down"; named[Qt.Key_PageUp] = "PgUp"; named[Qt.Key_PageDown] = "PgDown"
        named[Qt.Key_Print] = "Print"; named[Qt.Key_Slash] = "/"; named[Qt.Key_Comma] = ","; named[Qt.Key_Period] = "."
        named[Qt.Key_Semicolon] = ";"; named[Qt.Key_Apostrophe] = "'"; named[Qt.Key_BracketLeft] = "["; named[Qt.Key_BracketRight] = "]"
        named[Qt.Key_Backslash] = "\\"; named[Qt.Key_Minus] = "-"; named[Qt.Key_Equal] = "="; named[Qt.Key_QuoteLeft] = "`"
        named[Qt.Key_Escape] = "Esc"; named[Qt.Key_Question] = "/"; named[Qt.Key_Plus] = "="; named[Qt.Key_Underscore] = "-"
        return named[k] || ""
    }

    function startRecording(id) {
        if (page.recording === id)
            return
        page.pending = null
        page.errors = {}
        page.held = []
        page.recording = id
        catcher.forceActiveFocus()
        Sys.run(helper("record 30"))
    }

    function stopRecording() {
        if (page.recording === "")
            return
        page.recording = ""
        page.held = []
        Sys.run(helper("record stop"))
    }

    function setError(id, text) {
        var e = {}
        e[id] = text
        page.errors = e
        errorTimer.restart()
    }

    function commit(id, chord, force) {
        page.busy = id
        Sys.run(helper("set " + (force ? "--force " : "") + page.quote(id) + " " + page.quote(chord)), function (out) {
            page.busy = ""
            var r = null
            try {
                r = JSON.parse(out.trim().split("\n").pop())
            } catch (e) {
                page.setError(id, out.trim().replace(/^kwick-keys: /, ""))
                return
            }
            if (!r.ok && r.conflicts && r.conflicts.length && !force) {
                page.pending = { id: id, chord: chord, conflicts: r.conflicts }
                return
            }
            page.pending = null
            if (!r.ok && r.error)
                page.setError(id, r.error)
            page.load()
        })
    }

    function reset(id) {
        page.busy = id
        Sys.run(helper("reset " + page.quote(id)), function (out) {
            page.busy = ""
            try { page.km = JSON.parse(out) } catch (e) { page.load() }
        })
    }

    function resetAll() {
        page.confirmReset = false
        page.busy = "*"
        Sys.run(helper("reset"), function (out) {
            page.busy = ""
            try { page.km = JSON.parse(out) } catch (e) { page.load() }
            page.note = "All shortcuts are back to the KwickOS defaults"
            page.noteBad = false
        })
    }

    function conflictText(a) {
        return a.conflicts.map(function (c) { return "Also used by " + c.with }).filter(function (t, i, all) { return all.indexOf(t) === i }).join(" · ")
    }

    function pendingText(p) {
        var names = []
        p.conflicts.forEach(function (c) {
            var n = c.with + (c.where && !c.here ? " in " + c.where.join(", ") : "")
            if (names.indexOf(n) < 0) names.push(n)
        })
        return "Already used by " + names.join(" and ") + "."
    }

    Component.onCompleted: load()
    Component.onDestruction: if (page.recording !== "") Sys.run(helper("record stop"))

    Timer {
        id: errorTimer
        interval: 5000
        onTriggered: page.errors = {}
    }

    Timer {
        id: resetTimer
        interval: 3500
        onTriggered: page.confirmReset = false
    }

    Item {
        id: catcher
        width: 0
        height: 0
        focus: page.recording !== ""
        Keys.onPressed: event => {
            event.accepted = true
            if (page.recording === "")
                return
            var mods = page.modsOf(event)
            if (event.key === Qt.Key_Meta || event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R || event.key === Qt.Key_Control
                    || event.key === Qt.Key_Alt || event.key === Qt.Key_Shift || event.key === Qt.Key_AltGr || event.key === Qt.Key_Hyper_L) {
                page.held = mods
                return
            }
            var id = page.recording
            if (event.key === Qt.Key_Escape && mods.length === 0) {
                page.stopRecording()
                return
            }
            if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) && mods.length === 0) {
                page.stopRecording()
                page.commit(id, "none", false)
                return
            }
            var name = page.keyName(event)
            if (name === "") {
                page.setError(id, "That key can't be used in a shortcut")
                return
            }
            page.stopRecording()
            page.commit(id, mods.concat([name]).join("+"), false)
        }
        Keys.onReleased: event => {
            event.accepted = true
            if (page.recording !== "")
                page.held = page.modsOf(event).filter(function (m) {
                    return !((event.key === Qt.Key_Meta || event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R) && m === "Meta")
                        && !(event.key === Qt.Key_Control && m === "Ctrl") && !(event.key === Qt.Key_Alt && m === "Alt") && !(event.key === Qt.Key_Shift && m === "Shift")
                })
        }
        onActiveFocusChanged: if (!activeFocus && page.recording !== "") page.stopRecording()
    }

    FileDialog {
        id: exporter
        title: "Export Keyboard Shortcuts"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "json"
        nameFilters: ["Keyboard shortcuts (*.json)"]
        currentFolder: StandardPaths.writableLocation(StandardPaths.DocumentsLocation)
        selectedFile: StandardPaths.writableLocation(StandardPaths.DocumentsLocation) + "/kwick-keys.json"
        onAccepted: {
            var path = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""))
            Sys.run(page.helper("export " + page.quote(path)), function (out, code) {
                page.note = code === 0 ? out.trim().replace(/^exported/, "Exported") : out.trim().replace(/^kwick-keys: /, "")
                page.noteBad = code !== 0
            })
        }
    }

    FileDialog {
        id: importer
        title: "Import Keyboard Shortcuts"
        nameFilters: ["Keyboard shortcuts (*.json)", "All files (*)"]
        currentFolder: StandardPaths.writableLocation(StandardPaths.DocumentsLocation)
        onAccepted: {
            var path = decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, ""))
            Sys.run(page.helper("import " + page.quote(path)), function (out, code) {
                var lines = out.trim().split("\n")
                page.note = code === 0 ? lines[0].replace(/^imported/, "Imported") + (lines.length > 1 ? " · " + (lines.length - 1) + " conflict" + (lines.length > 2 ? "s" : "") : "")
                                       : out.trim().replace(/^kwick-keys: /, "").replace(/\n\s*/g, " · ")
                page.noteBad = code !== 0
                page.load()
            })
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        text: "Every KwickOS shortcut in one place. Click a shortcut and press the keys you want; it works right away and follows you to " + (page.km.session === "gnome" ? "Plasma, Hyprland and sway." : page.km.session === "kde" ? "GNOME, Hyprland and sway." : "Plasma and GNOME.")
        color: Theme.sub
        font.family: Theme.sans
        font.pixelSize: 13
        wrapMode: Text.WordWrap
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 30
            radius: 8
            color: Theme.field
            border.width: 1
            border.color: search.activeFocus ? Theme.accent : Theme.line
            Item {
                x: 9
                anchors.verticalCenter: parent.verticalCenter
                width: 13
                height: 13
                Rectangle { width: 9; height: 9; radius: 4.5; color: "transparent"; border.width: 1.5; border.color: Theme.sub }
                Rectangle { x: 8; y: 9; width: 5; height: 1.5; color: Theme.sub; rotation: 45; transformOrigin: Item.Left }
            }
            TextInput {
                id: search
                anchors.fill: parent
                anchors.leftMargin: 30
                anchors.rightMargin: 8
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.text
                font.family: Theme.sans
                font.pixelSize: 13
                selectionColor: Theme.accent
                clip: true
                onTextChanged: page.query = text
                Keys.onEscapePressed: text = ""
                Text { visible: !search.text.length; anchors.verticalCenter: parent.verticalCenter; text: "Search shortcuts"; color: Theme.sub; font: search.font }
            }
        }

        Btn {
            text: "Show Cheat Sheet"
            onClicked: Sys.run("kwick-keys show")
        }
    }

    Rectangle {
        visible: page.conflicted.length > 0 && page.query === ""
        Layout.fillWidth: true
        implicitHeight: warnRow.implicitHeight + 20
        radius: 10
        color: Theme.warnBg
        border.width: 1
        border.color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.35)
        RowLayout {
            id: warnRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 10
            Rectangle {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: 1
                width: 18
                height: 18
                radius: 9
                color: Theme.warn
                Text { anchors.centerIn: parent; text: "!"; color: "#ffffff"; font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.Bold }
            }
            Text {
                Layout.fillWidth: true
                text: (page.conflicted.length === 1 ? "1 shortcut is" : page.conflicted.length + " shortcuts are") + " also used by something else in " + page.sessionName(page.km.session) + ": "
                      + page.conflicted.map(function (a) { return a.title }).join(", ") + ". Only one of them will work."
                color: Theme.warnText
                font.family: Theme.sans
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }
    }

    Repeater {
        model: page.groups
        delegate: ColumnLayout {
            id: group
            required property var modelData
            Layout.fillWidth: true
            spacing: 10

            SectionTitle { text: group.modelData.title.toUpperCase() }
            Card {
                Repeater {
                    model: group.modelData.rows
                    delegate: Item {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool rec: page.recording === modelData.id
                        readonly property bool asking: !!page.pending && page.pending.id === modelData.id
                        readonly property string error: page.errors[modelData.id] || ""
                        readonly property bool last: index === group.modelData.rows.length - 1
                        readonly property string hint: rec ? (modelData.each.length ? (modelData.eachKind === "arrows" ? "Hold the modifiers and press an arrow key · Esc cancels" : "Hold the modifiers and press a number · Esc cancels")
                                                              : "Press the new shortcut · Esc cancels · " + (page.mac ? "⌫" : "Backspace") + " removes it")
                                                     : ""
                        Layout.fillWidth: true
                        implicitHeight: Math.max(54, textCol.implicitHeight + 22) + (asking ? ask.implicitHeight + 12 : 0)

                        ColumnLayout {
                            id: textCol
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.right: trailing.left
                            anchors.rightMargin: 12
                            y: Math.round((Math.max(54, implicitHeight + 22) - implicitHeight) / 2)
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.title
                                color: Theme.text
                                font.family: Theme.sans
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: row.error !== "" ? row.error
                                    : row.hint !== "" ? row.hint
                                    : row.modelData.conflicts.length ? page.conflictText(row.modelData)
                                    : row.modelData.fixed ? (row.modelData.subtitle !== "" ? row.modelData.subtitle + ". " : "") + "Reserved by KwickOS"
                                    : row.modelData.subtitle
                                color: row.error !== "" ? Theme.bad : row.hint !== "" ? Theme.accent : row.modelData.conflicts.length ? Theme.warn : Theme.sub
                                font.family: Theme.sans
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }
                        }

                        RowLayout {
                            id: trailing
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            y: Math.round((Math.max(54, textCol.implicitHeight + 22) - height) / 2)
                            spacing: 8

                            Btn {
                                visible: row.modelData.custom && !row.rec
                                text: "Reset"
                                enabled: page.busy === ""
                                onClicked: page.reset(row.modelData.id)
                            }

                            Rectangle {
                                id: field
                                readonly property bool hot: hover.containsMouse && !row.modelData.fixed
                                Layout.preferredWidth: Math.max(132, caps.implicitWidth + 20)
                                implicitHeight: 30
                                radius: 8
                                color: row.modelData.fixed ? "transparent" : row.rec ? Theme.field : field.hot ? Theme.controlHover : Theme.light ? Theme.bg : Theme.field
                                border.width: row.rec ? 2 : row.modelData.fixed ? 0 : 1
                                border.color: row.rec ? Theme.accent : row.modelData.conflicts.length ? Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.7) : Theme.line
                                opacity: page.busy === row.modelData.id ? 0.5 : 1

                                Row {
                                    id: caps
                                    anchors.centerIn: parent
                                    spacing: 5
                                    visible: !row.rec
                                    Repeater {
                                        model: row.modelData.caps.slice(0, 2)
                                        delegate: Row {
                                            id: chord
                                            required property var modelData
                                            required property int index
                                            spacing: 3
                                            Text {
                                                visible: chord.index > 0
                                                anchors.verticalCenter: parent.verticalCenter
                                                rightPadding: 2
                                                text: "or"
                                                color: Theme.sub
                                                font.family: Theme.sans
                                                font.pixelSize: 11
                                            }
                                            Repeater {
                                                model: chord.modelData
                                                delegate: Keycap { required property string modelData; text: modelData }
                                            }
                                        }
                                    }
                                    Text {
                                        visible: row.modelData.caps.length === 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "None"
                                        color: Theme.sub
                                        font.family: Theme.sans
                                        font.pixelSize: 12
                                    }
                                }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 3
                                    visible: row.rec
                                    Repeater {
                                        model: page.modCaps(page.held)
                                        delegate: Keycap { required property string modelData; text: modelData; live: true }
                                    }
                                    Text {
                                        visible: page.held.length === 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Type shortcut…"
                                        color: Theme.sub
                                        font.family: Theme.sans
                                        font.pixelSize: 12
                                        SequentialAnimation on opacity {
                                            running: row.rec
                                            loops: Animation.Infinite
                                            NumberAnimation { to: 0.45; duration: 650; easing.type: Easing.InOutSine }
                                            NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutSine }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: hover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !row.modelData.fixed && page.busy === ""
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: row.rec ? page.stopRecording() : page.startRecording(row.modelData.id)
                                }
                            }
                        }

                        RowLayout {
                            id: ask
                            visible: row.asking
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 12
                            spacing: 8
                            Text {
                                Layout.fillWidth: true
                                text: row.asking ? page.pendingText(page.pending) + " Use it here and remove it there?" : ""
                                color: Theme.warnText
                                font.family: Theme.sans
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                            }
                            Btn { text: "Cancel"; onClicked: page.pending = null }
                            Btn { text: "Use Anyway"; primary: true; onClicked: page.commit(page.pending.id, page.pending.chord, true) }
                        }

                        Rectangle {
                            visible: !row.last
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
        }
    }

    Item {
        visible: page.loaded && page.groups.length === 0
        Layout.fillWidth: true
        implicitHeight: 90
        Text {
            anchors.centerIn: parent
            text: "No shortcuts match “" + page.query.trim() + "”"
            color: Theme.sub
            font.family: Theme.sans
            font.pixelSize: 13
        }
    }

    SectionTitle { text: "MANAGE" }
    Card {
        Cell {
            title: "Import and export"
            subtitle: page.note !== "" ? page.note : "Move your shortcuts to another computer as a small JSON file"
            Btn { text: "Import…"; onClicked: importer.open() }
            Btn { text: "Export…"; onClicked: exporter.open() }
        }
        Cell {
            last: true
            title: "Reset all shortcuts"
            subtitle: page.km.actions.some(function (a) { return a.custom }) ? page.km.actions.filter(function (a) { return a.custom }).length + " changed from the KwickOS defaults" : "Every shortcut is on its KwickOS default"
            Btn {
                text: page.confirmReset ? "Reset All Shortcuts" : "Reset All…"
                danger: !page.confirmReset
                primary: page.confirmReset
                enabled: page.busy === "" && page.km.actions.some(function (a) { return a.custom })
                onClicked: {
                    if (page.confirmReset) {
                        page.resetAll()
                    } else {
                        page.confirmReset = true
                        resetTimer.restart()
                    }
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        text: "Shortcuts are saved in ~/.config/kwick/keys.json and written into each desktop when you sign in. In a terminal, kwick-keys lists, changes and checks them."
        color: Theme.sub
        font.family: Theme.sans
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }

    component Keycap: Rectangle {
        property string text
        property bool live: false
        readonly property bool glyph: text.length === 1 && "⌘⌥⌃⇧↩⇥⌫⌦←→↑↓⇞⇟↖↘".indexOf(text) >= 0
        implicitWidth: Math.max(implicitHeight, label.implicitWidth + 12)
        implicitHeight: 21
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        radius: 5
        color: live ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Theme.light ? 0.12 : 0.28) : Theme.light ? Theme.card : Theme.cardHi
        border.width: 1
        border.color: live ? Theme.accent : Theme.lineStrong
        Rectangle {
            visible: !parent.live
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 3
            anchors.rightMargin: 3
            height: 1
            color: Theme.line
        }
        Text {
            id: label
            anchors.centerIn: parent
            text: parent.text
            color: Theme.text
            font.family: Theme.sans
            font.pixelSize: parent.glyph ? 12.5 : 11
            font.weight: Font.Medium
        }
    }
}
