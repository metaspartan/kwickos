import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.notificationmanager as NotificationManager
import org.kde.kirigami as Kirigami
import "file:///usr/share/kwick/qml/fluent"

PlasmoidItem {
    id: root

    property date now: new Date()
    readonly property bool use24h: Plasmoid.configuration.use24h
    readonly property bool quiet: {
        const until = settings.notificationsInhibitedUntil
        return (!isNaN(until.getTime()) && until.getTime() > now.getTime()) || settings.notificationsInhibitedByApplication
    }

    function setQuiet(minutes) {
        if (minutes > 0) {
            settings.notificationsInhibitedUntil = new Date(Date.now() + minutes * 60000)
        } else {
            settings.notificationsInhibitedUntil = undefined
            settings.revokeApplicationInhibitions()
        }
        settings.save()
        now = new Date()
    }

    preferredRepresentation: compactRepresentation
    fullRepresentation: Item {}
    Plasmoid.icon: "preferences-system-time"
    Plasmoid.title: "Clock and Notifications"
    toolTipMainText: flyout.visible ? "" : Qt.formatDate(now, "dddd, MMMM d, yyyy")
    toolTipSubText: history.unreadNotificationsCount > 0 ? history.unreadNotificationsCount + " new notifications" : ""

    P5Support.DataSource {
        engine: "time"
        connectedSources: ["Local"]
        interval: 60000
        intervalAlignment: P5Support.Types.AlignToMinute
        onNewData: root.now = new Date()
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: source => disconnectSource(source)
    }

    NotificationManager.Settings {
        id: settings
    }

    NotificationManager.Notifications {
        id: history
        showExpired: true
        showDismissed: true
        showJobs: false
        sortMode: NotificationManager.Notifications.SortByDate
        groupMode: NotificationManager.Notifications.GroupDisabled
        urgencies: NotificationManager.Notifications.CriticalUrgency | NotificationManager.Notifications.NormalUrgency
    }

    compactRepresentation: RowLayout {
        spacing: 0
        Layout.minimumWidth: implicitWidth
        Layout.maximumWidth: implicitWidth
        Layout.fillHeight: true
        Component.onCompleted: flyout.anchorItem = this

        TaskbarButton {
            open: flyout.visible
            onClicked: flyout.toggle()

            Column {
                Layout.rightMargin: 8

                FluentText {
                    anchors.right: parent.right
                    text: Qt.formatTime(root.now, root.use24h ? "H:mm" : "h:mm AP")
                    font.pixelSize: Fluent.caption
                }

                FluentText {
                    anchors.right: parent.right
                    text: Qt.formatDate(root.now, "M/d/yyyy")
                    font.pixelSize: Fluent.caption
                }
            }

            Kirigami.Icon {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                source: root.quiet ? "notifications-disabled-symbolic" : history.unreadNotificationsCount > 0 ? "notification-active-symbolic" : "notifications-symbolic"
                isMask: true
                color: Fluent.text
            }
        }

        MouseArea {
            id: peek
            Layout.fillHeight: true
            Layout.preferredWidth: 12
            hoverEnabled: true
            onClicked: exec.connectSource("qdbus6 org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut 'Show Desktop'")

            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 5
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 16
                color: Fluent.text3
                visible: peek.containsMouse
            }
        }
    }

    Flyout {
        id: flyout
        onVisibleChanged: if (visible) center.reset()
        mainItem: CenterPanel {
            id: center
            nc: root
            history: history
        }
    }
}
