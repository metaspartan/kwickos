import QtQuick
import QtQuick.Layouts

ColumnLayout {
    spacing: 10

    Repeater {
        model: Sys.fonts
        delegate: ColumnLayout {
            id: fs
            required property var modelData
            readonly property bool current: Sys.layout === modelData.layout
            readonly property bool ready: modelData.uiOk && modelData.monoOk
            Layout.fillWidth: true
            spacing: 8

            SectionTitle { text: ({ macos: "MACOS", windows: "WINDOWS 11", linux: "LINUX" })[fs.modelData.layout] + (fs.current ? "  •  ACTIVE LAYOUT" : "") }
            Card {
                Cell {
                    title: "Interface font"
                    subtitle: fs.modelData.uiOk ? "Installed" : "Not installed"
                    Text { Layout.maximumWidth: 320; elide: Text.ElideRight; text: fs.modelData.ui; color: Theme.text; font.family: fs.modelData.uiOk ? fs.modelData.ui : Theme.sans; font.pixelSize: 15 }
                }
                Cell {
                    title: "Monospace font"
                    subtitle: fs.modelData.monoOk ? "Installed" : "Not installed"
                    Text { Layout.maximumWidth: 320; elide: Text.ElideRight; text: fs.modelData.mono; color: Theme.text; font.family: fs.modelData.monoOk ? fs.modelData.mono : Theme.mono; font.pixelSize: 15 }
                }
                Cell {
                    last: true
                    title: fs.ready ? "Use this font set" : "Install this font set"
                    subtitle: fs.ready ? "Applies to Plasma, GNOME and fontconfig" : "Downloads the packages, then you can apply them"
                    Btn {
                        visible: !fs.ready
                        text: "Install"
                        primary: true
                        onClicked: Sys.terminal("kwick-fonts " + fs.modelData.layout)
                    }
                    Btn {
                        visible: fs.ready
                        text: "Apply"
                        primary: !fs.current
                        onClicked: Sys.run("kwick-fonts apply " + fs.modelData.layout, Sys.refreshAll)
                    }
                }
            }
        }
    }

    Text {
        visible: Sys.fonts.length === 0
        text: "Reading font sets…"
        color: Theme.sub
        font.family: Theme.sans
        font.pixelSize: 13
    }
}
