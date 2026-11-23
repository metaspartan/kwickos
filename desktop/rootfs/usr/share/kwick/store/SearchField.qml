import QtQuick

Rectangle {
    id: sf
    property alias text: input.text
    property string placeholder: "Search"
    property alias input: input
    signal accepted(string text)
    signal cleared()
    implicitHeight: Look.mac ? 28 : Look.win ? 34 : 34
    radius: Look.win ? 4 : Look.mac ? 7 : 8
    color: Look.field
    border.width: Look.win ? 1 : input.activeFocus && !Look.mac ? 2 : 0
    border.color: Look.win ? Look.fieldStroke : Look.accent

    Rectangle {
        visible: Look.win && input.activeFocus
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 1
        height: 2
        color: Look.accent
    }

    Rectangle {
        visible: Look.mac && input.activeFocus
        anchors.fill: parent
        anchors.margins: -3
        radius: parent.radius + 3
        color: "transparent"
        border.width: 3
        border.color: Qt.rgba(Look.accent.r, Look.accent.g, Look.accent.b, 0.5)
    }

    Glyph {
        id: mag
        x: Look.win ? parent.width - 30 : 9
        anchors.verticalCenter: parent.verticalCenter
        name: "search"
        size: Look.mac ? 14 : 16
        color: Look.sub
        stroke: 1.8
    }

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: Look.win ? 12 : 30
        anchors.rightMargin: Look.win ? 38 : 26
        verticalAlignment: TextInput.AlignVCenter
        color: Look.text
        font.family: Look.sans
        font.pixelSize: Look.win ? 14 : 13
        selectionColor: Look.mac ? Qt.rgba(Look.accent.r, Look.accent.g, Look.accent.b, Look.light ? 0.3 : 0.4) : Look.accent
        selectedTextColor: Look.mac ? Look.text : "#ffffff"
        clip: true
        onAccepted: sf.accepted(text)
        Keys.onEscapePressed: { text = ""; sf.cleared() }
        Text {
            visible: !input.text.length
            anchors.verticalCenter: parent.verticalCenter
            text: sf.placeholder
            color: Look.faint
            font: input.font
        }
    }

    Rectangle {
        visible: input.text.length > 0
        width: 16
        height: 16
        radius: 8
        x: Look.win ? parent.width - 56 : parent.width - 22
        anchors.verticalCenter: parent.verticalCenter
        color: Look.faint
        Glyph { anchors.centerIn: parent; name: "close"; size: 10; stroke: 2; color: Look.field }
        MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: { input.text = ""; sf.cleared() } }
    }
}
