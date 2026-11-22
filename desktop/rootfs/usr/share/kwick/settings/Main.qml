import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

ApplicationWindow {
    id: win
    visible: false
    width: 1000
    height: 760
    minimumWidth: 860
    minimumHeight: 560
    title: "KwickOS Settings"
    color: Theme.bg

    property int current: 0
    property string query: ""
    readonly property var pages: [
        { name: "Appearance", icon: "layout", color: "#0a84ff", page: "PageAppearance.qml" },
        { name: "Dock", icon: "dock", color: "#5e5ce6", page: "PageDock.qml" },
        { name: "Effects", icon: "effects", color: "#bf5af2", page: "PageEffects.qml" },
        { name: "Fonts", icon: "fonts", color: "#8e8e93", page: "PageFonts.qml" },
        { name: "Desktop Session", icon: "desktop", color: "#ff9f0a", page: "PageDesktop.qml" },
        { name: "Shells", icon: "shells", color: "#3c4048", page: "PageShells.qml", keys: "terminal zsh bash fish nushell nu elvish xonsh powershell pwsh ash prompt starship powerline quickshell dux dms noctalia hyprland plasma gnome sway waybar login shell" },
        { name: "Touch & Tablet", icon: "touch", color: "#1f8f8a", page: "PageTouch.qml", keys: "touchscreen keyboard gestures rotation pen trackpad touchpad" },
        { name: "GPU", icon: "gpu", color: "#30d158", page: "PageGpu.qml" },
        { name: "Gaming", icon: "gaming", color: "#ff453a", page: "PageGaming.qml" },
        { name: "Storage", icon: "storage", color: "#64d2ff", page: "PageStorage.qml" },
        { name: "VPN", icon: "vpn", color: "#2c5aa0", page: "PageVPN.qml" },
        { name: "Nearby Share", icon: "nearby", color: "#0a84ff", page: "PageNearby.qml", keys: "airdrop localsend quick share send receive files phone transfer pin" },
        { name: "Agents", icon: "agents", color: "#5e5ce6", page: "PageAgents.qml", keys: "ai agents mcp claude codex gemini opencode ollama llama keys permissions sandbox" },
        { name: "Privacy & Security", icon: "privacy", color: "#0a84ff", page: "PagePrivacy.qml", keys: "camera microphone mic screen recording sharing location permissions flatpak portal firmware fwupd lvfs secure boot encryption security" },
        { name: "About", icon: "about", color: "#64d2ff", page: "PageAbout.qml" },
        { name: "Software Update", icon: "update", color: "#8e8e93", page: "PageUpdate.qml", keys: "updates upgrade kernel" },
        { name: "Snapshots", icon: "snapshots", color: "#22b39a", page: "PageSnapshots.qml", keys: "time machine backup restore rollback undo btrfs history versions" }
    ]

    function matches(p, q) {
        var n = p.name.toLowerCase().replace(/[^a-z0-9]+/g, " ")
        return n.indexOf(q) === 0 || (n + " " + (p.keys || "")).split(" ").some(function (w) { return w !== "" && w.indexOf(q) === 0 })
    }

    Component.onCompleted: {
        Qt.application.domain = "settings.kwickos.org"
        visible = true
        Sys.refreshAll()
        Sys.run("printenv KWICK_SETTINGS_PAGE", function (out) {
            var want = out.trim().toLowerCase().replace(/[-_]/g, " ")
            for (var j = 0; j < pages.length; j++)
                if (want !== "" && matches(pages[j], want)) { current = j; break }
        })
    }

    Timer {
        interval: 6000
        running: win.active
        repeat: true
        onTriggered: Sys.refresh()
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 252
            color: Theme.sidebar

            Rectangle {
                width: 1
                height: parent.height
                anchors.right: parent.right
                color: Theme.line
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 12
                    spacing: 10
                    Image { source: "icons/app.svg"; sourceSize.width: 80; sourceSize.height: 80; Layout.preferredWidth: 40; Layout.preferredHeight: 40 }
                    ColumnLayout {
                        spacing: 0
                        Text { text: "KwickOS"; color: Theme.text; font.family: Theme.sans; font.pixelSize: 15; font.weight: Font.DemiBold }
                        Text { text: "Settings"; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 12 }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 10
                    implicitHeight: 30
                    radius: 8
                    color: Theme.field
                    border.width: 1
                    border.color: Theme.line
                    Item {
                        x: 9
                        anchors.verticalCenter: parent.verticalCenter
                        width: 13
                        height: 13
                        Rectangle { width: 9; height: 9; radius: 4.5; color: "transparent"; border.width: 1.5; border.color: Theme.sub }
                        Rectangle { x: 8; y: 9; width: 5; height: 1.5; color: Theme.sub; rotation: 45; transformOrigin: Item.Left }
                    }
                    TextInput {
                        id: searchField
                        anchors.fill: parent
                        anchors.leftMargin: 30
                        anchors.rightMargin: 8
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text
                        font.family: Theme.sans
                        font.pixelSize: 13
                        selectionColor: Theme.accent
                        clip: true
                        onTextChanged: win.query = text.toLowerCase()
                        Text { visible: !searchField.text.length; anchors.verticalCenter: parent.verticalCenter; text: "Search"; color: Theme.sub; font: searchField.font }
                    }
                }

                Repeater {
                    model: win.pages
                    delegate: Rectangle {
                        id: item
                        required property var modelData
                        required property int index
                        readonly property bool on: win.current === index
                        Layout.fillWidth: true
                        Layout.topMargin: index === 4 || modelData.name === "About" ? 14 : 0
                        visible: win.query === "" || modelData.name.toLowerCase().indexOf(win.query) >= 0 || win.matches(modelData, win.query)
                        implicitHeight: 40
                        radius: 9
                        color: on ? Theme.accent : hover.containsMouse ? Theme.hover : "transparent"
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            spacing: 11
                            Image {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                source: "icons/obj-" + item.modelData.icon + ".svg"
                                sourceSize.width: 112
                                sourceSize.height: 112
                            }
                            Text {
                                Layout.fillWidth: true
                                text: item.modelData.name
                                color: item.on ? "#ffffff" : Theme.text
                                font.family: Theme.sans
                                font.pixelSize: 13
                                font.weight: item.on ? Font.Medium : Font.Normal
                            }
                        }
                        MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.current = item.index }
                    }
                }

                Item { Layout.fillHeight: true }

                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    text: "Layout: " + Sys.layout + "  •  Effects: " + Sys.preset
                    color: Theme.sub
                    font.family: Theme.sans
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Text {
                Layout.leftMargin: 36
                Layout.topMargin: 28
                Layout.bottomMargin: 14
                text: win.pages[win.current].name
                color: Theme.text
                font.family: Theme.sans
                font.pixelSize: 26
                font.weight: Font.DemiBold
            }

            Flickable {
                id: flick
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: loader.implicitHeight + 40
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { }

                Loader {
                    id: loader
                    x: 36
                    width: flick.width - 72
                    source: win.pages[win.current].page
                    onLoaded: flick.contentY = 0
                }
            }
        }
    }
}
