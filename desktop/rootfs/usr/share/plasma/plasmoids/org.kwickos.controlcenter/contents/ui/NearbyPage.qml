import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "file:///usr/share/kwick/qml/menu"

ColumnLayout {
    id: page

    property var nearby: null

    signal back()
    signal openSettings()
    signal share()

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
            text: "Nearby Share"
            font.weight: Font.Bold
        }

        MacSwitch {
            visible: !!page.nearby && page.nearby.available
            checked: !!page.nearby && page.nearby.on
            onToggled: on => page.nearby.setMode(on ? "everyone" : "off")
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

    Repeater {
        model: [
            { id: "off", label: "Receiving Off", hint: "You can still send" },
            { id: "contacts", label: "Known Devices Only", hint: "Devices you accepted before" },
            { id: "everyone", label: "Everyone for 10 Minutes", hint: "Any nearby device can ask" }
        ]
        delegate: MouseArea {
            id: row

            required property var modelData
            readonly property bool current: !!page.nearby && page.nearby.mode === modelData.id

            Layout.fillWidth: true
            implicitHeight: Math.round(Kirigami.Units.gridUnit * 2.2)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: page.nearby.setMode(modelData.id)

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
                    on: row.current
                    icon: row.modelData.id === "off" ? "action-unavailable-symbolic" : row.modelData.id === "contacts" ? "system-users-symbolic" : "kwick-nearby-symbolic"
                    onClicked: page.nearby.setMode(row.modelData.id)
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: row.modelData.label
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: row.modelData.id === "everyone" && row.current ? page.nearby.minutesLeft + " minutes left" : row.modelData.hint
                        font: Kirigami.Theme.smallFont
                        opacity: 0.6
                        textFormat: Text.PlainText
                    }
                }
            }
        }
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
        text: "Share Files Nearby…"
        onClicked: page.share()
    }

    MenuRow {
        text: "Nearby Share Settings…"
        onClicked: page.openSettings()
    }
}
