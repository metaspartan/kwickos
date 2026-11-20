import QtQuick
import QtQuick.Window
import org.kde.kwin
import org.kde.kirigami as Kirigami

Item {
    id: root

    readonly property bool dark: Kirigami.Theme.backgroundColor.hslLightness < 0.5
    readonly property color accent: dark ? "#60cdff" : "#005fb8"
    readonly property var layouts: [
        [[0, 0, 1 / 2, 1], [1 / 2, 0, 1 / 2, 1]],
        [[0, 0, 2 / 3, 1], [2 / 3, 0, 1 / 3, 1]],
        [[0, 0, 1 / 3, 1], [1 / 3, 0, 1 / 3, 1], [2 / 3, 0, 1 / 3, 1]],
        [[0, 0, 1 / 2, 1], [1 / 2, 0, 1 / 2, 1 / 2], [1 / 2, 1 / 2, 1 / 2, 1 / 2]],
        [[0, 0, 1 / 2, 1 / 2], [1 / 2, 0, 1 / 2, 1 / 2], [0, 1 / 2, 1 / 2, 1 / 2], [1 / 2, 1 / 2, 1 / 2, 1 / 2]],
        [[0, 0, 1 / 4, 1], [1 / 4, 0, 1 / 2, 1], [3 / 4, 0, 1 / 4, 1]]
    ]
    readonly property var zones: {
        const list = []
        for (let l = 0; l < layouts.length; ++l) {
            for (let z = 0; z < layouts[l].length; ++z)
                list.push([l, z])
        }
        return list
    }
    readonly property int shadowMargin: 28
    readonly property int buttonWidth: 46
    readonly property int buttonHeight: 32

    property var target: null
    property var pending: null
    property bool keyboard: false
    property int focusZone: -1

    function snappable(w) {
        return w && w.normalWindow && w.resizeable && w.moveable && !w.fullScreen && !w.minimized
    }

    function maximizeButton(w) {
        const g = w.frameGeometry
        return Qt.rect(g.x + g.width - 2 * buttonWidth, g.y, buttonWidth, w.noBorder ? 48 : buttonHeight)
    }

    function inside(r, p, pad) {
        return p.x >= r.x - pad && p.x < r.x + r.width + pad && p.y >= r.y - pad && p.y < r.y + r.height + pad
    }

    function panelRect() {
        return Qt.rect(flyout.x + shadowMargin, flyout.y + shadowMargin, panel.width, panel.height)
    }

    function open(w, viaKeyboard) {
        if (!snappable(w))
            return
        target = w
        keyboard = viaKeyboard
        focusZone = viaKeyboard ? 0 : -1
        const b = maximizeButton(w)
        const a = Workspace.clientArea(KWin.FullScreenArea, w)
        let px = Math.round(b.x + b.width / 2 - panel.width / 2)
        px = Math.max(a.x + 8, Math.min(px, a.x + a.width - panel.width - 8))
        let py = b.y + b.height + 2
        py = Math.max(a.y + 8, Math.min(py, a.y + a.height - panel.height - 8))
        flyout.x = px - shadowMargin
        flyout.y = py - shadowMargin
        flyout.visible = true
        if (viaKeyboard)
            flyout.requestActivate()
        keys.forceActiveFocus()
    }

    function close() {
        hoverDelay.stop()
        leaveDelay.stop()
        pending = null
        flyout.visible = false
        target = null
        focusZone = -1
    }

    function zoneRect(w, z) {
        const a = Workspace.clientArea(KWin.MaximizeArea, w)
        const x0 = Math.round(a.x + z[0] * a.width)
        const y0 = Math.round(a.y + z[1] * a.height)
        const x1 = Math.round(a.x + (z[0] + z[2]) * a.width)
        const y1 = Math.round(a.y + (z[1] + z[3]) * a.height)
        return Qt.rect(x0, y0, x1 - x0, y1 - y0)
    }

    function near(a, b) {
        return Math.abs(a - b) <= 8
    }

    function region(w) {
        const a = Workspace.clientArea(KWin.MaximizeArea, w)
        const g = w.frameGeometry
        const l = near(g.x, a.x)
        const r = near(g.x + g.width, a.x + a.width)
        const t = near(g.y, a.y)
        const b = near(g.y + g.height, a.y + a.height)
        const hw = near(g.width, a.width / 2)
        const hh = g.height < a.height * 0.75
        if (l && r && t && b)
            return "full"
        if (hw && t && b)
            return l ? "left" : r ? "right" : ""
        if (hw && hh) {
            if (t && !b)
                return l ? "topleft" : r ? "topright" : ""
            if (b && !t)
                return l ? "bottomleft" : r ? "bottomright" : ""
        }
        return ""
    }

    function untile(w) {
        try {
            if (w.tile)
                w.tile = null
        } catch (e) {
        }
    }

    function quickTile(w, mode) {
        Workspace.activeWindow = w
        Workspace["slotWindowQuickTile" + mode]()
    }

    function snapTo(w, z) {
        const modes = {
            "0,0,0.5,1": "Left",
            "0.5,0,0.5,1": "Right",
            "0,0,0.5,0.5": "TopLeft",
            "0.5,0,0.5,0.5": "TopRight",
            "0,0.5,0.5,0.5": "BottomLeft",
            "0.5,0.5,0.5,0.5": "BottomRight"
        }
        const names = {
            "Left": "left",
            "Right": "right",
            "TopLeft": "topleft",
            "TopRight": "topright",
            "BottomLeft": "bottomleft",
            "BottomRight": "bottomright"
        }
        const mode = modes[z.join(",")]
        if (mode) {
            if (region(w) !== names[mode]) {
                if (region(w) === "full")
                    w.setMaximize(false, false)
                quickTile(w, mode)
            }
            return
        }
        w.setMaximize(false, false)
        untile(w)
        w.frameGeometry = zoneRect(w, z)
        Workspace.activeWindow = w
    }

    function apply(l, z) {
        const w = target
        close()
        if (snappable(w))
            snapTo(w, layouts[l][z])
    }

    function up() {
        const w = Workspace.activeWindow
        if (!snappable(w))
            return
        switch (region(w)) {
        case "left":
            quickTile(w, "TopLeft")
            break
        case "right":
            quickTile(w, "TopRight")
            break
        case "bottomleft":
            quickTile(w, "Top")
            break
        case "bottomright":
            quickTile(w, "Top")
            break
        case "full":
            break
        default:
            if (w.maximizable)
                w.setMaximize(true, true)
        }
    }

    function down() {
        const w = Workspace.activeWindow
        if (!w || !w.normalWindow)
            return
        switch (region(w)) {
        case "full":
            untile(w)
            w.setMaximize(false, false)
            break
        case "left":
            quickTile(w, "BottomLeft")
            break
        case "right":
            quickTile(w, "BottomRight")
            break
        case "topleft":
            quickTile(w, "Bottom")
            break
        case "topright":
            quickTile(w, "Bottom")
            break
        default:
            if (w.minimizable)
                w.minimized = true
        }
    }

    ShortcutHandler {
        name: "Kwick Snap Layouts"
        text: "Open snap layouts"
        sequence: "Meta+Z"
        onActivated: {
            if (flyout.visible)
                root.close()
            else
                root.open(Workspace.activeWindow, true)
        }
    }

    ShortcutHandler {
        name: "Kwick Snap Up"
        text: "Maximize or snap to the top quarter"
        sequence: "Meta+Up"
        onActivated: root.up()
    }

    ShortcutHandler {
        name: "Kwick Snap Down"
        text: "Restore or minimize or snap to the bottom quarter"
        sequence: "Meta+Down"
        onActivated: root.down()
    }

    Connections {
        target: Workspace

        function onCursorPosChanged() {
            const p = Workspace.cursorPos
            if (flyout.visible) {
                if (root.keyboard)
                    return
                const over = root.inside(root.panelRect(), p, 0) || (root.target && root.inside(root.maximizeButton(root.target), p, 0))
                if (over)
                    leaveDelay.stop()
                else if (!leaveDelay.running)
                    leaveDelay.start()
                return
            }
            const w = Workspace.activeWindow
            if (root.snappable(w) && w.maximizable && root.inside(root.maximizeButton(w), p, 0)) {
                if (root.pending !== w) {
                    root.pending = w
                    hoverDelay.restart()
                }
            } else if (root.pending) {
                root.pending = null
                hoverDelay.stop()
            }
        }

        function onWindowActivated(w) {
            if (flyout.visible && !root.keyboard && w && w !== root.target)
                root.close()
        }
    }

    Timer {
        id: hoverDelay
        interval: 450
        onTriggered: {
            const w = root.pending
            root.pending = null
            if (w && w === Workspace.activeWindow && root.inside(root.maximizeButton(w), Workspace.cursorPos, 0))
                root.open(w, false)
        }
    }

    Timer {
        id: leaveDelay
        interval: 300
        onTriggered: root.close()
    }

    Window {
        id: flyout
        visible: false
        transientParent: null
        flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool
        color: "transparent"
        width: panel.width + 2 * root.shadowMargin
        height: panel.height + 2 * root.shadowMargin
        onActiveChanged: {
            if (!active && root.keyboard && visible)
                root.close()
        }

        Item {
            id: keys
            anchors.fill: parent
            focus: true

            Keys.onPressed: event => {
                const n = root.zones.length
                if (event.key === Qt.Key_Escape) {
                    root.close()
                } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                    root.focusZone = (root.focusZone + 1 + n) % n
                } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
                    root.focusZone = (root.focusZone - 1 + n) % n
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    if (root.focusZone >= 0)
                        root.apply(root.zones[root.focusZone][0], root.zones[root.focusZone][1])
                } else {
                    return
                }
                event.accepted = true
            }
        }

        Kirigami.ShadowedRectangle {
            id: panel
            x: root.shadowMargin
            y: root.shadowMargin
            width: grid.width + 2 * 14
            height: grid.height + 2 * 14
            radius: 8
            color: root.dark ? "#2c2c2c" : "#f9f9f9"
            border.width: 1
            border.color: root.dark ? Qt.rgba(1, 1, 1, 0.09) : Qt.rgba(0, 0, 0, 0.1)
            shadow.size: 24
            shadow.yOffset: 8
            shadow.color: root.dark ? Qt.rgba(0, 0, 0, 0.37) : Qt.rgba(0, 0, 0, 0.14)

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onExited: root.focusZone = root.keyboard ? root.focusZone : -1
            }

            Grid {
                id: grid
                x: 14
                y: 14
                columns: 3
                columnSpacing: 14
                rowSpacing: 14

                Repeater {
                    model: root.layouts.length

                    delegate: Item {
                        id: thumb
                        required property int index
                        readonly property var zones: root.layouts[index]
                        width: 92
                        height: 58

                        Repeater {
                            model: thumb.zones.length

                            delegate: Rectangle {
                                id: zone
                                required property int index
                                readonly property var spec: thumb.zones[index]
                                readonly property int flat: {
                                    let i = 0
                                    for (let l = 0; l < thumb.index; ++l)
                                        i += root.layouts[l].length
                                    return i + index
                                }
                                readonly property bool lit: root.focusZone === flat
                                readonly property int x0: Math.round(spec[0] * thumb.width) + (spec[0] > 0 ? 2 : 0)
                                readonly property int y0: Math.round(spec[1] * thumb.height) + (spec[1] > 0 ? 2 : 0)
                                readonly property int x1: Math.round((spec[0] + spec[2]) * thumb.width) - (spec[0] + spec[2] < 0.999 ? 2 : 0)
                                readonly property int y1: Math.round((spec[1] + spec[3]) * thumb.height) - (spec[1] + spec[3] < 0.999 ? 2 : 0)
                                x: x0
                                y: y0
                                width: x1 - x0
                                height: y1 - y0
                                radius: 4
                                color: lit ? root.accent : (root.dark ? Qt.rgba(1, 1, 1, 0.08) : "#ffffff")
                                border.width: 1
                                border.color: lit ? root.accent : (root.dark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.14))

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: root.focusZone = zone.flat
                                    onClicked: root.apply(thumb.index, zone.index)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
