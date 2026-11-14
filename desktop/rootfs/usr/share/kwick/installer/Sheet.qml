import QtQuick
import QtQuick.Layouts

FocusScope {
    id: sh
    property string title
    property string message
    property string icon: "file:///usr/share/icons/hicolor/scalable/apps/kwickos-logo.svg"
    property string confirmText: "OK"
    property string cancelText: "Cancel"
    property bool destructive: false
    property bool shown: false
    property bool single: false
    signal confirmed()
    signal cancelled()
    anchors.fill: parent
    visible: fade.opacity > 0.01
    z: 100

    function show() {
        shown = true
        if (single) okBtn.forceActiveFocus()
        else cancelBtn.forceActiveFocus()
    }
    function hide() { shown = false }

    Rectangle {
        id: fade
        anchors.fill: parent
        color: Theme.scrim
        opacity: sh.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.AllButtons; onWheel: (w) => w.accepted = true }
    }

    Rectangle {
        id: panel
        width: 340
        height: col.implicitHeight + 40
        anchors.centerIn: parent
        radius: 16
        color: Theme.dark ? "#2e2e33" : "#f6f6f8"
        border.width: 1
        border.color: Theme.dark ? "#26ffffff" : "#1a000000"
        opacity: sh.shown ? 1 : 0
        scale: sh.shown ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

        Rectangle {
            z: -1
            anchors.fill: parent
            anchors.topMargin: 10
            anchors.bottomMargin: -14
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            radius: 22
            color: Theme.shadow
            opacity: 0.55
        }

        ColumnLayout {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 22
            anchors.topMargin: 24
            spacing: 10

            Image {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 60
                Layout.preferredHeight: 60
                source: sh.icon
                sourceSize.width: 120
                sourceSize.height: 120
                fillMode: Image.PreserveAspectFit
                smooth: true
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 4
                text: sh.title
                color: Theme.text
                font.family: Theme.sans
                font.pixelSize: 15
                font.weight: Font.Bold
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                text: sh.message
                visible: text !== ""
                color: Theme.text
                opacity: 0.85
                font.family: Theme.sans
                font.pixelSize: 13
                lineHeight: 1.15
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 10
                spacing: 10
                KButton {
                    id: cancelBtn
                    Layout.fillWidth: true
                    visible: !sh.single
                    text: sh.cancelText
                    KeyNavigation.right: okBtn
                    KeyNavigation.tab: okBtn
                    onClicked: { sh.hide(); sh.cancelled() }
                    Keys.onReturnPressed: clicked()
                    Keys.onEnterPressed: clicked()
                }
                KButton {
                    id: okBtn
                    Layout.fillWidth: true
                    text: sh.confirmText
                    kind: sh.destructive ? "destructive" : "primary"
                    KeyNavigation.left: cancelBtn
                    KeyNavigation.tab: cancelBtn
                    onClicked: { sh.hide(); sh.confirmed() }
                    Keys.onReturnPressed: clicked()
                    Keys.onEnterPressed: clicked()
                }
            }
        }
    }

    Keys.onEscapePressed: { hide(); cancelled() }
}
