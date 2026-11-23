import QtQuick
import QtQuick.Window

Window {
    id: win
    width: Screen.desktopAvailableWidth
    height: Screen.desktopAvailableHeight
    color: "transparent"
    title: "Keyboard Shortcuts"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint

    Sheet {
        anchors.fill: parent
        keymap: JSON.parse(Qt.application.arguments[Qt.application.arguments.length - 1])
        onDone: Qt.quit()
    }

    Component.onCompleted: win.showMaximized()
}
