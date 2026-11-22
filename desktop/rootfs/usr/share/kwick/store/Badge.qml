import QtQuick

Rectangle {
    id: bd
    property string src
    property string label: Look.sourceName(src)
    property color tint: Look.sourceTint(src)
    implicitWidth: t.implicitWidth + 12
    implicitHeight: 18
    radius: Look.win ? 4 : 5
    color: Qt.rgba(tint.r, tint.g, tint.b, Look.light ? 0.12 : 0.2)
    Text {
        id: t
        anchors.centerIn: parent
        text: bd.label
        color: bd.tint
        font.family: Look.sans
        font.pixelSize: 11
        font.weight: Font.DemiBold
    }
}
