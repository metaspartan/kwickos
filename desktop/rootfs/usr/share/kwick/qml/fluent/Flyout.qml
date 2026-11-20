import QtQuick
import org.kde.plasma.core as PlasmaCore

PlasmaCore.Dialog {
    id: flyout

    property Item anchorItem
    property bool centered: false
    property double closedAt: 0
    property size area: Qt.size(1280, 720)

    function toggle() {
        if (visible) {
            visible = false
        } else if (Date.now() - closedAt > 300) {
            const panel = anchorItem ? anchorItem.Window.window : null
            if (panel)
                area = Qt.size(anchorItem.Screen.width, anchorItem.Screen.height - panel.height - 24 - margins.top - margins.bottom)
            visible = true
        }
    }

    function place() {
        const panel = anchorItem ? anchorItem.Window.window : null
        if (!panel)
            return
        const s = anchorItem.Screen
        x = centered ? Math.round(s.virtualX + (s.width - width) / 2) : s.virtualX + s.width - width - 12
        y = s.virtualY + s.height - panel.height - height - 12
    }

    visible: false
    location: PlasmaCore.Types.Floating
    type: PlasmaCore.Dialog.AppletPopup
    hideOnWindowDeactivate: true
    flags: Qt.WindowStaysOnTopHint

    onWidthChanged: place()
    onHeightChanged: place()
    onVisibleChanged: {
        if (visible) {
            place()
            if (mainItem)
                mainItem.forceActiveFocus()
        } else {
            closedAt = Date.now()
        }
    }
}
