import QtQuick

Rectangle {
    id: b
    property string text
    property bool primary: false
    property bool enabled: true
    property bool danger: false
    signal clicked()
    implicitWidth: label.implicitWidth + 28
    implicitHeight: 30
    radius: 8
    readonly property bool filled: primary && enabled
    readonly property color ink: !enabled ? Theme.faint : danger ? Theme.bad : filled ? "#ffffff" : Theme.controlText
    color: !enabled ? Theme.control
                    : filled ? (area.pressed ? Theme.fillPressed : area.containsMouse ? Theme.fillHover : Theme.fill)
                    : (area.pressed ? Theme.controlPressed : area.containsMouse ? Theme.controlHover : Theme.control)
    border.width: Theme.light && !filled ? 1 : 0
    border.color: Theme.lineStrong

    property string chevron: ""

    Canvas {
        id: arrow
        visible: b.chevron !== ""
        anchors.centerIn: parent
        width: 12
        height: 12
        property color ink: b.ink
        onInkChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.strokeStyle = String(arrow.ink);
            ctx.lineWidth = 1.6;
            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            ctx.beginPath();
            if (b.chevron === "up") {
                ctx.moveTo(2, 8);
                ctx.lineTo(6, 4);
                ctx.lineTo(10, 8);
            } else {
                ctx.moveTo(2, 4);
                ctx.lineTo(6, 8);
                ctx.lineTo(10, 4);
            }
            ctx.stroke();
        }
    }

    Text {
        id: label
        visible: b.chevron === ""
        anchors.centerIn: parent
        text: b.text
        color: b.ink
        font.family: Theme.sans
        font.pixelSize: 13
        font.weight: Font.Medium
    }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.topMargin: -7
        anchors.bottomMargin: -7
        hoverEnabled: true
        enabled: b.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: b.clicked()
    }
}
