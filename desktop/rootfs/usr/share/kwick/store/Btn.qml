import QtQuick
import QtQuick.Layouts

Rectangle {
    id: b
    property string text
    property string glyph
    property bool primary: false
    property bool danger: false
    property bool flat: false
    property bool enabled: true
    signal clicked()
    implicitWidth: row.implicitWidth + (Look.win ? 24 : 26)
    implicitHeight: Look.mac ? 28 : Look.win ? 32 : 34
    radius: Look.mac && primary ? height / 2 : Look.controlRadius
    readonly property bool macOff: Look.mac && !enabled
    opacity: enabled || macOff ? 1 : 0.45
    color: macOff ? (flat ? "transparent" : Look.getBg)
         : primary ? (area.pressed ? Qt.darker(Look.fill, 1.12) : area.containsMouse ? Qt.darker(Look.fill, 1.06) : Look.fill)
                   : flat ? (area.pressed ? Look.pressed : area.containsMouse ? Look.hover : "transparent")
                   : Look.mac ? (area.pressed ? Look.pressed : area.containsMouse ? Look.getBgHover : Look.getBg)
                   : (area.pressed ? Look.pressed : area.containsMouse ? Qt.tint(Look.openBg, Look.hover) : Look.openBg)
    border.width: Look.win && !primary && !flat ? 1 : 0
    border.color: Look.fieldStroke

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Glyph {
            visible: b.glyph !== ""
            name: b.glyph
            size: 16
            color: lbl.color
        }
        Text {
            id: lbl
            visible: b.text !== ""
            text: b.text
            color: b.macOff ? Look.faint : b.primary ? (Look.win ? Look.onAccent : "#ffffff") : b.danger ? Look.bad : Look.mac && !b.flat ? Look.accentText : Look.text
            font.family: Look.sans
            font.pixelSize: Look.win ? 14 : 13
            font.weight: Look.mac ? Font.DemiBold : Look.win ? Font.Normal : Font.Bold
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: b.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: b.clicked()
    }
}
