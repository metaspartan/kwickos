import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: page
    spacing: 10

    property var mods: ({})
    property var gm: ({})
    property bool loaded: false
    property bool busy: false
    readonly property var session: page.mods["gamescope-session"] || ({ state: "no", desc: "", note: "" })
    readonly property bool ready: session.state === "yes"
    readonly property bool unavailable: session.state === "na"
    readonly property bool boot: page.gm.boot === "yes"
    readonly property bool quick: page.gm.quick === "yes"
    readonly property bool mangoapp: page.gm.mangoapp === "yes"
    readonly property bool mangohud: page.mods.overlay !== undefined && page.mods.overlay.state !== "no"
    readonly property string device: page.gm.device || ""
    readonly property var hudLevels: [
        { id: "off", label: "Off" },
        { id: "fps", label: "FPS" },
        { id: "compact", label: "Compact" },
        { id: "full", label: "Full" }
    ]
    readonly property var catalog: [
        { id: "steam", name: "Steam", color: "#1b6aa5", open: "steam" },
        { id: "proton", name: "Proton-GE and ProtonUp-Qt", color: "#bf5af2", open: "flatpak run net.davidotek.pupgui2" },
        { id: "launchers", name: "Lutris, Heroic and Bottles", color: "#d9843b", open: "lutris" },
        { id: "overlay", name: "MangoHud, GameMode and vkBasalt", color: "#30b0c7", open: "" },
        { id: "controllers", name: "Controllers", color: "#34c759", open: "" },
        { id: "waydroid", name: "Waydroid", color: "#32ade6", open: "waydroid show-full-ui" },
        { id: "streaming", name: "Sunshine and Moonlight", color: "#ffd60a", open: "flatpak run com.moonlight_stream.Moonlight" },
        { id: "rgb", name: "OpenRGB", color: "#ff375f", open: "flatpak run org.openrgb.OpenRGB" },
        { id: "tweaks", name: "Performance tweaks", color: "#8e8e93", open: "" }
    ]

    function load() {
        Sys.run("sh " + Sys.dir + "helpers/gaming.sh", function (out) {
            var m = {}
            var g = {}
            out.split("\n").forEach(function (l) {
                var p = l.split("|")
                if (p.length >= 4)
                    m[p[0]] = { state: p[1], desc: p[2], note: p[3] }
                else if (p.length === 2)
                    g[p[0]] = p[1].trim()
            })
            page.mods = m
            page.gm = g
            page.loaded = true
        })
    }

    function act(verb, id) {
        if (page.busy)
            return
        page.busy = true
        Sys.terminal(Sys.elevated("/usr/bin/kwick-gaming " + verb + " " + id), function () {
            page.busy = false
            page.load()
        })
        refreshTimer.restart()
    }

    function setSession(key, verb) {
        page.gm = Object.assign({}, page.gm, key)
        Sys.run(Sys.elevated("/usr/bin/kwick-gaming session " + verb), page.load)
    }

    function setHud(level) {
        page.gm = Object.assign({}, page.gm, { hud: level })
        Sys.run("kwick-gaming session hud " + level, page.load)
    }

    Component.onCompleted: load()

    Timer {
        id: refreshTimer
        interval: 4000
        onTriggered: page.load()
    }

    component ModuleRow: Item {
        id: row
        property string mod
        property string name
        property color tint
        property string open: ""
        property string blurb: ""
        property string installedText: "Installed"
        property bool last: false
        readonly property var info: page.mods[mod] || ({ state: "no", desc: "", note: "" })
        readonly property bool have: info.state === "yes"
        readonly property bool part: info.state === "part"
        readonly property bool gone: info.state === "na"
        Layout.fillWidth: true
        implicitHeight: Math.max(64, rowText.implicitHeight + 24)
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 16
            spacing: 14
            Rectangle {
                Layout.preferredWidth: 38
                Layout.preferredHeight: 38
                radius: 10
                color: row.tint
                opacity: row.gone ? 0.4 : 1
                Image { anchors.centerIn: parent; width: 22; height: 22; source: "icons/gaming.svg"; sourceSize.width: 44; sourceSize.height: 44 }
            }
            ColumnLayout {
                id: rowText
                Layout.fillWidth: true
                spacing: 2
                Text { Layout.fillWidth: true; text: row.name; color: Theme.text; font.family: Theme.sans; font.pixelSize: 14; font.weight: Font.DemiBold }
                Text {
                    Layout.fillWidth: true
                    text: row.have ? row.installedText : row.part ? "Partly installed" : row.gone ? "Unavailable: " + row.info.note : (row.blurb || row.info.desc)
                    color: row.have ? Theme.good : row.part ? Theme.accent : Theme.sub
                    font.family: Theme.sans
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
            Btn { visible: (row.have || row.part) && row.open !== ""; text: "Open"; onClicked: Sys.run(row.open) }
            Btn { visible: row.have || row.part; enabled: !page.busy; text: "Remove"; danger: true; onClicked: page.act("remove", row.mod) }
            Btn { visible: !row.have; enabled: !row.gone && !page.busy; text: row.part ? "Repair" : "Install"; primary: true; onClicked: page.act("install", row.mod) }
        }
        Rectangle {
            visible: !row.last
            height: 1
            color: Theme.line
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.right: parent.right
            anchors.bottom: parent.bottom
        }
    }

    SectionTitle { text: "GAMING MODE" }
    Card {
        Item {
            Layout.fillWidth: true
            implicitHeight: hero.implicitHeight + 32
            RowLayout {
                id: hero
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 16
                Image {
                    source: "icons/obj-gaming.svg"
                    sourceSize.width: 112
                    sourceSize.height: 112
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: 56
                    opacity: page.unavailable ? 0.5 : 1
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    RowLayout {
                        spacing: 8
                        Text { text: "Gaming Mode"; color: Theme.text; font.family: Theme.sans; font.pixelSize: 15; font.weight: Font.DemiBold }
                        Item {
                            visible: page.loaded
                            implicitWidth: badge.implicitWidth + 16
                            implicitHeight: 20
                            Rectangle {
                                anchors.fill: parent
                                radius: 10
                                color: badge.color
                                opacity: 0.16
                            }
                            Text {
                                id: badge
                                anchors.centerIn: parent
                                text: page.ready ? (page.boot ? "Starts at boot" : "Ready") : page.session.state === "part" ? "Incomplete" : page.unavailable ? "Unavailable" : "Not set up"
                                color: page.ready ? Theme.good : page.session.state === "part" ? Theme.warn : Theme.sub
                                font.family: Theme.sans
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: page.unavailable ? "Steam and Gamescope are x86 only; " + page.session.note + "."
                            : page.ready ? "Steam's controller-first interface in Gamescope, like a Steam Deck. Pick it on the login screen, or switch now: this logs out of the desktop."
                            : "Turns this computer into a console: Steam's controller-first interface in Gamescope, like a Steam Deck. Installs Steam and Gamescope."
                        color: Theme.sub
                        font.family: Theme.sans
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        lineHeight: 1.15
                    }
                }
                Btn {
                    visible: page.ready
                    text: "Switch Now"
                    primary: true
                    onClicked: Sys.run("steamos-session-select gamescope")
                }
                Btn {
                    visible: !page.ready
                    enabled: page.loaded && !page.unavailable && !page.busy
                    text: page.session.state === "part" ? "Repair…" : "Set Up…"
                    primary: true
                    onClicked: page.act("install", "gamescope-session")
                }
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
        Cell {
            opacity: page.ready ? 1 : 0.45
            title: "Boot into Gaming Mode"
            subtitle: "Starts Steam at power on. Switch to Desktop in Steam opens this desktop until you log out."
            Toggle {
                checked: page.boot
                enabled: page.ready && !page.busy
                onToggled: function (v) { page.setSession({ boot: v ? "yes" : "no" }, v ? "boot-on" : "boot-off") }
            }
        }
        Cell {
            opacity: page.ready ? 1 : 0.45
            title: "Switch without signing in"
            subtitle: page.boot ? "Always on while the computer boots into Gaming Mode."
                    : "Switch to Desktop in Steam and Return to Gaming Mode on the desktop skip the login screen."
            Toggle {
                checked: page.quick || page.boot
                enabled: page.ready && !page.boot
                onToggled: function (v) { page.setSession({ quick: v ? "yes" : "no" }, v ? "quick-on" : "quick-off") }
            }
        }
        Cell {
            opacity: page.ready ? 1 : 0.45
            last: !page.ready
            title: "Performance overlay"
            subtitle: page.mangoapp ? "Set it from Steam's quick access menu, under Performance."
                    : page.mangohud ? "MangoHud on top of games started in Gaming Mode."
                    : "Needs MangoHud, from the module list below."
            Seg {
                visible: !page.mangoapp && page.mangohud
                options: page.hudLevels
                current: page.gm.hud || "off"
                onPicked: function (id) { if (page.ready) page.setHud(id) }
            }
            Btn {
                visible: !page.mangoapp && !page.mangohud
                enabled: page.ready && !page.busy
                text: "Install"
                onClicked: page.act("install", "overlay")
            }
        }
        Cell {
            visible: page.ready
            last: true
            title: "Remove Gaming Mode"
            subtitle: "Removes the session and Gamescope. Steam and your games stay."
            Btn { text: "Remove…"; danger: true; enabled: !page.busy; onClicked: page.act("remove", "gamescope-session") }
        }
    }

    SectionTitle { text: "STEAM PLUGINS AND HANDHELDS" }
    Card {
        ModuleRow {
            mod: "decky"
            name: "Decky Loader"
            tint: "#ff453a"
            blurb: "Plugins and themes in Steam's quick access menu, for Gaming Mode"
            installedText: "Installed. Restart Steam to see the plug icon in the quick access menu."
        }
        ModuleRow {
            mod: "handheld"
            name: "Handheld support"
            tint: "#ff9f0a"
            last: true
            blurb: page.device !== "" ? "Detected " + page.device + ". Adds its buttons, gyro, TDP and the HHD overlay."
                 : "Handheld Daemon for ROG Ally, Legion Go and similar: buttons, gyro and TDP"
            installedText: "Installed. Settings are in ~/.config/hhd."
        }
    }

    SectionTitle { text: "GAMING MODULES" }
    Card {
        Repeater {
            model: page.catalog
            delegate: ModuleRow {
                required property var modelData
                required property int index
                mod: modelData.id
                name: modelData.name
                tint: modelData.color
                open: modelData.open
                last: index === page.catalog.length - 1
            }
        }
    }

    SectionTitle { text: "ONE CLICK" }
    Card {
        Cell {
            last: true
            title: "Install everything"
            subtitle: "Every module this machine supports. Performance tools: use gamemoderun %command% or mangohud %command% in Steam launch options"
            Btn { text: "Install all"; primary: true; enabled: !page.busy; onClicked: page.act("all", "") }
        }
    }
    Btn { Layout.alignment: Qt.AlignRight; text: "Refresh status"; onClicked: page.load() }
}
