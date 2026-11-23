import QtQuick
import QtQuick.Controls.Basic

Item {
    id: sw
    property color color: "transparent"
    property bool selected: false
    property bool rainbow: false
    property string tip: ""
    signal clicked()
    implicitWidth: 20
    implicitHeight: 20

    Canvas {
        anchors.fill: parent
        visible: sw.rainbow
        onPaint: {
            var c = getContext("2d")
            c.reset()
            var g = c.createConicalGradient(width / 2, height / 2, 0)
            var stops = ["#ff453a", "#ff9f0a", "#ffd60a", "#30d158", "#64d2ff", "#0a84ff", "#bf5af2", "#ff375f", "#ff453a"]
            for (var i = 0; i < stops.length; i++)
                g.addColorStop(i / (stops.length - 1), stops[i])
            c.fillStyle = g
            c.beginPath()
            c.arc(width / 2, height / 2, width / 2, 0, Math.PI * 2)
            c.fill()
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: sw.rainbow ? "transparent" : sw.color
        border.width: 1
        border.color: Theme.light ? "#26000000" : "#33ffffff"
    }

    Rectangle {
        visible: sw.selected
        anchors.centerIn: parent
        width: 6
        height: 6
        radius: 3
        color: "#ffffff"
    }

    Rectangle {
        visible: sw.selected
        anchors.centerIn: parent
        width: parent.width + 6
        height: parent.height + 6
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: Theme.light ? "#40000000" : "#59ffffff"
    }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -3
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.clicked()
    }

    ToolTip.visible: area.containsMouse && sw.tip !== ""
    ToolTip.delay: 500
    ToolTip.text: sw.tip
}
