import QtQuick
import QtQuick.Layouts

ColumnLayout {
    spacing: 10

    SectionTitle { text: "DESKTOP LAYOUT" }
    RowLayout {
        Layout.fillWidth: true
        spacing: 14
        Repeater {
            model: [
                { id: "macos", name: "macOS", sub: "Menu bar and floating dock" },
                { id: "windows", name: "Windows 11", sub: "Centered taskbar" },
                { id: "linux", name: "Linux", sub: "Top bar and bottom panel" }
            ]
            delegate: Rectangle {
                id: opt
                required property var modelData
                readonly property bool on: Sys.layout === modelData.id
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 250
                radius: 14
                color: Theme.card
                border.width: on ? 2 : 1
                border.color: on ? Theme.accent : Theme.line
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10
                    LayoutPreview {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        kind: opt.modelData.id
                    }
                    ColumnLayout {
                        spacing: 1
                        Text { Layout.fillWidth: true; text: opt.modelData.name; color: Theme.text; font.family: Theme.sans; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Text { Layout.fillWidth: true; text: opt.modelData.sub; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 12 }
                    }
                }
                Rectangle {
                    visible: opt.on
                    width: 22
                    height: 22
                    radius: 11
                    color: Theme.accent
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 18
                    Text { anchors.centerIn: parent; text: "✓"; color: "#ffffff"; font.pixelSize: 13; font.weight: Font.Bold }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Sys.setLayout(opt.modelData.id) }
            }
        }
    }

    SectionTitle { text: "COLOR" }
    Card {
        Cell {
            title: "Accent color"
            subtitle: "Used for buttons, selection and focus rings"
            last: true
            Row {
                spacing: 9
                Repeater {
                    model: Sys.accents
                    delegate: Rectangle {
                        required property var modelData
                        width: 24
                        height: 24
                        radius: 12
                        color: modelData.hex
                        border.width: Sys.accentName === modelData.name ? 2 : 0
                        border.color: "#ffffff"
                        Rectangle {
                            visible: Sys.accentName === modelData.name
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: 4
                            color: "#ffffff"
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Sys.setAccent(modelData) }
                    }
                }
            }
        }
    }

    Card {
        Cell {
            title: "Appearance"
            subtitle: "Every KwickOS layout is dark"
            last: true
            Rectangle {
                implicitWidth: 74
                implicitHeight: 26
                radius: 13
                color: "#2f2f36"
                border.width: 1
                border.color: Theme.lineStrong
                Text { anchors.centerIn: parent; text: "Dark"; color: Theme.text; font.family: Theme.sans; font.pixelSize: 13 }
            }
        }
    }
}
