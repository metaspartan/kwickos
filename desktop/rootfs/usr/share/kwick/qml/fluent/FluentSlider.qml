import QtQuick

MouseArea {
    id: slider

    property real value: 0
    readonly property real clamped: Math.max(0, Math.min(1, value))
    signal moved(real value)

    implicitHeight: 32
    implicitWidth: 200
    hoverEnabled: true
    preventStealing: true

    function emitAt(x) {
        slider.moved(Math.max(0, Math.min(1, (x - 10) / (width - 20))))
    }

    onPressed: mouse => emitAt(mouse.x)
    onPositionChanged: mouse => {
        if (pressed)
            emitAt(mouse.x)
    }
    onWheel: wheel => slider.moved(Math.max(0, Math.min(1, value + (wheel.angleDelta.y > 0 ? 0.02 : -0.02))))

    Rectangle {
        x: 10
        width: parent.width - 20
        height: 4
        radius: 2
        anchors.verticalCenter: parent.verticalCenter
        color: Fluent.sliderTrack

        Rectangle {
            width: parent.width * slider.clamped
            height: parent.height
            radius: 2
            color: Fluent.accent
        }
    }

    Rectangle {
        width: 20
        height: 20
        radius: 10
        x: (parent.width - 20) * slider.clamped
        anchors.verticalCenter: parent.verticalCenter
        color: Fluent.thumb
        border.width: 1
        border.color: Fluent.dark ? Qt.rgba(1, 1, 1, 0.094) : Qt.rgba(0, 0, 0, 0.06)

        Rectangle {
            readonly property int size: slider.pressed ? 10 : slider.containsMouse ? 14 : 12
            anchors.centerIn: parent
            width: size
            height: size
            radius: size / 2
            color: Fluent.accent
            Behavior on width { NumberAnimation { duration: 100 } }
            Behavior on height { NumberAnimation { duration: 100 } }
        }
    }
}
