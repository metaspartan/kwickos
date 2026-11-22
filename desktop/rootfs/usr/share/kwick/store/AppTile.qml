import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

Item {
    id: t
    property var app
    property bool separator: true
    implicitHeight: Look.mac ? 84 : Look.win ? 236 : 96

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: t.ApplicationWindow.window.openApp(t.app)
    }

    Item {
        visible: Look.mac
        anchors.fill: parent
        RowLayout {
            anchors.fill: parent
            anchors.bottomMargin: 1
            spacing: 12
            AppIcon {
                Layout.preferredWidth: 60
                Layout.preferredHeight: 60
                size: 60
                source: t.app ? t.app.icon || "" : ""
                name: t.app ? t.app.name || "" : ""
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { Layout.fillWidth: true; text: t.app ? t.app.name : ""; color: Look.text; font.family: Look.sans; font.pixelSize: 14; font.weight: Font.Medium; elide: Text.ElideRight }
                Text { Layout.fillWidth: true; text: t.app ? t.app.summary || "" : ""; color: Look.sub; font.family: Look.sans; font.pixelSize: 12; elide: Text.ElideRight; maximumLineCount: 1 }
                Item { implicitHeight: 4 }
                GetButton { app: t.app }
            }
        }
        Rectangle {
            visible: t.separator
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.leftMargin: 72
            anchors.right: parent.right
            height: 1
            color: Look.line
        }
    }

    Rectangle {
        visible: Look.win
        anchors.fill: parent
        radius: 8
        color: area.containsMouse ? Look.cardHover : Look.card
        border.width: 1
        border.color: Look.cardStroke
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 6
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 108
                radius: 6
                color: Look.light ? "#f3f3f3" : "#262626"
                AppIcon {
                    anchors.centerIn: parent
                    size: 72
                    source: t.app ? t.app.icon || "" : ""
                    name: t.app ? t.app.name || "" : ""
                }
            }
            Text { Layout.fillWidth: true; Layout.topMargin: 4; text: t.app ? t.app.name : ""; color: Look.text; font.family: Look.sans; font.pixelSize: 14; font.weight: Font.DemiBold; elide: Text.ElideRight }
            Text { Layout.fillWidth: true; text: t.app ? t.app.summary || "" : ""; color: Look.sub; font.family: Look.sans; font.pixelSize: 12; elide: Text.ElideRight; wrapMode: Text.WordWrap; maximumLineCount: 2; lineHeight: 1.1 }
            Item { Layout.fillHeight: true }
            RowLayout {
                Layout.fillWidth: true
                Repeater {
                    model: t.app ? (t.app.srcs || [t.app.src]).slice(0, 2) : []
                    delegate: Badge { required property var modelData; src: modelData }
                }
                Item { Layout.fillWidth: true }
                Text { text: Store.isInstalled(t.app) ? "Installed" : "Free"; color: Look.sub; font.family: Look.sans; font.pixelSize: 12 }
            }
        }
    }

    Rectangle {
        visible: Look.gnu
        anchors.fill: parent
        radius: 12
        color: area.containsMouse ? Look.cardHover : Look.card
        border.width: 1
        border.color: Look.cardStroke
        RowLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 14
            AppIcon {
                Layout.preferredWidth: 64
                Layout.preferredHeight: 64
                size: 64
                source: t.app ? t.app.icon || "" : ""
                name: t.app ? t.app.name || "" : ""
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                Text { Layout.fillWidth: true; text: t.app ? t.app.name : ""; color: Look.text; font.family: Look.sans; font.pixelSize: 14; font.weight: Font.Bold; elide: Text.ElideRight }
                Text { Layout.fillWidth: true; text: t.app ? t.app.summary || "" : ""; color: Look.sub; font.family: Look.sans; font.pixelSize: 13; elide: Text.ElideRight; wrapMode: Text.WordWrap; maximumLineCount: 2 }
            }
        }
        Rectangle {
            visible: Store.isInstalled(t.app)
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 10
            width: 20
            height: 20
            radius: 10
            color: Look.accent
            Glyph { anchors.centerIn: parent; name: "check"; size: 13; stroke: 2.2; color: "#ffffff" }
        }
    }
}
