import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

Popup {
    id: sheet
    property string title
    property string body
    property string confirmText: "OK"
    property string cancelText: "Cancel"
    property bool danger: false
    property string icon: "icons/app.svg"
    default property alias extra: slot.data
    signal confirmed()

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: 440
    modal: true
    focus: true
    padding: 22
    closePolicy: Popup.CloseOnEscape
    Overlay.modal: Rectangle { color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.6) }
    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 } NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 160; easing.type: Easing.OutCubic } }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 110 } }
    background: Rectangle {
        radius: 14
        color: Theme.cardHi
        border.width: 1
        border.color: Theme.lineStrong
    }

    contentItem: ColumnLayout {
        spacing: 10
        Image {
            visible: sheet.icon !== ""
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 56
            Layout.preferredHeight: 56
            source: sheet.icon
            sourceSize.width: 112
            sourceSize.height: 112
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: sheet.title
            color: Theme.text
            font.family: Theme.sans
            font.pixelSize: 14
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
        }
        Text {
            visible: sheet.body !== ""
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: sheet.body
            color: Theme.sub
            font.family: Theme.sans
            font.pixelSize: 12
            lineHeight: 1.2
            wrapMode: Text.WordWrap
        }
        ColumnLayout {
            id: slot
            Layout.fillWidth: true
            spacing: 0
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 8
            spacing: 8
            Btn {
                visible: sheet.cancelText !== ""
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                text: sheet.cancelText
                onClicked: sheet.close()
            }
            Btn {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                text: sheet.confirmText
                primary: !sheet.danger
                danger: sheet.danger
                onClicked: { sheet.close(); sheet.confirmed() }
            }
        }
    }
}
