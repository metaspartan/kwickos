import QtQuick
import QtQuick.Layouts

Rectangle {
    id: meter
    property real value: -1
    property color tint: Theme.accent
    Layout.fillWidth: true
    implicitHeight: 6
    radius: 3
    color: Theme.track
    clip: true

    Rectangle {
        visible: meter.value >= 0
        height: parent.height
        radius: 3
        color: meter.tint
        width: parent.width * Math.max(0.02, Math.min(1, meter.value / 100))
        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
    }

    Rectangle {
        id: sweep
        visible: meter.value < 0
        height: parent.height
        width: parent.width * 0.28
        radius: 3
        color: meter.tint
        NumberAnimation on x { running: sweep.visible; loops: Animation.Infinite; from: -sweep.width; to: sweep.parent.width; duration: 1300; easing.type: Easing.InOutQuad }
    }
}
