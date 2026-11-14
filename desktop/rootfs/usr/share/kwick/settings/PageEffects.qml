import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: page
    spacing: 10

    readonly property var mainList: [
        { id: "wobbly", title: "Wobbly windows", sub: "Windows deform like jelly while you drag them" },
        { id: "lamp", title: "Magic lamp", sub: "Minimized windows are sucked into the dock" },
        { id: "flame", title: "Flame open and close", sub: "Windows ignite when they open and burn away when they close" },
        { id: "flip", title: "3D flip open and close", sub: "Windows swing in and out in perspective with lighting (replaces flame)" },
        { id: "cube", title: "3D desktop cube", sub: "Meta+C shows your desktops as a cube with windows floating above the faces" },
        { id: "blur", title: "Blur", sub: "Frosted glass behind menus, docks and panels" },
        { id: "transparency", title: "Translucency", sub: "Inactive windows, dialogs and menus turn slightly see-through" }
    ]
    readonly property var moreList: [
        { id: "dissolve", title: "Dissolve", sub: "Closing windows crumble into glowing dust (replaces flame)" },
        { id: "glide", title: "Glide", sub: "Windows glide in and out in 3D (replaces flame)" },
        { id: "fallapart", title: "Fall apart", sub: "Closing windows shatter into pieces (replaces flame)" },
        { id: "sheet", title: "Sheet", sub: "Dialogs drop down from the top of their window" },
        { id: "dim", title: "Dim inactive windows", sub: "Draws attention to the window you are working in" },
        { id: "overview", title: "Overview", sub: "Window and desktop overview" }
    ]

    property int wobble: 6
    property int sway: 7
    property bool wobbleReady: false

    function loadParams() {
        Sys.run("kwick-effects param wobbly", function (out) {
            var p = String(out).trim().split(/\s+/)
            if (p.length === 2) {
                page.wobble = parseInt(p[0])
                page.sway = parseInt(p[1])
            }
            page.wobbleReady = true
        })
        Sys.run("kwick-effects flame-style", function (out) {
            var v = String(out).trim()
            if (v === "classic" || v === "inferno" || v === "ember" || v === "blue") page.flameStyle = v
        })
        Sys.run("kwick-effects flame-height", function (out) {
            var v = parseInt(String(out).trim())
            if (v >= 50 && v <= 200) page.flameHeight = v
        })
        Sys.run("kwick-effects param flip", function (out) {
            var v = String(out).trim()
            if (v === "flip" || v === "door" || v === "tilt") page.flipStyle = v
        })
    }
    property string flipStyle: "flip"
    property string flameStyle: "classic"
    property int flameHeight: 100
    function applyWobble() {
        Sys.run("kwick-effects wobbly " + page.wobble + " " + page.sway)
    }
    Component.onCompleted: loadParams()

    function lastVisible(list) {
        for (var i = list.length - 1; i >= 0; i--)
            if (Sys.has(list[i].id)) return i
        return -1
    }
    function anyVisible(list) {
        return lastVisible(list) >= 0
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
                { id: "subtle", name: "Subtle", sub: "Fades, blur, magic lamp" },
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
                color: on ? "#252a3a" : Theme.card
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

    SectionTitle { text: "WINDOW EFFECTS"; visible: page.anyVisible(page.mainList) }
    Card {
        visible: page.anyVisible(page.mainList)
        Repeater {
            model: page.mainList
            delegate: Cell {
                required property var modelData
                required property int index
                visible: Sys.has(modelData.id)
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

    SectionTitle { text: "WOBBLE, FLAME AND 3D"; visible: Sys.backend === "kde" || Sys.backend === "gnome" || Sys.backend === "hyprland" }
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
            title: "Flame style"
            subtitle: "Classic rises above the window, Inferno flares out wide, Ember is a subtle burn with sparks, Blue is a gas flame"
            Seg {
                options: [{ id: "classic", label: "Classic" }, { id: "inferno", label: "Inferno" }, { id: "ember", label: "Ember" }, { id: "blue", label: "Blue" }]
                current: page.flameStyle
                onPicked: (id) => { page.flameStyle = id; Sys.run("kwick-effects flame-style " + id) }
            }
        }
        Cell {
            visible: Sys.backend === "kde"
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
            visible: Sys.backend === "kde"
            last: true
            title: "3D open and close style"
            subtitle: "Flip turns the window around its middle, Door hinges it on the left, Tilt drops it back"
            Seg {
                options: [{ id: "flip", label: "Flip" }, { id: "door", label: "Door" }, { id: "tilt", label: "Tilt" }]
                current: page.flipStyle
                onPicked: (id) => { page.flipStyle = id; Sys.run("kwick-effects param flip " + id) }
            }
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
                visible: Sys.has(modelData.id)
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
