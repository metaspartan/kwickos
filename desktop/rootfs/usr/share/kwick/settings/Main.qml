import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

ApplicationWindow {
    id: win
    visible: true
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
        { name: "GPU", icon: "gpu", color: "#30d158", page: "PageGpu.qml" },
        { name: "Gaming", icon: "gaming", color: "#ff453a", page: "PageGaming.qml" }
    ]

    Component.onCompleted: {
        Sys.refreshAll()
        Sys.run("printenv KWICK_SETTINGS_PAGE", function (out) {
            var want = out.trim().toLowerCase()
            for (var j = 0; j < pages.length; j++)
                if (want !== "" && pages[j].name.toLowerCase().indexOf(want) === 0) current = j
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
                    color: "#303036"
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
                        Layout.topMargin: index === 4 ? 14 : 0
                        visible: win.query === "" || modelData.name.toLowerCase().indexOf(win.query) >= 0
                        implicitHeight: 40
                        radius: 9
                        color: on ? Theme.accent : hover.containsMouse ? "#2f2f35" : "transparent"
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            spacing: 11
                            Rectangle {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26
                                radius: 7
                                gradient: Gradient {
                                    GradientStop { position: 0; color: Qt.lighter(item.modelData.color, 1.18) }
                                    GradientStop { position: 1; color: item.modelData.color }
                                }
                                Image {
                                    anchors.centerIn: parent
                                    width: 16
                                    height: 16
                                    source: "icons/" + item.modelData.icon + ".svg"
                                    sourceSize.width: 32
                                    sourceSize.height: 32
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: item.modelData.name
                                color: item.on ? "#ffffff" : Theme.text
                                font.family: Theme.sans
                                font.pixelSize: 14
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
