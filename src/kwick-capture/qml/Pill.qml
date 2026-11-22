import QtQuick
import KwickCapture

Item {
    id: root
    property int edge: 0
    readonly property bool counting: Capture.countdown > 0
    readonly property int seconds: Capture.recordSeconds

    Palette { id: pal }

    function two(n) {
        return n < 10 ? "0" + n : "" + n
    }
    function syncMask() {
        Capture.setMask(root.Window.window, [Qt.rect(pill.x - 6, pill.y - 6, pill.width + 12, pill.height + 12)])
    }
    onWidthChanged: syncMask()
    Component.onCompleted: syncMask()

    PanelBox {
        id: pill
        width: row.implicitWidth + 22
        height: 40
        radius: 20
        rings: 4
        x: Math.round((root.width - width) / 2)
        y: 10 + root.edge
        onWidthChanged: root.syncMask()
        onXChanged: root.syncMask()
        onYChanged: root.syncMask()

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 10

            Rectangle {
                visible: !root.counting
                width: 10
                height: 10
                radius: 5
                anchors.verticalCenter: parent.verticalCenter
                color: "#ff3b30"
                SequentialAnimation on opacity {
                    running: !root.counting
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
            }
            Glyph {
                visible: root.counting
                name: "timer"
                width: 18
                height: 18
                anchors.verticalCenter: parent.verticalCenter
                tint: pal.label
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.counting ? "Capturing in " + Capture.countdown + " s" : Math.floor(root.seconds / 60) + ":" + root.two(root.seconds % 60)
                color: pal.label
                font.family: pal.sans
                font.pixelSize: 13
                font.weight: Font.Medium
                font.features: { "tnum": 1 }
            }
            Rectangle {
                width: actionRow.implicitWidth + 20
                height: 28
                radius: 14
                anchors.verticalCenter: parent.verticalCenter
                color: actionArea.pressed ? pal.pressed : actionArea.containsMouse ? pal.selected : pal.hover
                Row {
                    id: actionRow
                    anchors.centerIn: parent
                    spacing: 6
                    Glyph {
                        visible: !root.counting
                        name: "stop"
                        width: 12
                        height: 12
                        anchors.verticalCenter: parent.verticalCenter
                        tint: pal.label
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.counting ? "Cancel" : "Stop"
                        color: pal.label
                        font.family: pal.sans
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }
                MouseArea {
                    id: actionArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.counting ? Capture.cancelCountdown() : Capture.stopRecording()
                }
            }
        }
    }
}
