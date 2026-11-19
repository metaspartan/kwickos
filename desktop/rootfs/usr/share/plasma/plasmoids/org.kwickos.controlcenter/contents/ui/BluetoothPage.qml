import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "file:///usr/share/kwick/qml/menu"

ColumnLayout {
    id: page

    property var bt: null

    signal back()
    signal openSettings()

    spacing: 0

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 10
        Layout.bottomMargin: 4
        spacing: 6

        MouseArea {
            implicitWidth: 22
            implicitHeight: 22
            cursorShape: Qt.PointingHandCursor
            onClicked: page.back()

            Kirigami.Icon {
                anchors.centerIn: parent
                width: 16
                height: 16
                source: "go-previous-symbolic"
            }
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: "Bluetooth"
            font.weight: Font.Bold
        }

        MacSwitch {
            visible: !!page.bt && page.bt.available
            checked: !!page.bt && page.bt.on
            onToggled: on => page.bt.setOn(on)
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 10
        Layout.rightMargin: 10
        Layout.bottomMargin: 5
        implicitHeight: 1
        color: Kirigami.Theme.textColor
        opacity: 0.12
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        Layout.leftMargin: 10
        Layout.topMargin: 2
        Layout.bottomMargin: 4
        visible: !!page.bt && page.bt.available && page.bt.on
        text: "Devices"
        font: Kirigami.Theme.smallFont
        opacity: 0.55
    }

    Repeater {
        model: page.bt && page.bt.on ? page.bt.devices : []
        delegate: MouseArea {
            id: row

            required property var modelData

            Layout.fillWidth: true
            implicitHeight: Math.round(Kirigami.Units.gridUnit * 2.1)
            hoverEnabled: true
            onClicked: page.bt.toggle(modelData)

            Rectangle {
                anchors.fill: parent
                radius: 6
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                visible: row.containsMouse
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 10
                spacing: 9

                Glyph {
                    size: 26
                    on: row.modelData.connected
                    icon: row.modelData.icon + "-symbolic"
                    onClicked: page.bt.toggle(row.modelData)
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: row.modelData.name
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: (row.modelData.connected ? "Connected" : "Not Connected")
                              + (row.modelData.battery >= 0 ? " · " + row.modelData.battery + "%" : "")
                        font: Kirigami.Theme.smallFont
                        opacity: 0.6
                        textFormat: Text.PlainText
                    }
                }
            }
        }
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        Layout.margins: 10
        visible: !page.bt || !page.bt.available || !page.bt.on || page.bt.devices.length === 0
        text: !page.bt || !page.bt.available ? "No Bluetooth Adapter" : !page.bt.on ? "Bluetooth Is Off" : "No Paired Devices"
        opacity: 0.55
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 10
        Layout.rightMargin: 10
        Layout.topMargin: 5
        Layout.bottomMargin: 5
        implicitHeight: 1
        color: Kirigami.Theme.textColor
        opacity: 0.12
    }

    MenuRow {
        text: "Bluetooth Settings…"
        onClicked: page.openSettings()
    }
}
