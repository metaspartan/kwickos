import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

Popup {
    id: dlg
    property string title
    property string body
    property string confirmText: "OK"
    property string cancelText: "Cancel"
    property bool danger: false
    property bool confirmEnabled: true
    property var app: null
    default property alias extra: slot.data
    signal confirmed()

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: 440
    modal: true
    focus: true
    padding: 0
    closePolicy: Popup.CloseOnEscape
    Overlay.modal: Rectangle { color: Look.win ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(0, 0, 0, Look.light ? 0.2 : 0.45) }
    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 } NumberAnimation { property: "scale"; from: Look.win ? 1.05 : 0.96; to: 1; duration: 170; easing.type: Easing.OutCubic } }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 110 } }

    background: Rectangle {
        radius: Look.mac ? 14 : Look.win ? 8 : 18
        color: Look.popup
        border.width: 1
        border.color: Look.mac ? (Look.light ? Qt.rgba(0, 0, 0, 0.12) : Qt.rgba(1, 1, 1, 0.12)) : Look.win ? (Look.light ? Qt.rgba(0, 0, 0, 0.1) : Qt.rgba(1, 1, 1, 0.08)) : Look.cardStroke
    }

    contentItem: ColumnLayout {
        spacing: 0

        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: Look.win ? 24 : 22
            Layout.bottomMargin: Look.win ? 24 : 16
            spacing: Look.win ? 12 : 8

            AppIcon {
                visible: !!dlg.app && !Look.win
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 64
                Layout.preferredHeight: 64
                size: 64
                source: dlg.app ? dlg.app.icon || "" : ""
                name: dlg.app ? dlg.app.name || "" : ""
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Look.win ? Text.AlignLeft : Text.AlignHCenter
                text: dlg.title
                color: Look.text
                font.family: Look.display
                font.pixelSize: Look.win ? 20 : Look.gnu ? 18 : 14
                font.weight: Look.win ? Font.DemiBold : Font.Bold
                wrapMode: Text.WordWrap
            }
            Text {
                visible: dlg.body !== ""
                Layout.fillWidth: true
                horizontalAlignment: Look.win ? Text.AlignLeft : Text.AlignHCenter
                text: dlg.body
                color: Look.win ? Look.text : Look.sub
                font.family: Look.sans
                font.pixelSize: Look.win ? 14 : 12
                lineHeight: 1.2
                wrapMode: Text.WordWrap
            }
            ColumnLayout {
                id: slot
                Layout.fillWidth: true
                spacing: 8
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: Look.win
            implicitHeight: 80
            color: Look.light ? "#f3f3f3" : "#202020"
            radius: 8
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 10; color: parent.color }
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 1; color: Look.line }
            RowLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 8
                Btn { Layout.fillWidth: true; Layout.preferredWidth: 1; text: dlg.confirmText; primary: true; enabled: dlg.confirmEnabled; onClicked: { dlg.close(); dlg.confirmed() } }
                Btn { visible: dlg.cancelText !== ""; Layout.fillWidth: true; Layout.preferredWidth: 1; text: dlg.cancelText; onClicked: dlg.close() }
            }
        }

        RowLayout {
            visible: Look.mac
            Layout.fillWidth: true
            Layout.leftMargin: 18
            Layout.rightMargin: 18
            Layout.bottomMargin: 18
            spacing: 8
            Rectangle {
                visible: dlg.cancelText !== ""
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 28
                radius: 7
                color: ca.pressed ? Look.pressed : Look.light ? "#e3e3e6" : "#4a4a4d"
                Text { anchors.centerIn: parent; text: dlg.cancelText; color: Look.text; font.family: Look.sans; font.pixelSize: 13; font.weight: Font.Medium }
                MouseArea { id: ca; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dlg.close() }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 28
                radius: 7
                opacity: dlg.confirmEnabled ? 1 : 0.45
                color: dlg.danger ? (oa.pressed ? Qt.darker(Look.bad, 1.1) : Look.bad) : (oa.pressed ? Qt.darker(Look.accent, 1.1) : Look.accent)
                Text { anchors.centerIn: parent; text: dlg.confirmText; color: "#ffffff"; font.family: Look.sans; font.pixelSize: 13; font.weight: Font.Medium }
                MouseArea { id: oa; anchors.fill: parent; enabled: dlg.confirmEnabled; cursorShape: Qt.PointingHandCursor; onClicked: { dlg.close(); dlg.confirmed() } }
            }
        }

        ColumnLayout {
            visible: Look.gnu
            Layout.fillWidth: true
            Layout.leftMargin: 22
            Layout.rightMargin: 22
            Layout.bottomMargin: 22
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Rectangle {
                    visible: dlg.cancelText !== ""
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: 40
                    radius: 20
                    color: ga.pressed ? Look.pressed : Look.openBg
                    Text { anchors.centerIn: parent; text: dlg.cancelText; color: Look.text; font.family: Look.sans; font.pixelSize: 14; font.weight: Font.Bold }
                    MouseArea { id: ga; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: dlg.close() }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: 40
                    radius: 20
                    opacity: dlg.confirmEnabled ? 1 : 0.45
                    color: dlg.danger ? (gb.pressed ? Qt.darker("#e01b24", 1.1) : "#e01b24") : (gb.pressed ? Qt.darker(Look.accent, 1.1) : Look.accent)
                    Text { anchors.centerIn: parent; text: dlg.confirmText; color: "#ffffff"; font.family: Look.sans; font.pixelSize: 14; font.weight: Font.Bold }
                    MouseArea { id: gb; anchors.fill: parent; enabled: dlg.confirmEnabled; cursorShape: Qt.PointingHandCursor; onClicked: { dlg.close(); dlg.confirmed() } }
                }
            }
        }
    }
}
