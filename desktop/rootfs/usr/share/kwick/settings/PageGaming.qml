import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: page
    spacing: 10

    property var mods: ({})
    property bool bootMode: false
    readonly property var catalog: [
        { id: "steam", name: "Steam", color: "#1b6aa5", open: "steam" },
        { id: "gamescope-session", name: "Game Mode session", color: "#5e5ce6", open: "" },
        { id: "proton", name: "Proton-GE and ProtonUp-Qt", color: "#bf5af2", open: "flatpak run net.davidotek.pupgui2" },
        { id: "launchers", name: "Lutris, Heroic and Bottles", color: "#d9843b", open: "lutris" },
        { id: "overlay", name: "MangoHud, GameMode and vkBasalt", color: "#30b0c7", open: "" },
        { id: "controllers", name: "Controllers", color: "#34c759", open: "" },
        { id: "handheld", name: "Handheld Daemon", color: "#ff9f0a", open: "" },
        { id: "waydroid", name: "Waydroid", color: "#32ade6", open: "waydroid show-full-ui" },
        { id: "decky", name: "Decky Loader", color: "#ff453a", open: "" },
        { id: "streaming", name: "Sunshine and Moonlight", color: "#ffd60a", open: "flatpak run com.moonlight_stream.Moonlight" },
        { id: "rgb", name: "OpenRGB", color: "#ff375f", open: "flatpak run org.openrgb.OpenRGB" },
        { id: "tweaks", name: "Performance tweaks", color: "#8e8e93", open: "" }
    ]

    function load() {
        Sys.run("sh " + Sys.dir + "helpers/gaming.sh", function (out) {
            var m = {}
            var boot = false
            out.split("\n").forEach(function (l) {
                var p = l.split("|")
                if (p.length >= 4)
                    m[p[0]] = { state: p[1], desc: p[2], note: p[3] }
                else if (p.length === 2 && p[0] === "boot")
                    boot = p[1].trim() === "yes"
            })
            page.mods = m
            page.bootMode = boot
        })
    }

    function act(verb, id) {
        Sys.terminal(Sys.elevated("/usr/bin/kwick-gaming " + verb + " " + id))
        refreshTimer.restart()
    }

    Component.onCompleted: load()

    Timer {
        id: refreshTimer
        interval: 4000
        onTriggered: page.load()
    }

    SectionTitle { text: "GAMING MODULES" }
    Card {
        Repeater {
            model: page.catalog
            delegate: Item {
                id: gr
                required property var modelData
                required property int index
                readonly property var info: page.mods[modelData.id] || ({ state: "no", desc: "", note: "" })
                readonly property bool have: info.state === "yes"
                readonly property bool part: info.state === "part"
                readonly property bool gone: info.state === "na"
                Layout.fillWidth: true
                implicitHeight: 64
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 16
                    spacing: 14
                    Rectangle {
                        width: 38
                        height: 38
                        radius: 10
                        color: gr.modelData.color
                        opacity: gr.gone ? 0.4 : 1
                        Image { anchors.centerIn: parent; width: 22; height: 22; source: "icons/gaming.svg"; sourceSize.width: 44; sourceSize.height: 44 }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text { Layout.fillWidth: true; text: gr.modelData.name; color: Theme.text; font.family: Theme.sans; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Text {
                            Layout.fillWidth: true
                            text: gr.have ? "Installed" : gr.part ? "Partly installed" : gr.gone ? "Unavailable: " + gr.info.note : gr.info.desc
                            color: gr.have ? Theme.good : gr.part ? Theme.accent : Theme.sub
                            font.family: Theme.sans
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }
                    Btn { visible: (gr.have || gr.part) && gr.modelData.open !== ""; text: "Open"; onClicked: Sys.run(gr.modelData.open) }
                    Btn { visible: gr.have || gr.part; text: "Remove"; danger: true; onClicked: page.act("remove", gr.modelData.id) }
                    Btn { visible: !gr.have; enabled: !gr.gone; text: gr.part ? "Repair" : "Install"; primary: true; onClicked: page.act("install", gr.modelData.id) }
                }
                Rectangle {
                    visible: gr.index < page.catalog.length - 1
                    height: 1
                    color: Theme.line
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                }
            }
        }
    }

    SectionTitle { text: "GAME MODE" }
    Card {
        Cell {
            last: true
            title: "Boot straight into Game Mode"
            subtitle: (page.mods["gamescope-session"] && page.mods["gamescope-session"].state === "yes")
                      ? "Skips the desktop login like a Steam Deck. Use Switch to Desktop in Steam to come back."
                      : "Install the Game Mode session above first"
            Toggle {
                checked: page.bootMode
                enabled: page.mods["gamescope-session"] !== undefined && page.mods["gamescope-session"].state === "yes"
                onToggled: function (v) { page.act("session", v ? "boot-on" : "boot-off") }
            }
        }
    }

    SectionTitle { text: "ONE CLICK" }
    Card {
        Cell {
            last: true
            title: "Install everything"
            subtitle: "Every module this machine supports. Performance tools: use gamemoderun %command% or mangohud %command% in Steam launch options"
            Btn { text: "Install all"; primary: true; onClicked: page.act("all", "") }
        }
    }
    Btn { Layout.alignment: Qt.AlignRight; text: "Refresh status"; onClicked: page.load() }
}
