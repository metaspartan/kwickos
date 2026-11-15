import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

import org.kde.notificationmanager as NotificationManager

import "../components" as Components

BaseDelegate {
    id: delegateRoot

    Layout.preferredWidth: 320

    body: null
    icon: image
    footer: footerLoader.item
    columns: 3
    columnSpacing: 10
    rowSpacing: 1

    Accessible.role: Accessible.Notification

    readonly property bool critical: modelInterface.urgency === NotificationManager.Notifications.CriticalUrgency
    readonly property string title: modelInterface.summary.length > 0 ? modelInterface.summary : modelInterface.applicationName
    readonly property color secondary: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.6)
    property date now: new Date()

    function stamp(t) {
        if (!t) {
            return "now";
        }
        const minutes = Math.floor((now - t) / 60000);
        if (minutes < 1) {
            return "now";
        }
        if (minutes < 60) {
            return minutes + "m ago";
        }
        return Qt.formatTime(t, "h:mm AP");
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: delegateRoot.now = new Date()
    }

    HoverHandler {
        id: hover
    }

    Kirigami.Icon {
        Layout.row: 0
        Layout.column: 0
        Layout.rowSpan: 2
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: 32
        Layout.preferredHeight: 32
        source: delegateRoot.modelInterface.applicationIconSource || (delegateRoot.critical ? "dialog-warning" : "dialog-information")
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
            text: delegateRoot.stamp(delegateRoot.modelInterface.time)
            color: delegateRoot.secondary
            font.pointSize: Kirigami.Theme.smallFont.pointSize
        }
    }

    PlasmaComponents3.Label {
        Layout.row: 1
        Layout.column: 1
        Layout.fillWidth: true
        visible: delegateRoot.hasBodyText
        text: delegateRoot.modelInterface.body
        textFormat: Text.StyledText
        color: delegateRoot.secondary
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        onLinkActivated: link => Qt.openUrlExternally(link)
    }

    Components.Icon {
        id: image
        Layout.row: 0
        Layout.column: 2
        Layout.rowSpan: 2
        Layout.alignment: Qt.AlignVCenter
        Layout.maximumWidth: 40
        Layout.maximumHeight: 40
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

    Rectangle {
        id: closeButton
        parent: delegateRoot.parent
        visible: delegateRoot.modelInterface.closable && (hover.hovered || closeArea.containsMouse)
        width: 18
        height: 18
        radius: 9
        x: 4
        y: 4
        z: 10
        color: closeArea.pressed ? "#3a3a3c" : "#48484a"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.14)

        Kirigami.Icon {
            anchors.centerIn: parent
            width: 9
            height: 9
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
