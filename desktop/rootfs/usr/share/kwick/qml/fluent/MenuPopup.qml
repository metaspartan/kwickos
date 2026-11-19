import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

QQC2.Popup {
    id: menu

    default property alias entries: column.data

    function popup(item, px, py) {
        const p = item.mapToItem(parent, px, py)
        x = p.x
        y = p.y
        open()
    }

    margins: 4
    padding: 0
    topPadding: 2
    bottomPadding: 2
    implicitWidth: Math.max(160, column.implicitWidth)
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside

    background: Rectangle {
        radius: Fluent.overlayRadius
        color: Fluent.menu
        border.width: 1
        border.color: Fluent.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
    }

    contentItem: ColumnLayout {
        id: column
        spacing: 0
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 83 }
    }
}
