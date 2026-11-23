import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

ApplicationWindow {
    id: win
    visible: false
    width: 900
    height: 780
    minimumWidth: 720
    minimumHeight: 520
    title: "Software Update"
    color: Theme.bg

    Component.onCompleted: {
        Qt.application.domain = "softwareupdate.kwickos.org"
        visible = true
        Sys.refresh()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 36
            Layout.rightMargin: 36
            Layout.topMargin: 24
            Layout.bottomMargin: 14
            spacing: 14
            Image {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                source: "/usr/share/icons/hicolor/scalable/apps/kwick-software-update.svg"
                sourceSize.width: 88
                sourceSize.height: 88
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text { Layout.fillWidth: true; text: "Software Update"; color: Theme.text; font.family: Theme.sans; font.pixelSize: 24; font.weight: Font.DemiBold }
                Text { Layout.fillWidth: true; text: "KwickOS, apps and kernels"; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 12 }
            }
            Rectangle {
                implicitWidth: storeRow.implicitWidth + 24
                implicitHeight: 30
                radius: 8
                color: storeArea.pressed ? Theme.controlPressed : storeArea.containsMouse ? Theme.controlHover : Theme.control
                border.width: Theme.light ? 1 : 0
                border.color: Theme.lineStrong
                RowLayout {
                    id: storeRow
                    anchors.centerIn: parent
                    spacing: 6
                    Text { text: "App Store…"; color: Theme.controlText; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.Medium }
                }
                MouseArea { id: storeArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Sys.run("setsid kwick-store updates >/dev/null 2>&1 &") }
            }
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: loader.implicitHeight + 40
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { }

            Loader {
                id: loader
                x: 36
                width: flick.width - 72
                source: "PageUpdate.qml"
            }
        }
    }
}
