import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: root

    readonly property bool dark: spotlight.dark
    readonly property color accent: spotlight.accent.valid ? spotlight.accent : (dark ? "#0a84ff" : "#007aff")
    readonly property color ink: dark ? "#ffffff" : "#000000"
    readonly property color label: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.92 : 0.86)
    readonly property color secondary: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.55 : 0.5)
    readonly property color tertiary: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.3 : 0.28)
    readonly property color hairline: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.1 : 0.09)
    readonly property real ratio: Math.max(0.8, Math.min(1.2, spotlight.cornerRadius / 10))
    readonly property int fieldHeight: 52
    readonly property real radius: Math.min(fieldHeight / 2, Math.round(26 * ratio))
    readonly property real rowRadius: Math.round(8 * ratio)
    readonly property int rowHeight: 34
    readonly property int topHeight: 50
    readonly property int sectionHeight: 26
    readonly property int pad: 8
    readonly property int panelWidth: 680
    readonly property int maxBody: 412
    readonly property bool glass: spotlight.material === "glass"
    readonly property bool empty: input.text.trim() === "" && spotlight.mode === ""
    readonly property bool noResults: !empty && results.count === 0 && !spotlight.querying && settled
    readonly property bool expanded: results.count > 0 || noResults
    readonly property var modes: [
        { name: "apps", label: "Applications", icon: "apps" },
        { name: "files", label: "Files", icon: "files" },
        { name: "actions", label: "Actions", icon: "actions" },
        { name: "clipboard", label: "Clipboard", icon: "clipboard" }
    ]
    property int current: 0
    property bool settled: false
    property bool pendingRun: false
    property point pointer
    readonly property string completion: {
        const top = results.topTitle
        const typed = input.text
        if (typed === "" || top.length <= typed.length || top.substr(0, typed.length).toLowerCase() !== typed.toLowerCase())
            return ""
        return top.substr(typed.length)
    }

    function icon(name) {
        return Qt.resolvedUrl("icons/" + name + ".svg")
    }

    function select(i) {
        if (results.count === 0)
            return
        current = Math.max(0, Math.min(results.count - 1, i))
        list.positionViewAtIndex(current, ListView.Contain)
    }

    function jumpSection(step) {
        const here = list.itemAtIndex(current)
        let i = current
        const from = here ? here.section : ""
        while (i + step >= 0 && i + step < results.count) {
            i += step
            const item = list.itemAtIndex(i)
            if (!item || item.section !== from)
                break
        }
        select(i)
    }

    function runCurrent(alternate) {
        if (spotlight.current && results.count > 0)
            spotlight.run(current, alternate)
        else if (!spotlight.current || spotlight.querying)
            pendingRun = true
    }

    function runPending() {
        if (!pendingRun || !spotlight.current)
            return
        if (results.count > 0) {
            pendingRun = false
            spotlight.run(0, false)
        } else if (!spotlight.querying) {
            pendingRun = false
        }
    }

    function toggleMode(name) {
        spotlight.mode = spotlight.mode === name ? "" : name
        current = 0
        input.forceActiveFocus()
    }

    function syncPanel() {
        spotlight.setPanel(panel.x, panel.y, panel.width, panel.height, radius)
    }

    visible: spotlight.shown

    MouseArea {
        anchors.fill: parent
        onPressed: spotlight.hide()
    }

    HoverHandler {
        id: pointerWatch
        onPointChanged: {
            const p = point.scenePosition
            if (p.x === root.pointer.x && p.y === root.pointer.y)
                return
            root.pointer = p
            const local = list.mapFromItem(null, p.x, p.y)
            const i = list.indexAt(local.x + list.contentX, local.y + list.contentY)
            if (i >= 0 && list.contains(local))
                root.current = i
        }
    }

    Connections {
        target: spotlight
        function onShownChanged() {
            if (spotlight.shown)
                root.syncPanel()
            else
                root.pendingRun = false
        }
        function onCurrentChanged() {
            root.runPending()
        }
        function onQueryingChanged() {
            root.runPending()
        }
        function onActivated() {
            root.current = 0
            input.forceActiveFocus()
            input.selectAll()
        }
        function onTyped(text) {
            if (input.selectionStart !== input.selectionEnd)
                input.remove(input.selectionStart, input.selectionEnd)
            input.insert(input.cursorPosition, text)
        }
        function onSubmitted() {
            root.runCurrent(false)
        }
        function onQueryReplaced(text, cursor) {
            input.text = text
            input.cursorPosition = cursor
        }
        function onQueryChanged() {
            root.settled = false
            settle.restart()
        }
    }

    Connections {
        target: results
        function onCountChanged() {
            if (root.current >= results.count)
                root.current = 0
            root.runPending()
        }
    }

    Timer {
        id: settle
        interval: 160
        onTriggered: root.settled = true
    }

    Repeater {
        model: root.glass ? 0 : 6
        Rectangle {
            required property int index
            readonly property real spread: (index + 1) * 3.5
            x: panel.x - spread
            y: panel.y - spread + 6 + index
            width: panel.width + 2 * spread
            height: panel.height + 2 * spread
            radius: root.radius + spread
            color: "transparent"
            border.width: 3.5
            border.color: Qt.rgba(0, 0, 0, (root.dark ? 0.085 : 0.045) * (1 - index / 6))
        }
    }

    Item {
        id: panel
        x: Math.round((root.width - width) / 2)
        y: Math.round(root.height * 0.2)
        width: root.panelWidth
        height: root.fieldHeight + (root.expanded ? body.height + 1 : 0)
        onHeightChanged: root.syncPanel()
        onXChanged: root.syncPanel()
        onYChanged: root.syncPanel()

        MouseArea {
            anchors.fill: parent
        }

        Rectangle {
            anchors.fill: parent
            radius: root.radius
            color: root.glass ? (root.dark ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(1, 1, 1, 0.78))
                 : spotlight.material === "blur" ? (root.dark ? Qt.rgba(0.13, 0.13, 0.14, 0.74) : Qt.rgba(0.97, 0.97, 0.97, 0.8))
                 : (root.dark ? Qt.rgba(0.14, 0.14, 0.15, 0.97) : Qt.rgba(0.97, 0.97, 0.97, 0.98))
            border.width: root.glass ? 0 : 1
            border.color: root.dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
        }

        Item {
            id: field
            width: parent.width
            height: root.fieldHeight

            Kirigami.Icon {
                id: lens
                x: 19
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                height: 22
                source: root.icon(spotlight.mode === "" ? "search" : root.modes.find(m => m.name === spotlight.mode).icon)
                isMask: true
                color: root.secondary
            }

            TextInput {
                id: input
                x: 52
                width: chips.x - x - 10
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: 21
                color: root.label
                selectionColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.4)
                selectedTextColor: root.label
                clip: true
                focus: true
                renderType: Text.NativeRendering
                onTextChanged: {
                    root.current = 0
                    spotlight.query = text
                }
                Keys.onPressed: event => {
                    const cmd = event.modifiers & (Qt.ControlModifier | Qt.MetaModifier)
                    if (cmd && event.key >= Qt.Key_1 && event.key <= Qt.Key_4) {
                        root.toggleMode(root.modes[event.key - Qt.Key_1].name)
                    } else if (cmd && event.key === Qt.Key_Y && results.count > 0) {
                        spotlight.preview(root.current)
                    } else if (event.key === Qt.Key_Down) {
                        cmd ? root.jumpSection(1) : root.select(root.current + 1)
                    } else if (event.key === Qt.Key_Up) {
                        cmd ? root.jumpSection(-1) : root.select(root.current - 1)
                    } else if (event.key === Qt.Key_PageDown) {
                        root.select(root.current + 8)
                    } else if (event.key === Qt.Key_PageUp) {
                        root.select(root.current - 8)
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.runCurrent(cmd !== 0)
                    } else if (event.key === Qt.Key_Escape) {
                        if (text !== "")
                            text = ""
                        else if (spotlight.mode !== "")
                            spotlight.mode = ""
                        else
                            spotlight.hide()
                    } else if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Right) && ghost.visible) {
                        text = text + root.completion
                    } else if (event.key === Qt.Key_Tab) {
                        root.select(root.current + 1)
                    } else {
                        return
                    }
                    event.accepted = true
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text === ""
                    text: spotlight.mode !== "" ? "Search " + root.modes.find(m => m.name === spotlight.mode).label : spotlight.layout === "macos" ? "Spotlight Search" : "Search"
                    color: root.tertiary
                    font: input.font
                    renderType: Text.NativeRendering
                }

                Text {
                    id: ghost
                    x: input.contentWidth
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.completion !== "" && input.cursorPosition === input.text.length && input.selectedText === "" && input.contentWidth < input.width - 40
                    text: root.completion
                    color: root.tertiary
                    font: input.font
                    renderType: Text.NativeRendering
                }
            }

            Row {
                id: chips
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                opacity: root.empty || spotlight.mode !== "" ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 120 } }

                Repeater {
                    model: root.modes
                    Rectangle {
                        id: chip
                        required property var modelData
                        required property int index
                        readonly property bool on: spotlight.mode === modelData.name
                        visible: modelData.name !== "clipboard" || spotlight.clipboard
                        width: 32
                        height: 32
                        radius: 16
                        color: on ? root.accent : hover.hovered ? (root.dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.07)) : "transparent"

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: 18
                            height: 18
                            source: root.icon(chip.modelData.icon)
                            isMask: true
                            color: chip.on ? "white" : root.secondary
                        }

                        HoverHandler {
                            id: hover
                        }

                        TapHandler {
                            onTapped: root.toggleMode(chip.modelData.name)
                        }
                    }
                }
            }
        }

        Rectangle {
            y: root.fieldHeight
            width: parent.width
            height: 1
            color: root.hairline
            visible: root.expanded
        }

        Item {
            id: body
            y: root.fieldHeight + 1
            width: parent.width
            height: results.count > 0 ? Math.min(list.contentHeight, root.maxBody) + 2 * root.pad : root.noResults ? 52 : 0
            clip: true
            visible: root.expanded

            Text {
                anchors.centerIn: parent
                visible: root.noResults
                text: spotlight.mode === "clipboard" ? "Clipboard history is empty" : "No Results"
                color: root.secondary
                font.pixelSize: 15
                renderType: Text.NativeRendering
            }

            ListView {
                id: list
                anchors.fill: parent
                anchors.margins: root.pad
                model: results
                currentIndex: root.current
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                reuseItems: true
                section.property: "section"
                section.criteria: ViewSection.FullString
                section.delegate: Item {
                    required property string section
                    width: ListView.view.width
                    height: root.sectionHeight
                    Text {
                        x: 12
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 5
                        text: parent.section
                        color: root.secondary
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        renderType: Text.NativeRendering
                    }
                }
                delegate: ResultRow {
                    width: ListView.view.width
                    theme: root
                    onActivated: alternate => spotlight.run(index, alternate)
                }
            }
        }
    }
}
