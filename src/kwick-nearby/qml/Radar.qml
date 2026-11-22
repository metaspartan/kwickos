import QtQuick

Item {
    id: radar
    property Look pal
    property bool active: true
    implicitWidth: 150
    implicitHeight: 150

    Repeater {
        model: 3
        Rectangle {
            id: ring
            required property int index
            property real phase: 0
            anchors.centerIn: parent
            width: 56 + (radar.width - 56) * phase
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1.5
            border.color: radar.pal.accent
            opacity: radar.active ? (1 - phase) * 0.55 : (index === 0 ? 0.25 : 0)
            SequentialAnimation on phase {
                running: radar.active
                loops: Animation.Infinite
                PauseAnimation { duration: ring.index * 800 }
                NumberAnimation { from: 0; to: 1; duration: 2400; easing.type: Easing.OutCubic }
            }
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: 56
        height: 56
        radius: 28
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(radar.pal.accent, 1.25) }
            GradientStop { position: 1; color: radar.pal.accent }
        }
        Glyph {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -1
            name: "waves"
            width: 28
            height: 28
            tint: "#ffffff"
        }
    }
}
