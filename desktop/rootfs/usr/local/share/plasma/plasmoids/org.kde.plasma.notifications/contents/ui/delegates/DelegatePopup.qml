import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrolsaddons as KQuickControlsAddons

import org.kde.notificationmanager as NotificationManager
import org.kde.plasma.private.notifications as Notifications

import "../components" as Components

BaseDelegate {
    id: delegateRoot

    Layout.preferredWidth: Math.max(footerLoader.item?.implicitWidth ?? 0, Kirigami.Units.gridUnit * 19)

    body: bodyLabel
    icon: image
    footer: footerLoader.item
    columns: 3
    columnSpacing: 11
    rowSpacing: 1

    Accessible.role: Accessible.Notification

    readonly property bool critical: modelInterface.urgency === NotificationManager.Notifications.CriticalUrgency
    readonly property string title: modelInterface.summary.length > 0 ? modelInterface.summary : modelInterface.applicationName

    HoverHandler {
        id: hover
    }

    Item {
        Layout.row: 0
        Layout.column: 0
        Layout.rowSpan: 2
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: 1
        Layout.preferredWidth: 34
        Layout.preferredHeight: 34

        Kirigami.Icon {
            anchors.fill: parent
            source: delegateRoot.modelInterface.applicationIconSource || (delegateRoot.critical ? "dialog-warning" : "dialog-information")
        }

        Rectangle {
            id: closeButton
            visible: delegateRoot.modelInterface.closable && (hover.hovered || closeArea.containsMouse)
            width: 20
            height: 20
            radius: 10
            x: -13
            y: -13
            color: closeArea.pressed ? "#4a4a4a" : "#5a5a5a"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.16)

            Kirigami.Icon {
                anchors.centerIn: parent
                width: 10
                height: 10
                source: "window-close-symbolic"
                color: "#ffffff"
                isMask: true
            }

            MouseArea {
                id: closeArea
                anchors.fill: parent
                anchors.margins: -3
                hoverEnabled: true
                onClicked: delegateRoot.modelInterface.closeClicked()
            }
        }
    }

    RowLayout {
        Layout.row: 0
        Layout.column: 1
        Layout.fillWidth: true
        spacing: 6

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: delegateRoot.title
            textFormat: Text.PlainText
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        PlasmaComponents3.Label {
            text: "now"
            opacity: 0.55
            font.pointSize: Kirigami.Theme.smallFont.pointSize
        }
    }

    KQuickControlsAddons.MouseEventListener {
        Layout.row: 1
        Layout.column: 1
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.maximumHeight: Kirigami.Units.gridUnit * Math.max(2, delegateRoot.modelInterface.maximumLineCount)
        implicitWidth: -1
        implicitHeight: scroll.implicitHeight
        visible: delegateRoot.hasBodyText
        opacity: 0.66
        onClicked: {
            if (delegateRoot.modelInterface.hasDefaultAction) {
                delegateRoot.modelInterface.defaultActionInvoked();
            }
        }

        PlasmaComponents3.ScrollView {
            id: scroll
            anchors.fill: parent
            PlasmaComponents3.ScrollBar.vertical.visible: delegateRoot.modelInterface.maximumLineCount > 0 && bodyLabel.implicitHeight > parent.Layout.maximumHeight
            PlasmaComponents3.ScrollBar.horizontal.visible: false

            Components.Body {
                id: bodyLabel
                width: scroll.contentItem.width
                modelInterface: delegateRoot.modelInterface
                Accessible.ignored: true
            }
        }
    }

    Components.Icon {
        id: image
        Layout.row: 0
        Layout.column: 2
        Layout.rowSpan: 2
        Layout.alignment: Qt.AlignVCenter
        modelInterface: delegateRoot.modelInterface
    }

    Components.FooterLoader {
        id: footerLoader
        Layout.fillWidth: true
        Layout.row: 2
        Layout.column: 1
        Layout.columnSpan: 2
        Layout.topMargin: item ? 6 : 0
        modelInterface: delegateRoot.modelInterface
        iconContainerItem: image
    }

    TapHandler {
        enabled: delegateRoot.modelInterface.hasDefaultAction && !delegateRoot.hasBodyText
        onTapped: delegateRoot.modelInterface.defaultActionInvoked()
    }
}
