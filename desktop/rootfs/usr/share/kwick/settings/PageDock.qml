import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

ColumnLayout {
    id: page
    spacing: 10

    Rectangle {
        visible: !Sys.dockAvailable
        Layout.fillWidth: true
        implicitHeight: nrow.implicitHeight + 28
        radius: 12
        color: "#2e2412"
        border.width: 1
        border.color: "#55ff9f0a"
        RowLayout {
            id: nrow
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12
            Rectangle { width: 8; height: 8; radius: 4; color: Theme.warn }
            Text {
                Layout.fillWidth: true
                text: "The kwick-dock tool is not installed yet. Changes here are shown but not applied."
                color: "#f5d9a8"
                font.family: Theme.sans
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }
        }
    }

    SectionTitle { text: "POSITION ON SCREEN" }
    RowLayout {
        Layout.fillWidth: true
        spacing: 14
        Repeater {
            model: [{ id: "left", name: "Left" }, { id: "bottom", name: "Bottom" }, { id: "right", name: "Right" }]
            delegate: Rectangle {
                id: pos
                required property var modelData
                readonly property bool on: Sys.dockPosition === modelData.id
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 150
                radius: 14
                color: Theme.card
                border.width: on ? 2 : 1
                border.color: on ? Theme.accent : Theme.line
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    Rectangle {
                        id: scr
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 8
                        clip: true
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "#1a1440" }
                            GradientStop { position: 0.55; color: "#2b1d6b" }
                            GradientStop { position: 1; color: "#0f6b78" }
                        }
                        Rectangle {
                            x: parent.width * 0.26
                            y: parent.height * 0.18
                            width: parent.width * 0.46
                            height: parent.height * 0.46
                            radius: 4
                            color: "#2c2c32"
                            border.width: 1
                            border.color: "#26ffffff"
                        }
                        Rectangle {
                            readonly property bool vert: pos.modelData.id !== "bottom"
                            width: vert ? 12 : parent.width * 0.5
                            height: vert ? parent.height * 0.6 : 12
                            radius: 6
                            color: "#66ffffff"
                            border.width: 1
                            border.color: "#40ffffff"
                            x: pos.modelData.id === "left" ? 5 : pos.modelData.id === "right" ? parent.width - width - 5 : (parent.width - width) / 2
                            y: vert ? (parent.height - height) / 2 : parent.height - height - 5
                            Grid {
                                anchors.centerIn: parent
                                columns: parent.vert ? 1 : 5
                                spacing: 3
                                Repeater { model: 5; Rectangle { width: 5; height: 5; radius: 1.5; color: "#d0ffffff" } }
                            }
                        }
                    }
                    Text { Layout.alignment: Qt.AlignHCenter; text: pos.modelData.name; color: pos.on ? Theme.text : Theme.sub; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.Medium }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Sys.setDockPosition(pos.modelData.id) }
            }
        }
    }

    SectionTitle { text: "DOCK" }
    Card {
        Cell {
            title: "Icon size"
            subtitle: Sys.dockSize + " px"
            Sld {
                implicitWidth: 240
                from: 32
                to: 96
                step: 4
                value: Sys.dockSize
                onValueChanged: if (pressed) Sys.dockSize = value
                onReleased: (v) => Sys.setDockSize(v)
            }
        }
        Cell {
            title: "Automatically hide the dock"
            subtitle: "The dock slides away until you move the pointer to its edge"
            last: !Sys.dockFloatingSupported
            Toggle { checked: Sys.dockAutohide; onToggled: (v) => Sys.setDockAutohide(v) }
        }
        Cell {
            visible: Sys.dockFloatingSupported
            title: "Floating dock"
            subtitle: "Keeps a gap between the dock and the screen edge"
            last: true
            Toggle { checked: Sys.dockFloating; onToggled: (v) => Sys.setDockFloating(v) }
        }
    }

    SectionTitle { text: "PINNED APPS" }
    Card {
        Repeater {
            model: Sys.pinned
            delegate: Item {
                id: prow
                required property string modelData
                required property int index
                readonly property var info: Sys.appInfo(modelData)
                Layout.fillWidth: true
                implicitHeight: 52
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 12
                    spacing: 12
                    AppIcon { name: prow.info.name; icon: prow.info.icon }
                    Text { Layout.fillWidth: true; text: prow.info.name; color: Theme.text; font.family: Theme.sans; font.pixelSize: 13; elide: Text.ElideRight }
                    Btn { text: "↑"; implicitWidth: 30; enabled: prow.index > 0; onClicked: Sys.movePinned(prow.index, -1) }
                    Btn { text: "↓"; implicitWidth: 30; enabled: prow.index < Sys.pinned.length - 1; onClicked: Sys.movePinned(prow.index, 1) }
                    Btn { text: "Remove"; danger: true; onClicked: Sys.unpin(prow.modelData) }
                }
                Rectangle {
                    height: 1
                    color: Theme.line
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                }
            }
        }
        Cell {
            visible: Sys.pinned.length === 0
            title: "No pinned apps"
            subtitle: "Add apps to keep them in the dock"
        }
        Cell {
            last: true
            title: "Add an app"
            subtitle: "Pick from the installed applications"
            Btn { text: "Add…"; primary: true; onClicked: picker.open() }
        }
    }

    Popup {
        id: picker
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        width: 460
        height: 520
        padding: 0
        onOpened: { search.text = ""; search.forceActiveFocus() }
        background: Rectangle { radius: 14; color: "#2a2a2f"; border.width: 1; border.color: Theme.lineStrong }
        Overlay.modal: Rectangle { color: "#99000000" }
        contentItem: ColumnLayout {
            spacing: 0
            Text { Layout.margins: 18; Layout.bottomMargin: 8; text: "Add to Dock"; color: Theme.text; font.family: Theme.sans; font.pixelSize: 16; font.weight: Font.DemiBold }
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                implicitHeight: 32
                radius: 8
                color: Theme.field
                TextInput {
                    id: search
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.text
                    font.family: Theme.sans
                    font.pixelSize: 13
                    selectionColor: Theme.accent
                    Text { visible: !search.text.length; anchors.verticalCenter: parent.verticalCenter; text: "Search apps"; color: Theme.sub; font: search.font }
                }
            }
            ListView {
                id: appList
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: 8
                clip: true
                model: Sys.apps.filter(function (a) { return Sys.pinned.indexOf(a.id) < 0 && a.name.toLowerCase().indexOf(search.text.toLowerCase()) >= 0 })
                ScrollBar.vertical: ScrollBar { }
                delegate: Item {
                    id: arow
                    required property var modelData
                    width: appList.width
                    height: 48
                    Rectangle { anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; radius: 8; color: ma.containsMouse ? "#38383f" : "transparent" }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        spacing: 12
                        AppIcon { name: arow.modelData.name; icon: arow.modelData.icon }
                        Text { Layout.fillWidth: true; text: arow.modelData.name; color: Theme.text; font.family: Theme.sans; font.pixelSize: 13; elide: Text.ElideRight }
                    }
                    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { Sys.pin(arow.modelData.id); picker.close() } }
                }
            }
            RowLayout {
                Layout.margins: 14
                Item { Layout.fillWidth: true }
                Btn { text: "Cancel"; onClicked: picker.close() }
            }
        }
    }
}
