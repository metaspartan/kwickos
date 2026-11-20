import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

MouseArea {
    id: button

    property alias icon: glyph.source
    property bool open: false
    property bool mask: false
    property color tint: Fluent.text
    default property alias content: row.data

    Layout.fillHeight: true
    Layout.minimumWidth: Math.max(44, row.implicitWidth + 16)
    Layout.preferredWidth: Layout.minimumWidth
    Layout.maximumWidth: Layout.minimumWidth
    hoverEnabled: true

    Rectangle {
        anchors.centerIn: parent
        width: parent.width
        height: Math.min(40, parent.height)
        radius: Fluent.radius
        color: button.pressed ? Fluent.subtlePressed : button.containsMouse || button.open ? Fluent.subtleHover : "transparent"
        border.width: button.containsMouse || button.open ? 1 : 0
        border.color: Fluent.dark ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.04)
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 0

        Kirigami.Icon {
            id: glyph
            visible: !!source && String(source) !== ""
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
            isMask: button.mask
            color: button.tint
            scale: button.pressed ? 0.88 : 1
            Behavior on scale { NumberAnimation { duration: 100 } }
        }
    }
}
