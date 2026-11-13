import QtQuick
import QtQuick.Layouts

ColumnLayout {
    spacing: 10

    SectionTitle { text: "GAME LAUNCHERS" }
    Card {
        Repeater {
            model: [
                { id: "com.valvesoftware.Steam", name: "Steam", sub: "With Proton for Windows games", color: "#1b6aa5", cmd: "steam" },
                { id: "net.davidotek.pupgui2", name: "ProtonUp-Qt", sub: "Install Proton-GE and Wine builds", color: "#5e5ce6", cmd: "flatpak run net.davidotek.pupgui2" },
                { id: "com.heroicgameslauncher.hgl", name: "Heroic", sub: "Epic Games and GOG libraries", color: "#ff9f0a", cmd: "flatpak run com.heroicgameslauncher.hgl" },
                { id: "net.lutris.Lutris", name: "Lutris", sub: "Everything else, including emulators", color: "#d9843b", cmd: "flatpak run net.lutris.Lutris" }
            ]
            delegate: Item {
                id: gr
                required property var modelData
                required property int index
                readonly property bool have: Sys.gaming[modelData.id] === true
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
                        Image { anchors.centerIn: parent; width: 22; height: 22; source: "icons/gaming.svg"; sourceSize.width: 44; sourceSize.height: 44 }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text { Layout.fillWidth: true; text: gr.modelData.name; color: Theme.text; font.family: Theme.sans; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Text { Layout.fillWidth: true; text: gr.have ? "Installed" : gr.modelData.sub; color: gr.have ? Theme.good : Theme.sub; font.family: Theme.sans; font.pixelSize: 12 }
                    }
                    Btn { visible: gr.have; text: "Open"; onClicked: Sys.run(gr.modelData.cmd) }
                    Btn { visible: !gr.have; text: "Install"; primary: true; onClicked: Sys.terminal("pkexec env DISPLAY=$DISPLAY /usr/bin/kwick-gaming " + gr.modelData.id) }
                }
                Rectangle {
                    visible: gr.index < 3
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

    SectionTitle { text: "ONE CLICK" }
    Card {
        Cell {
            title: "Install everything"
            subtitle: "Steam, ProtonUp-Qt, Heroic and Lutris from Flathub"
            Btn { text: "Install all"; primary: true; onClicked: Sys.terminal("pkexec env DISPLAY=$DISPLAY /usr/bin/kwick-gaming") }
        }
        Cell {
            last: true
            title: "Performance tools"
            subtitle: "GameMode and MangoHud are preinstalled: use gamemoderun %command% or mangohud %command% in Steam launch options"
        }
    }
    Btn { Layout.alignment: Qt.AlignRight; text: "Refresh status"; onClicked: Sys.run("sh " + Sys.dir + "helpers/gaming.sh", Sys.parseGaming) }
}
