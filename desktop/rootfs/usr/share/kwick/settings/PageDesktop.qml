import QtQuick
import QtQuick.Layouts

ColumnLayout {
    spacing: 10

    SectionTitle { text: "DESKTOP SESSION" }
    Card {
        Repeater {
            model: [
                { id: "kde", name: "KDE Plasma", sub: "The default KwickOS desktop with KWin effects, Wayland and X11" },
                { id: "gnome", name: "GNOME", sub: "GNOME Shell with dock, blur, wobbly windows and a 3D cube" },
                { id: "hyprland", name: "Tiling", sub: "Sway tiling compositor with waybar and wofi" }
            ]
            delegate: Item {
                id: sr
                required property var modelData
                required property int index
                readonly property string state: Sys.sessions[modelData.id] || ""
                readonly property bool installed: state.indexOf("installed") === 0
                readonly property bool isDefault: state.indexOf("default") >= 0
                Layout.fillWidth: true
                implicitHeight: 72
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 16
                    spacing: 14
                    Rectangle {
                        width: 40
                        height: 40
                        radius: 10
                        color: ["#1d99f3", "#4a86cf", "#e0a63a"][sr.index]
                        Image { anchors.centerIn: parent; width: 24; height: 24; source: "icons/desktop.svg"; sourceSize.width: 48; sourceSize.height: 48 }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text { Layout.fillWidth: true; text: sr.modelData.name; color: Theme.text; font.family: Theme.sans; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Text { Layout.fillWidth: true; text: sr.modelData.sub; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 12; wrapMode: Text.WordWrap }
                    }
                    Rectangle {
                        visible: sr.isDefault
                        implicitWidth: dl.implicitWidth + 18
                        implicitHeight: 22
                        radius: 11
                        color: "#1e3a28"
                        Text { id: dl; anchors.centerIn: parent; text: "Default"; color: Theme.good; font.family: Theme.sans; font.pixelSize: 12; font.weight: Font.Medium }
                    }
                    Btn { visible: !sr.installed && Object.keys(Sys.sessions).length > 0; text: "Install"; onClicked: Sys.terminal("kwick-desktop install " + sr.modelData.id) }
                    Btn { visible: sr.installed && !sr.isDefault; text: "Make default"; primary: true; onClicked: Sys.setDefaultSession(sr.modelData.id) }
                }
                Rectangle {
                    visible: sr.index < 2
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
    Text {
        Layout.leftMargin: 4
        Layout.fillWidth: true
        text: "Log out to switch to the new default session."
        color: Theme.sub
        font.family: Theme.sans
        font.pixelSize: 12
    }
}
