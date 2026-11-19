import QtQuick
import QtQuick.Layouts
import QtQuick.Window

ColumnLayout {
    id: page
    spacing: 10

    readonly property var mainList: [
        { id: "wobbly", title: "Wobbly windows", sub: "Windows deform like jelly while you drag them" },
        { id: "lamp", title: "Magic lamp", sub: "Minimized windows are sucked into the dock" },
        { id: "flip", title: "3D open and close", sub: "Windows spring in and sink away", only: "hyprland" },
        { id: "cube", title: "3D desktop cube", sub: "Meta+C shows your desktops as a cube with windows floating above the faces" },
        { id: "blur", title: "Blur", sub: "Frosted glass behind menus, docks and panels" },
        { id: "liquidglass", title: "Liquid Glass", sub: "The dock, menu bar, menus and notifications bend, frost and catch the light like real glass (needs a GPU)" },
        { id: "transparency", title: "Translucency", sub: "Inactive windows, dialogs and menus turn slightly see-through" }
    ]
    readonly property var moreList: [
        { id: "sheet", title: "Sheet", sub: "Dialogs drop down from the top of their window" },
        { id: "dim", title: "Dim inactive windows", sub: "Draws attention to the window you are working in" },
        { id: "overview", title: "Overview", sub: "Window and desktop overview" }
    ]
    readonly property var kwickStyles: ["none", "scale", "fade", "glide", "flip", "flame", "dissolve", "fallapart"]
    readonly property var styles: Sys.openCloseList.map(function (o) {
        return { id: o.id, label: o.label, sub: o.sub, group: page.kwickStyles.indexOf(o.id) >= 0 ? "KwickOS" : "Burn My Windows" }
    })
    readonly property var style: {
        for (var i = 0; i < styles.length; i++)
            if (styles[i].id === Sys.openClose) return styles[i]
        return null
    }
    readonly property bool flameOptions: Sys.backend === "kde" && Sys.openClose === "flame"
    readonly property bool flipOptions: Sys.backend === "kde" && Sys.openClose === "flip"

    property int wobble: 6
    property int sway: 7
    property string flipStyle: "flip"
    property string flameStyle: "classic"
    property int flameHeight: 100
    property int windowDepth: 5

    function loadParams() {
        Sys.run("kwick-effects param wobbly", function (out) {
            var p = String(out).trim().split(/\s+/)
            if (p.length === 2) {
                page.wobble = parseInt(p[0])
                page.sway = parseInt(p[1])
            }
        })
        Sys.run("kwick-effects flame-style", function (out) {
            var v = String(out).trim()
            if (["classic", "inferno", "ember", "blue", "legacy"].indexOf(v) >= 0) page.flameStyle = v
        })
        Sys.run("kwick-effects flame-height", function (out) {
            var v = parseInt(String(out).trim())
            if (v >= 50 && v <= 200) page.flameHeight = v
        })
        Sys.run("kwick-effects param depth", function (out) {
            var v = parseInt(String(out).trim())
            if (v >= 0 && v <= 10) page.windowDepth = v
        })
        Sys.run("kwick-effects param flip", function (out) {
            var v = String(out).trim()
            if (["flip", "door", "tilt"].indexOf(v) >= 0) page.flipStyle = v
        })
    }
    function applyWobble() {
        Sys.run("kwick-effects wobbly " + page.wobble + " " + page.sway)
    }
    Component.onCompleted: loadParams()

    function shown(item) {
        return Sys.has(item.id) && (!item.only || item.only === Sys.backend)
    }
    function lastVisible(list) {
        for (var i = list.length - 1; i >= 0; i--)
            if (shown(list[i])) return i
        return -1
    }
    function anyVisible(list) {
        return lastVisible(list) >= 0
    }
    function preview() {
        previewTimer.stop()
        previewWindow.visible = false
        previewWindow.visible = true
        previewTimer.interval = Math.max(page.style && Sys.openCloseDuration > 0 ? Sys.openCloseDuration : 400, 400) + 900
        previewTimer.start()
    }

    Window {
        id: previewWindow
        width: 420
        height: 260
        title: page.style ? page.style.label : "Preview"
        color: Theme.bg
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 6
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                width: 44
                height: 44
                radius: 12
                color: "#bf5af2"
                Image { anchors.centerIn: parent; width: 26; height: 26; source: "icons/effects.svg"; sourceSize.width: 104; sourceSize.height: 104 }
            }
            Text { Layout.alignment: Qt.AlignHCenter; text: page.style ? page.style.label : ""; color: Theme.text; font.family: Theme.sans; font.pixelSize: 17; font.weight: Font.DemiBold }
            Text { Layout.alignment: Qt.AlignHCenter; text: page.style ? page.style.sub : ""; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 12 }
        }
    }
    Timer {
        id: previewTimer
        onTriggered: previewWindow.visible = false
    }

    Rectangle {
        visible: Sys.backend === "kde" && Sys.compositor !== "gpu"
        Layout.fillWidth: true
        implicitHeight: warnRow.implicitHeight + 28
        radius: 12
        color: "#2e2412"
        border.width: 1
        border.color: "#55ff9f0a"
        RowLayout {
            id: warnRow
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12
            Rectangle { width: 8; height: 8; radius: 4; color: Theme.warn }
            Text {
                Layout.fillWidth: true
                text: Sys.compositor === "software"
                      ? "KWin is rendering in software, which disables animations. Install the GPU drivers for your hardware, then log in again."
                      : "No OpenGL compositor is running, so effects cannot animate. Install the GPU drivers (kwick-gpu), then log in again."
                color: "#f5d9a8"
                font.family: Theme.sans
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }
            Btn { text: "Install kwick-gpu"; primary: true; onClicked: Sys.terminal("kwick-gpu install") }
        }
    }

    SectionTitle { text: "PRESET" }
    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        Repeater {
            model: [
                { id: "off", name: "Off", sub: "No animations" },
                { id: "subtle", name: "Subtle", sub: "Scale, blur, magic lamp" },
                { id: "fluid", name: "Fluid", sub: "Wobbly windows, 3D flip" },
                { id: "full", name: "Full", sub: "Flames, 3D cube, translucency" }
            ]
            delegate: Rectangle {
                id: pc
                required property var modelData
                readonly property bool on: Sys.preset === modelData.id
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 112
                radius: 12
                color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12) : Theme.card
                border.width: on ? 2 : 1
                border.color: on ? Theme.accent : Theme.line
                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 14
                    spacing: 3
                    Text { Layout.fillWidth: true; text: pc.modelData.name; color: Theme.text; font.family: Theme.sans; font.pixelSize: 14; font.weight: Font.DemiBold }
                    Text { Layout.fillWidth: true; text: pc.modelData.sub; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 12; wrapMode: Text.WordWrap }
                }
                Rectangle {
                    x: 14
                    y: 14
                    width: 22
                    height: 22
                    radius: 7
                    color: ["#6e6e78", "#0a84ff", "#af52de", "#ff375f"][["off", "subtle", "fluid", "full"].indexOf(pc.modelData.id)]
                    Image { anchors.centerIn: parent; width: 14; height: 14; source: "icons/effects.svg"; sourceSize.width: 56; sourceSize.height: 56 }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Sys.setPreset(pc.modelData.id) }
            }
        }
    }
    Text {
        visible: Sys.preset === "custom"
        Layout.leftMargin: 4
        text: "Custom: you changed individual effects."
        color: Theme.sub
        font.family: Theme.sans
        font.pixelSize: 12
    }

    SectionTitle { text: "OPEN AND CLOSE"; visible: page.styles.length > 1 }
    Card {
        visible: page.styles.length > 1
        Cell {
            title: "Animation"
            subtitle: page.style ? page.style.sub : ""
            last: Sys.openCloseDuration <= 0 && !page.flameOptions && !page.flipOptions
            Btn { text: "Preview"; onClicked: page.preview() }
            Pick {
                options: page.styles
                current: Sys.openClose
                onPicked: (id) => Sys.setOpenClose(id, page.preview)
            }
        }
        Cell {
            visible: Sys.openCloseDuration > 0
            last: !page.flameOptions && !page.flipOptions
            title: "Duration"
            subtitle: "How long the animation plays"
            Sld {
                id: durationSlider
                implicitWidth: 220
                from: 100
                to: 3000
                step: 50
                value: Sys.openCloseDuration
                onReleased: (v) => Sys.setOpenCloseDuration(v)
                Connections {
                    target: Sys
                    function onOpenCloseDurationChanged() { if (!durationSlider.pressed) durationSlider.value = Sys.openCloseDuration }
                }
            }
            Text { Layout.preferredWidth: 58; horizontalAlignment: Text.AlignRight; text: (durationSlider.value / 1000).toFixed(2) + " s"; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 13 }
        }
        Cell {
            visible: page.flameOptions
            title: "Flame style"
            subtitle: "Classic rises above the window, Inferno flares out wide, Ember is a subtle burn with sparks, Blue is a gas flame, Legacy is the classic particle burn"
            Seg {
                options: [{ id: "classic", label: "Classic" }, { id: "inferno", label: "Inferno" }, { id: "ember", label: "Ember" }, { id: "blue", label: "Blue" }, { id: "legacy", label: "Legacy" }]
                current: page.flameStyle
                onPicked: (id) => { page.flameStyle = id; Sys.run("kwick-effects flame-style " + id, page.preview) }
            }
        }
        Cell {
            visible: page.flameOptions
            last: true
            title: "Flame height"
            subtitle: "How far the flames rise past the window edges"
            Sld {
                implicitWidth: 220
                from: 50
                to: 200
                step: 10
                value: page.flameHeight
                onValueChanged: if (pressed) page.flameHeight = value
                onReleased: (v) => { page.flameHeight = v; Sys.run("kwick-effects flame-height " + v) }
            }
            Text { Layout.preferredWidth: 40; horizontalAlignment: Text.AlignRight; text: page.flameHeight + "%"; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 13 }
        }
        Cell {
            visible: page.flipOptions
            last: true
            title: "3D style"
            subtitle: "Flip turns the window around its middle, Door hinges it on the left, Tilt drops it back"
            Seg {
                options: [{ id: "flip", label: "Flip" }, { id: "door", label: "Door" }, { id: "tilt", label: "Tilt" }]
                current: page.flipStyle
                onPicked: (id) => { page.flipStyle = id; Sys.run("kwick-effects param flip " + id, page.preview) }
            }
        }
    }

    SectionTitle { text: "WINDOW EFFECTS"; visible: page.anyVisible(page.mainList) }
    Card {
        visible: page.anyVisible(page.mainList)
        Repeater {
            model: page.mainList
            delegate: Cell {
                required property var modelData
                required property int index
                visible: page.shown(modelData)
                title: modelData.title
                subtitle: modelData.sub
                last: index === page.lastVisible(page.mainList)
                Toggle {
                    checked: Sys.fx[modelData.id] === "on"
                    onToggled: (v) => Sys.setEffect(modelData.id, v)
                }
            }
        }
    }

    SectionTitle { text: Sys.backend === "kde" ? "WOBBLE AND CUBE" : "WOBBLE"; visible: Sys.backend === "kde" || Sys.backend === "gnome" || Sys.backend === "hyprland" }
    Card {
        visible: Sys.backend === "kde" || Sys.backend === "gnome" || Sys.backend === "hyprland"
        Cell {
            title: "Wobble"
            subtitle: "How far windows stretch while you drag them"
            Sld {
                implicitWidth: 220
                from: 1
                to: 10
                step: 1
                value: page.wobble
                onValueChanged: if (pressed) page.wobble = value
                onReleased: (v) => { page.wobble = v; page.applyWobble() }
            }
            Text { Layout.preferredWidth: 22; horizontalAlignment: Text.AlignRight; text: page.wobble; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 13 }
        }
        Cell {
            last: Sys.backend !== "kde"
            title: "Sway"
            subtitle: "How curvy and fluid the wobble is: softer springs, finer mesh"
            Sld {
                implicitWidth: 220
                from: 1
                to: 10
                step: 1
                value: page.sway
                onValueChanged: if (pressed) page.sway = value
                onReleased: (v) => { page.sway = v; page.applyWobble() }
            }
            Text { Layout.preferredWidth: 22; horizontalAlignment: Text.AlignRight; text: page.sway; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 13 }
        }
        Cell {
            visible: Sys.backend === "kde"
            last: true
            title: "Window depth"
            subtitle: "How far windows float off the cube faces while it turns"
            Sld {
                implicitWidth: 220
                from: 0
                to: 10
                step: 1
                value: page.windowDepth
                onValueChanged: if (pressed) page.windowDepth = value
                onReleased: (v) => { page.windowDepth = v; Sys.run("kwick-effects param depth " + v) }
            }
            Text { Layout.preferredWidth: 22; horizontalAlignment: Text.AlignRight; text: page.windowDepth; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 13 }
        }
    }

    SectionTitle { text: "SWITCHING" }
    Card {
        Cell {
            title: "Desktop switch animation"
            subtitle: "How the screen changes when you move to another desktop"
            last: Sys.backend !== "kde"
            Seg {
                options: Sys.backend === "kde"
                         ? [{ id: "slide", label: "Slide" }, { id: "fade", label: "Fade" }, { id: "cube", label: "Cube" }, { id: "none", label: "None" }]
                         : Sys.backend === "gnome"
                           ? [{ id: "slide", label: "Slide" }, { id: "cube", label: "Cube" }]
                           : [{ id: "slide", label: "Slide" }, { id: "fade", label: "Fade" }, { id: "cube", label: "Vertical" }, { id: "none", label: "None" }]
                current: Sys.switchMode
                onPicked: (id) => Sys.setSwitch(id)
            }
        }
        Cell {
            visible: Sys.backend === "kde"
            last: true
            title: "Alt+Tab style"
            subtitle: "Windows thumbnails, Cover Flow, Flip or an icon grid"
            Seg {
                options: [{ id: "windows", label: "Windows" }, { id: "cover", label: "Cover" }, { id: "flip", label: "Flip" }, { id: "grid", label: "Grid" }]
                current: Sys.tabboxMode
                onPicked: (id) => Sys.setTabbox(id)
            }
        }
    }

    SectionTitle { text: "MORE"; visible: page.anyVisible(page.moreList) }
    Card {
        visible: page.anyVisible(page.moreList)
        Repeater {
            model: page.moreList
            delegate: Cell {
                required property var modelData
                required property int index
                visible: page.shown(modelData)
                title: modelData.title
                subtitle: modelData.sub
                last: index === page.lastVisible(page.moreList)
                Toggle {
                    checked: Sys.fx[modelData.id] === "on"
                    onToggled: (v) => Sys.setEffect(modelData.id, v)
                }
            }
        }
    }
}
