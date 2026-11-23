import QtQuick
import org.kde.kirigami as Kirigami

MouseArea {
    id: glyph

    property bool on: false
    property string icon
    property int size: 28

    implicitWidth: size
    implicitHeight: size
    cursorShape: Qt.PointingHandCursor

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: glyph.on ? Kirigami.Theme.focusColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, glyph.pressed ? 0.22 : 0.14)
        Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
    }

    Kirigami.Icon {
        anchors.centerIn: parent
        width: Math.round(glyph.size * 0.6)
        height: width
        source: glyph.icon
        isMask: true
        color: glyph.on ? "#ffffff" : Kirigami.Theme.textColor
    }
}
