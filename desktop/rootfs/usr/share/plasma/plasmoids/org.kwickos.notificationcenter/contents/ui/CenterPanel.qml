import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.notificationmanager as NotificationManager
import org.kde.kirigami as Kirigami
import "file:///usr/share/kwick/qml/fluent"

FocusScope {
    id: panel

    required property var nc
    required property var history
    property bool collapsed: false
    property int focusMinutes: Plasmoid.configuration.focusMinutes

    function reset() {
        calendar.month = new Date(nc.now.getFullYear(), nc.now.getMonth(), 1)
        forceActiveFocus()
    }

    width: 360
    height: column.implicitHeight
    Keys.onEscapePressed: Window.window.visible = false

    ColumnLayout {
        id: column
        width: parent.width
        spacing: 0

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 52

            FluentText {
                x: 20
                anchors.verticalCenter: parent.verticalCenter
                text: "Notifications"
                strong: true
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                MouseArea {
                    id: clear
                    visible: panel.history.count > 0
                    width: clearLabel.implicitWidth + 20
                    height: 32
                    hoverEnabled: true
                    onClicked: panel.history.clear(NotificationManager.Notifications.ClearExpired)

                    Subtle {
                        anchors.fill: parent
                        hovered: clear.containsMouse
                        pressed: clear.pressed
                    }

                    FluentText {
                        id: clearLabel
                        anchors.centerIn: parent
                        text: "Clear all"
                        font.pixelSize: Fluent.caption
                    }
                }

                IconButton {
                    icon: panel.nc.quiet ? "notifications-disabled-symbolic" : "notifications-symbolic"
                    checked: panel.nc.quiet
                    onClicked: panel.nc.setQuiet(panel.nc.quiet ? 0 : 60 * 24 * 365)
                }
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(list.implicitHeight, 360)
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            contentHeight: list.implicitHeight
            clip: true
            visible: panel.history.count > 0
            boundsBehavior: Flickable.StopAtBounds
            QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

            Column {
                id: list
                width: parent.width
                spacing: 8

                Repeater {
                    model: panel.history

                    delegate: Toast {
                        required property int index
                        required property var model
                        width: list.width
                        appName: model.applicationName || ""
                        appIcon: model.applicationIconName || ""
                        summary: model.summary || ""
                        body: model.body || ""
                        image: model.image || model.iconName || ""
                        time: model.updated || model.created
                        now: panel.nc.now
                        onActivated: panel.history.invokeDefaultAction(panel.history.index(index, 0))
                        onDismissed: panel.history.close(panel.history.index(index, 0))
                    }
                }
            }
        }

        FluentText {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            visible: panel.history.count === 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: "No new notifications"
            level: 1
        }

        Item {
            Layout.preferredHeight: 12
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Fluent.divider
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 48

            FluentText {
                x: 20
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(panel.nc.now, "dddd, MMMM d")
                strong: true
            }

            IconButton {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                icon: panel.collapsed ? "arrow-up" : "arrow-down"
                iconSize: 12
                onClicked: panel.collapsed = !panel.collapsed
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Fluent.divider
            visible: !panel.collapsed
        }

        MonthGrid {
            id: calendar
            Layout.fillWidth: true
            visible: !panel.collapsed
            today: panel.nc.now
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            color: Fluent.footer
            radius: Fluent.overlayRadius - 1

            Rectangle {
                width: parent.width
                height: parent.radius
                color: parent.color
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Fluent.divider
            }

            Row {
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                visible: !panel.nc.quiet

                IconButton {
                    icon: "list-remove-symbolic"
                    enabled: panel.focusMinutes > 5
                    onClicked: Plasmoid.configuration.focusMinutes = panel.focusMinutes - (panel.focusMinutes > 30 ? 15 : 5)
                }

                FluentText {
                    width: 64
                    height: 32
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: panel.focusMinutes + " mins"
                }

                IconButton {
                    icon: "list-add-symbolic"
                    enabled: panel.focusMinutes < 240
                    onClicked: Plasmoid.configuration.focusMinutes = panel.focusMinutes + (panel.focusMinutes >= 30 ? 15 : 5)
                }
            }

            FluentText {
                x: 20
                anchors.verticalCenter: parent.verticalCenter
                visible: panel.nc.quiet
                text: "Focus session in progress"
            }

            MouseArea {
                id: start
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: startRow.implicitWidth + 24
                height: 32
                hoverEnabled: true
                onClicked: panel.nc.setQuiet(panel.nc.quiet ? 0 : panel.focusMinutes)

                Rectangle {
                    anchors.fill: parent
                    radius: Fluent.radius
                    color: start.pressed ? Fluent.controlPressed : start.containsMouse ? Fluent.controlHover : Fluent.control
                    border.width: 1
                    border.color: Fluent.controlStroke
                }

                Row {
                    id: startRow
                    anchors.centerIn: parent
                    spacing: 8

                    Kirigami.Icon {
                        width: 16
                        height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        source: panel.nc.quiet ? "media-playback-stop-symbolic" : "media-playback-start-symbolic"
                        isMask: true
                        color: Fluent.text
                    }

                    FluentText {
                        text: panel.nc.quiet ? "End session" : "Focus"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }
}
