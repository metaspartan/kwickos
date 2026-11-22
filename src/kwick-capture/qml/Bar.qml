import QtQuick
import KwickCapture

Item {
    id: root
    property int edge: 0
    property bool menuOpen: false
    property int focusIndex: -1
    property int menuIndex: -1
    readonly property int pad: 28
    readonly property var modes: [
        { id: "screen", icon: "screen", tip: "Capture Entire Screen" },
        { id: "window", icon: "window", tip: "Capture Selected Window" },
        { id: "selection", icon: "selection", tip: "Capture Selected Portion" },
        { id: "recordScreen", icon: "rec-screen", tip: "Record Entire Screen" },
        { id: "recordSelection", icon: "rec-selection", tip: "Record Selected Portion" },
        { id: "text", icon: "text", tip: "Copy Text from Selection" },
        { id: "color", icon: "color", tip: "Pick a Color" }
    ]
    readonly property var stops: ["close", "screen", "window", "selection", "recordScreen", "recordSelection", "text", "color", "options", "capture"]
    readonly property bool recordMode: Capture.mode === "recordScreen" || Capture.mode === "recordSelection"
    readonly property string actionText: recordMode ? "Record" : Capture.mode === "text" ? "Copy Text" : Capture.mode === "color" ? "Pick Color" : "Capture"
    readonly property var menuItems: [
        { header: true, text: "Save to" },
        { key: "saveTo", value: "desktop", text: "Desktop" },
        { key: "saveTo", value: "pictures", text: "Pictures" },
        { key: "saveTo", value: "clipboard", text: "Clipboard" },
        { header: true, text: "Timer" },
        { key: "timer", value: 0, text: "None" },
        { key: "timer", value: 5, text: "5 Seconds" },
        { key: "timer", value: 10, text: "10 Seconds" },
        { header: true, text: "Options" },
        { key: "microphone", value: true, text: "Record Microphone" },
        { key: "pointer", value: true, text: "Show Mouse Pointer" }
    ]
    property string hoverTip: ""
    property Item hoverItem: null

    Palette { id: pal }

    focus: true
    Component.onCompleted: forceActiveFocus()

    function isChecked(item) {
        if (item.key === "saveTo")
            return Capture.saveTo === item.value
        if (item.key === "timer")
            return Capture.timer === item.value
        if (item.key === "microphone")
            return Capture.microphone
        if (item.key === "pointer")
            return Capture.pointer
        return false
    }

    function applyItem(item) {
        if (item.key === "saveTo")
            Capture.saveTo = item.value
        else if (item.key === "timer")
            Capture.timer = item.value
        else if (item.key === "microphone")
            Capture.microphone = !Capture.microphone
        else if (item.key === "pointer")
            Capture.pointer = !Capture.pointer
    }

    function activate(stop) {
        if (stop === "close")
            Capture.closeBar()
        else if (stop === "options")
            toggleMenu()
        else if (stop === "capture")
            Capture.capture()
        else
            Capture.mode = stop
    }

    function toggleMenu() {
        menuOpen = !menuOpen
        menuIndex = -1
    }

    function moveMenu(step) {
        let i = menuIndex
        do {
            i = (i + step + menuItems.length) % menuItems.length
        } while (menuItems[i].header)
        menuIndex = i
    }

    function syncMask() {
        Capture.setMask(root.Window.window, menuOpen ? [] : [Qt.rect(bar.x - 4, bar.y - 4, bar.width + 8, bar.height + 8)])
    }

    onMenuOpenChanged: syncMask()
    onWidthChanged: syncMask()
    onHeightChanged: syncMask()

    Keys.onPressed: event => {
        const key = event.key
        if (key === Qt.Key_Escape) {
            if (menuOpen)
                menuOpen = false
            else
                Capture.closeBar()
        } else if (menuOpen && (key === Qt.Key_Down || key === Qt.Key_Up)) {
            moveMenu(key === Qt.Key_Down ? 1 : -1)
        } else if (menuOpen && (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) && menuIndex >= 0) {
            applyItem(menuItems[menuIndex])
        } else if (key === Qt.Key_Right || (key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier))) {
            menuOpen = false
            focusIndex = (focusIndex + 1) % stops.length
        } else if (key === Qt.Key_Left || key === Qt.Key_Backtab) {
            menuOpen = false
            focusIndex = focusIndex <= 0 ? stops.length - 1 : focusIndex - 1
        } else if (key === Qt.Key_Space && focusIndex >= 0) {
            activate(stops[focusIndex])
        } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
            if (focusIndex >= 0 && stops[focusIndex] !== "capture" && modes.some(m => m.id === stops[focusIndex])) {
                Capture.mode = stops[focusIndex]
                Capture.capture()
            } else if (focusIndex >= 0) {
                activate(stops[focusIndex])
            } else {
                Capture.capture()
            }
        } else if (key === Qt.Key_Down && focusIndex === stops.indexOf("options")) {
            menuOpen = true
            moveMenu(1)
        } else {
            return
        }
        event.accepted = true
    }

    MouseArea {
        anchors.fill: parent
        visible: root.menuOpen
        onClicked: root.menuOpen = false
    }

    Rectangle {
        id: tip
        readonly property point at: root.hoverItem ? root.hoverItem.mapToItem(root, root.hoverItem.width / 2, 0) : Qt.point(0, 0)
        visible: root.hoverTip !== "" && !root.menuOpen
        width: tipText.implicitWidth + 16
        height: 24
        radius: 6
        x: Math.round(Math.max(4, Math.min(root.width - width - 4, at.x - width / 2)))
        y: bar.y - height - 10
        color: pal.menu
        border.width: 1
        border.color: pal.border
        Text {
            id: tipText
            anchors.centerIn: parent
            text: root.hoverTip
            color: pal.label
            font.family: pal.sans
            font.pixelSize: 12
        }
    }

    PanelBox {
        id: bar
        width: strip.implicitWidth + 16
        height: 52
        x: Math.round((root.width - width) / 2)
        y: root.height - height - root.pad - root.edge
        onXChanged: root.syncMask()
        onYChanged: root.syncMask()
        onWidthChanged: root.syncMask()

        Row {
            id: strip
            anchors.centerIn: parent
            spacing: 2

            Item {
                width: 34
                height: 36
                Rectangle {
                    id: closeButton
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    radius: 11
                    color: closeArea.containsMouse ? pal.pressed : pal.selected
                    Glyph {
                        anchors.centerIn: parent
                        name: "close"
                        width: 12
                        height: 12
                        tint: pal.label
                    }
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -3
                        radius: width / 2
                        color: "transparent"
                        border.width: 2
                        border.color: pal.accent
                        visible: root.focusIndex === 0
                    }
                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        onClicked: Capture.closeBar()
                        onContainsMouseChanged: {
                            root.hoverItem = containsMouse ? closeButton : null
                            root.hoverTip = containsMouse ? "Close" : ""
                        }
                    }
                }
            }

            Repeater {
                model: root.modes
                Row {
                    id: group
                    required property var modelData
                    required property int index
                    spacing: 2
                    Item {
                        visible: group.index === 0 || group.index === 3 || group.index === 5
                        width: 13
                        height: 36
                        Rectangle {
                            anchors.centerIn: parent
                            width: 1
                            height: 24
                            color: pal.hairline
                        }
                    }
                    ToolButton {
                        id: modeButton
                        icon: group.modelData.icon
                        iconSize: 26
                        width: 46
                        checked: Capture.mode === group.modelData.id
                        focused: root.stops[root.focusIndex] === group.modelData.id
                        onClicked: {
                            root.menuOpen = false
                            Capture.mode = group.modelData.id
                        }
                        onDoubleClicked: Capture.capture()
                        onHoveredChanged: {
                            root.hoverItem = hovered ? modeButton : null
                            root.hoverTip = hovered ? group.modelData.tip : ""
                        }
                    }
                }
            }

            Item {
                width: 13
                height: 36
                Rectangle {
                    anchors.centerIn: parent
                    width: 1
                    height: 24
                    color: pal.hairline
                }
            }

            ToolButton {
                id: optionsButton
                text: "Options"
                chevron: true
                checked: root.menuOpen
                focused: root.stops[root.focusIndex] === "options"
                onClicked: root.toggleMenu()
            }

            Item {
                width: 6
                height: 36
            }

            Rectangle {
                id: captureButton
                width: captureLabel.implicitWidth + 30
                height: 34
                anchors.verticalCenter: parent.verticalCenter
                radius: pal.small
                color: captureArea.pressed ? Qt.darker(pal.accent, 1.15) : captureArea.containsMouse ? Qt.lighter(pal.accent, 1.08) : pal.accent
                Text {
                    id: captureLabel
                    anchors.centerIn: parent
                    text: root.actionText
                    color: "#ffffff"
                    font.family: pal.sans
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -3
                    radius: parent.radius + 3
                    color: "transparent"
                    border.width: 2
                    border.color: Qt.rgba(pal.accent.r, pal.accent.g, pal.accent.b, 0.5)
                    visible: root.focusIndex === root.stops.indexOf("capture")
                }
                MouseArea {
                    id: captureArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: Capture.capture()
                }
            }

            Item {
                width: 4
                height: 36
            }
        }
    }

    Loader {
        active: root.menuOpen
        sourceComponent: Component {
            PanelBox {
                id: menu
                fill: pal.menu
                radius: Math.round(9 * pal.ratio)
                rings: 5
                width: 212
                height: menuColumn.implicitHeight + 12
                x: Math.round(Math.min(root.width - width - 8, bar.x + optionsButton.mapToItem(bar, 0, 0).x - 6))
                y: bar.y - height - 8

                Column {
                    id: menuColumn
                    x: 6
                    y: 6
                    width: parent.width - 12
                    spacing: 0
                    Repeater {
                        model: root.menuItems
                        Column {
                            id: entry
                            required property var modelData
                            required property int index
                            width: menuColumn.width
                            Rectangle {
                                visible: entry.modelData.header === true && entry.index > 0
                                width: parent.width - 12
                                x: 6
                                height: 1
                                color: pal.hairline
                            }
                            Item {
                                visible: entry.modelData.header === true && entry.index > 0
                                width: 1
                                height: 4
                            }
                            MenuRow {
                                width: menuColumn.width
                                text: entry.modelData.text
                                header: entry.modelData.header === true
                                checked: root.isChecked(entry.modelData)
                                focused: root.menuIndex === entry.index
                                onTriggered: root.applyItem(entry.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
