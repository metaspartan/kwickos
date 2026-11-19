import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: bar

    property real value: 0
    property string icon
    property bool active: true

    signal moved(real value)
    signal iconClicked()

    implicitHeight: 24
    opacity: active ? 1 : 0.4

    function setFrom(x) {
        const v = Math.max(0, Math.min(1, (x - height / 2) / Math.max(1, width - height)))
        bar.moved(v)
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.14)
    }

    Rectangle {
        height: parent.height
        width: height + (parent.width - height) * Math.max(0, Math.min(1, bar.value))
        radius: height / 2
        color: "#f2f2f2"
    }

    Rectangle {
        x: Math.round((bar.width - bar.height) * Math.max(0, Math.min(1, bar.value)))
        width: bar.height
        height: bar.height
        radius: width / 2
        color: "#ffffff"
        border.width: 0.5
        border.color: Qt.rgba(0, 0, 0, 0.12)
    }

    MouseArea {
        anchors.fill: parent
        enabled: bar.active
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => {
            if (mouse.x < bar.height * 0.9 && bar.value > 0.08)
                bar.iconClicked()
            else
                bar.setFrom(mouse.x)
        }
        onPositionChanged: mouse => { if (pressed) bar.setFrom(mouse.x) }
        onWheel: wheel => bar.moved(Math.max(0, Math.min(1, bar.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
    }

    Kirigami.Icon {
        x: Math.round((bar.height - width) / 2) + 1
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        height: 16
        source: bar.icon
        isMask: true
        color: "#3a3a3c"
    }
}
