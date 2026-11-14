import QtQuick
import QtQuick.Layouts

PageFrame {
    id: p
    icon: "icons/look.svg"
    title: "Choose Your Look"
    subtitle: "Pick the desktop layout that feels like home. You can switch at any time in KwickOS Settings."
    maxWidth: 780
    firstFocus: cards

    readonly property var options: [
        { id: "macos", name: "macOS", sub: "Menu bar and floating dock" },
        { id: "windows", name: "Windows 11", sub: "Centered taskbar" },
        { id: "linux", name: "Linux", sub: "Top bar and bottom panel" }
    ]

    function idx() {
        for (var i = 0; i < options.length; i++) if (options[i].id === Inst.layout) return i
        return 0
    }

    FocusScope {
        id: cards
        Layout.fillWidth: true
        Layout.topMargin: 6
        implicitHeight: row.implicitHeight
        activeFocusOnTab: true
        Keys.onLeftPressed: Inst.layout = p.options[Math.max(0, p.idx() - 1)].id
        Keys.onRightPressed: Inst.layout = p.options[Math.min(p.options.length - 1, p.idx() + 1)].id

        RowLayout {
            id: row
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 18

            Repeater {
                model: p.options
                delegate: Item {
                    id: opt
                    required property var modelData
                    readonly property bool on: Inst.layout === modelData.id
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: col.implicitHeight

                    ColumnLayout {
                        id: col
                        width: parent.width
                        spacing: 14

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: width * 0.64

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -5
                                radius: 17
                                color: "transparent"
                                border.width: 3
                                border.color: opt.on ? Theme.accent : "transparent"
                                Behavior on border.color { ColorAnimation { duration: 160 } }
                            }
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -9
                                radius: 20
                                color: "transparent"
                                border.width: 3
                                border.color: Theme.focusRing
                                visible: opt.on && cards.activeFocus
                            }
                            LayoutPreview {
                                anchors.fill: parent
                                radius: 12
                                kind: opt.modelData.id
                                scale: ma.pressed ? 0.98 : 1
                                Behavior on scale { NumberAnimation { duration: 120 } }
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            spacing: 3
                            Text {
                                width: parent.width
                                text: opt.modelData.name
                                color: Theme.text
                                font.family: Theme.sans
                                font.pixelSize: 15
                                font.weight: opt.on ? Font.DemiBold : Font.Medium
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Text {
                                width: parent.width
                                text: opt.modelData.sub
                                color: Theme.sub
                                font.family: Theme.sans
                                font.pixelSize: 13
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: 20
                            height: 20
                            radius: 10
                            color: opt.on ? Theme.accent : "transparent"
                            border.width: opt.on ? 0 : 1.5
                            border.color: Theme.faint
                            Chevron {
                                anchors.centerIn: parent
                                width: 10
                                height: 9
                                shape: "check"
                                stroke: 2
                                color: "#ffffff"
                                visible: opt.on
                            }
                        }
                    }

                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { Inst.layout = opt.modelData.id; cards.forceActiveFocus() }
                        onDoubleClicked: Inst.navNext()
                    }
                }
            }
        }
    }
}
