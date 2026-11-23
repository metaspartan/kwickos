import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasma5support as P5

Item {
    id: sheet

    property var keymap: ({ actions: [], categories: [], layout: "macos", session: "kde", appearance: "dark", accent: "" })
    property string query: ""
    property int sel: 0
    property bool closing: false
    signal done()

    readonly property bool dark: keymap.appearance !== "light"
    readonly property string layout: keymap.layout || "macos"
    readonly property bool mac: layout === "macos"
    readonly property color accent: keymap.accent ? keymap.accent : pal.highlight
    readonly property color ink: dark ? "#ffffff" : "#000000"
    readonly property color label: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.92 : 0.86)
    readonly property color secondary: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.55 : 0.5)
    readonly property color tertiary: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.3 : 0.28)
    readonly property color hairline: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.1 : 0.09)
    readonly property color capFill: dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(1, 1, 1, 0.95)
    readonly property color capEdge: dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.13)
    readonly property color capShadow: dark ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(0, 0, 0, 0.12)
    readonly property real capRadius: layout === "windows" ? 4 : 5
    readonly property real panelRadius: layout === "windows" ? 8 : layout === "linux" ? 12 : 16
    readonly property string font: keymap.font || Qt.application.font.family
    readonly property string sessionName: ({ kde: "Plasma", gnome: "GNOME", hyprland: "Hyprland", sway: "sway" })[keymap.session] || keymap.session
    readonly property string layoutName: ({ macos: "macOS", windows: "Windows", linux: "Linux" })[layout] || layout
    readonly property var shown: filter()
    readonly property var flat: {
        var out = []
        columns().forEach(function (col) { col.forEach(function (g) { g.rows.forEach(function (r) { out.push(r) }) }) })
        return out
    }
    readonly property int conflictCount: keymap.actions.filter(function (a) { return a.conflicts && a.conflicts.length }).length
    readonly property int columnCount: panel.width > 980 ? 3 : 2

    SystemPalette { id: pal }

    function filter() {
        var q = query.trim().toLowerCase()
        var cats = {}
        keymap.categories.forEach(function (c) { cats[c.id] = c.title })
        return keymap.actions.filter(function (a) {
            if (!a.chords.length)
                return false
            if (q === "")
                return true
            var hay = [a.title, a.subtitle, a.keywords, cats[a.category] || "", a.chords.join(" "), a.caps.map(function (c) { return c.join(" ") }).join(" ")].join(" ").toLowerCase()
            return q.split(/\s+/).every(function (w) { return hay.indexOf(w) >= 0 })
        })
    }

    function columns() {
        var groups = []
        keymap.categories.forEach(function (c) {
            var rows = shown.filter(function (a) { return a.category === c.id })
            if (rows.length)
                groups.push({ id: c.id, title: c.title, rows: rows })
        })
        var n = Math.min(columnCount, Math.max(1, groups.length))
        var weight = function (from, to) {
            var h = 0
            for (var k = from; k < to; k++)
                h += groups[k].rows.length + 1.6
            return h
        }
        var best = null
        var split = function (start, left, cuts) {
            if (left === 1) {
                var all = cuts.concat([groups.length])
                var worst = 0
                var prev = 0
                all.forEach(function (c) { worst = Math.max(worst, weight(prev, c)); prev = c })
                if (!best || worst < best.worst)
                    best = { worst: worst, cuts: all }
                return
            }
            for (var c = start + 1; c <= groups.length - left + 1; c++)
                split(c, left - 1, cuts.concat([c]))
        }
        split(0, n, [])
        var cols = []
        var prev = 0
        best.cuts.forEach(function (c) { cols.push(groups.slice(prev, c)); prev = c })
        return cols.filter(function (c) { return c.length })
    }

    function runnable(a) {
        return a.runnable && (!a.each || a.each.length === 0)
    }

    function activate(a) {
        if (!a || !runnable(a) || closing)
            return
        closing = true
        sheet.opacity = 0
        exec.connectSource("kwick-keys run '" + a.id.replace(/'/g, "") + "' #" + Date.now())
    }

    function customize() {
        if (closing)
            return
        closing = true
        sheet.opacity = 0
        exec.connectSource("setsid kwick-settings keyboard >/dev/null 2>&1 & #" + Date.now())
    }

    function move(step) {
        if (!flat.length)
            return
        sel = Math.max(0, Math.min(flat.length - 1, sel + step))
    }

    onQueryChanged: sel = 0

    P5.DataSource {
        id: exec
        engine: "executable"
        onNewData: (src, d) => {
            disconnectSource(src)
            sheet.done()
        }
    }

    Behavior on opacity { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, sheet.dark ? 0.42 : 0.22)
        opacity: shownAnim.running ? shownAnim.t : 1
    }

    MouseArea {
        anchors.fill: parent
        onClicked: sheet.done()
    }

    Repeater {
        model: 6
        Rectangle {
            required property int index
            readonly property real spread: (index + 1) * 4
            x: panel.x - spread
            y: panel.y - spread + 8 + index
            width: panel.width + 2 * spread
            height: panel.height + 2 * spread
            radius: sheet.panelRadius + spread
            color: "transparent"
            border.width: 4
            border.color: Qt.rgba(0, 0, 0, (sheet.dark ? 0.1 : 0.05) * (1 - index / 6))
        }
    }

    Rectangle {
        id: panel
        width: Math.min(1120, sheet.width - 80)
        height: Math.min(Math.max(header.height + body.contentHeight + footer.height, 300), sheet.height - 80)
        property real fullHeight: 0
        x: Math.round((sheet.width - width) / 2)
        y: Math.round((sheet.height - Math.max(height, fullHeight)) / 2)
        onHeightChanged: if (sheet.query === "") fullHeight = height
        radius: sheet.panelRadius
        color: sheet.dark ? Qt.rgba(0.135, 0.135, 0.145, 1) : Qt.rgba(0.975, 0.975, 0.975, 1)
        border.width: 1
        border.color: sheet.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
        scale: shownAnim.running ? 0.97 + 0.03 * shownAnim.t : 1
        clip: true

        NumberAnimation {
            id: shownAnim
            property real t: 0
            target: shownAnim
            property: "t"
            from: 0
            to: 1
            duration: 140
            easing.type: Easing.OutCubic
            running: true
        }

        MouseArea {
            anchors.fill: parent
        }

        Item {
            id: header
            width: parent.width
            height: 68

            Column {
                x: 26
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    text: "Keyboard Shortcuts"
                    color: sheet.label
                    font.family: sheet.font
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }
                Text {
                    text: sheet.sessionName + " · " + sheet.layoutName + " layout"
                    color: sheet.secondary
                    font.family: sheet.font
                    font.pixelSize: 12
                }
            }

            Rectangle {
                id: field
                anchors.right: parent.right
                anchors.rightMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                width: 300
                height: 34
                radius: sheet.layout === "windows" ? 5 : 9
                color: sheet.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.045)
                border.width: input.activeFocus ? 2 : 1
                border.color: input.activeFocus ? Qt.rgba(sheet.accent.r, sheet.accent.g, sheet.accent.b, 0.75) : sheet.hairline

                Item {
                    x: 11
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14
                    height: 14
                    Rectangle { width: 10; height: 10; radius: 5; color: "transparent"; border.width: 1.6; border.color: sheet.secondary }
                    Rectangle { x: 8.5; y: 9.5; width: 5.5; height: 1.6; radius: 0.8; color: sheet.secondary; rotation: 45; transformOrigin: Item.Left }
                }

                TextInput {
                    id: input
                    anchors.fill: parent
                    anchors.leftMargin: 33
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    color: sheet.label
                    font.family: sheet.font
                    font.pixelSize: 14
                    selectionColor: Qt.rgba(sheet.accent.r, sheet.accent.g, sheet.accent.b, 0.4)
                    selectedTextColor: sheet.label
                    clip: true
                    focus: true
                    onTextChanged: sheet.query = text
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            if (text !== "")
                                text = ""
                            else
                                sheet.done()
                        } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier))) {
                            sheet.move(1)
                        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
                            sheet.move(-1)
                        } else if (event.key === Qt.Key_PageDown) {
                            sheet.move(8)
                        } else if (event.key === Qt.Key_PageUp) {
                            sheet.move(-8)
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            sheet.activate(sheet.flat[sheet.sel])
                        } else {
                            return
                        }
                        event.accepted = true
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: input.text === ""
                        text: "Search shortcuts"
                        color: sheet.tertiary
                        font: input.font
                    }
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: sheet.hairline
            }
        }

        Flickable {
            id: body
            y: header.height
            width: parent.width
            height: parent.height - header.height - footer.height
            contentWidth: width
            contentHeight: grid.implicitHeight + 30
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Text {
                anchors.centerIn: parent
                visible: sheet.flat.length === 0
                text: "No shortcuts match “" + sheet.query.trim() + "”"
                color: sheet.secondary
                font.family: sheet.font
                font.pixelSize: 15
            }

            RowLayout {
                id: grid
                x: 18
                y: 14
                width: parent.width - 36
                spacing: 18

                Repeater {
                    model: sheet.columns()
                    delegate: ColumnLayout {
                        id: col
                        required property var modelData
                        Layout.alignment: Qt.AlignTop
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        spacing: 2

                        Repeater {
                            model: col.modelData
                            delegate: ColumnLayout {
                                id: group
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.topMargin: index > 0 ? 14 : 0
                                spacing: 1

                                Text {
                                    Layout.leftMargin: 10
                                    Layout.bottomMargin: 4
                                    text: sheet.mac ? group.modelData.title : group.modelData.title.toUpperCase()
                                    color: sheet.secondary
                                    font.family: sheet.font
                                    font.pixelSize: sheet.mac ? 12 : 11
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: sheet.mac ? 0 : 0.6
                                }

                                Repeater {
                                    model: group.modelData.rows
                                    delegate: Rectangle {
                                        id: row
                                        required property var modelData
                                        readonly property bool current: !!sheet.flat[sheet.sel] && sheet.flat[sheet.sel].id === modelData.id
                                        readonly property bool can: sheet.runnable(modelData)
                                        Layout.fillWidth: true
                                        implicitHeight: 32
                                        radius: sheet.layout === "windows" ? 4 : 7
                                        color: current ? Qt.rgba(sheet.accent.r, sheet.accent.g, sheet.accent.b, sheet.dark ? 0.32 : 0.16) : "transparent"

                                        Text {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 10
                                            anchors.right: keys.left
                                            anchors.rightMargin: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: row.modelData.title
                                            color: sheet.label
                                            font.family: sheet.font
                                            font.pixelSize: 13
                                            elide: Text.ElideRight
                                        }

                                        Row {
                                            id: keys
                                            anchors.right: parent.right
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 6
                                            Repeater {
                                                model: row.modelData.caps.slice(0, 2)
                                                delegate: Row {
                                                    id: chord
                                                    required property var modelData
                                                    required property int index
                                                    spacing: sheet.mac ? 3 : 4
                                                    Text {
                                                        visible: chord.index > 0
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: "or"
                                                        rightPadding: 2
                                                        color: sheet.tertiary
                                                        font.family: sheet.font
                                                        font.pixelSize: 11
                                                    }
                                                    Repeater {
                                                        model: chord.modelData
                                                        delegate: Cap {
                                                            required property string modelData
                                                            text: modelData
                                                            theme: sheet
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: row.can ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onEntered: sheet.sel = sheet.flat.findIndex(function (a) { return a.id === row.modelData.id })
                                            onClicked: sheet.activate(row.modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: footer
            anchors.bottom: parent.bottom
            width: parent.width
            height: 44

            Rectangle {
                width: parent.width
                height: 1
                color: sheet.hairline
            }

            Row {
                x: 26
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Cap { text: "↑"; theme: sheet; anchors.verticalCenter: parent.verticalCenter }
                Cap { text: "↓"; theme: sheet; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "choose"; color: sheet.secondary; font.family: sheet.font; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter; rightPadding: 10 }
                Cap { text: "↩"; theme: sheet; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "run"; color: sheet.secondary; font.family: sheet.font; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter; rightPadding: 10 }
                Cap { text: "Esc"; theme: sheet; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "close"; color: sheet.secondary; font.family: sheet.font; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14

                Text {
                    visible: sheet.conflictCount > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: sheet.conflictCount === 1 ? "1 shortcut conflicts" : sheet.conflictCount + " shortcuts conflict"
                    color: sheet.dark ? "#ff9f0a" : "#c66a00"
                    font.family: sheet.font
                    font.pixelSize: 12
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Customize Shortcuts…"
                    color: link.containsMouse ? Qt.lighter(sheet.accent, sheet.dark ? 1.2 : 0.85) : sheet.accent
                    font.family: sheet.font
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    MouseArea {
                        id: link
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sheet.customize()
                    }
                }
            }
        }
    }
}
