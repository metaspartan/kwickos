import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell

Window {
    id: win
    width: Screen.width
    height: Screen.height
    color: "transparent"
    title: "Keyboard Shortcuts"
    visible: false

    LayerShell.Window.scope: "kwick-keys"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityExclusive
    LayerShell.Window.exclusionZone: -1

    Sheet {
        anchors.fill: parent
        keymap: JSON.parse(Qt.application.arguments[Qt.application.arguments.length - 1])
        onDone: Qt.quit()
    }

    Component.onCompleted: visible = true
}
