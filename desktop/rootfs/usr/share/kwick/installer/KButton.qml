import QtQuick

FocusScope {
    id: b
    property string text
    property string kind: "secondary"
    property bool large: false
    property bool busy: false
    signal clicked()

    readonly property bool primary: kind === "primary"
    readonly property bool destructive: kind === "destructive"
    readonly property bool filled: primary || destructive
    readonly property bool down: area.pressed || keyDown

    property bool keyDown: false
    implicitWidth: Math.max(large ? 200 : 96, label.implicitWidth + (large ? 48 : 36))
    implicitHeight: large ? 44 : 34
    activeFocusOnTab: enabled
    opacity: enabled ? 1 : 0.42
    Behavior on opacity { NumberAnimation { duration: 160 } }

    Rectangle {
        anchors.fill: face
        anchors.margins: -3.5
        radius: face.radius + 3.5
        color: "transparent"
        border.width: 3
        border.color: Theme.focusRing
        visible: b.activeFocus
    }

    Rectangle {
        anchors.fill: face
        anchors.topMargin: 1
        anchors.bottomMargin: -1
        radius: face.radius
        color: Theme.dark ? "#40000000" : "#14000000"
        visible: !b.filled
    }

    Rectangle {
        id: face
        anchors.fill: parent
        radius: b.large ? 11 : 8
        color: b.primary ? (b.down ? Theme.accentPressed : area.containsMouse ? Theme.accentHover : Theme.accent)
             : b.destructive ? (b.down ? Theme.badPressed : area.containsMouse ? Qt.lighter(Theme.bad, 1.06) : Theme.bad)
             : (b.down ? Theme.buttonPressed : area.containsMouse ? Theme.buttonHover : Theme.button)
        border.width: b.filled ? 0 : 1
        border.color: Theme.dark ? "#1affffff" : "#1f000000"
        Behavior on color { ColorAnimation { duration: 120 } }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: b.filled
            gradient: Gradient {
                GradientStop { position: 0; color: "#1fffffff" }
                GradientStop { position: 1; color: "#00ffffff" }
            }
        }

        Text {
            id: label
            anchors.centerIn: parent
            text: b.text
            visible: !b.busy
            color: b.filled ? Theme.accentText : Theme.text
            font.family: Theme.sans
            font.pixelSize: b.large ? 16 : 14
            font.weight: Font.Medium
        }

        Spinner {
            anchors.centerIn: parent
            visible: b.busy
            size: 16
            color: b.filled ? Theme.accentText : Theme.sub
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: b.enabled && !b.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: b.clicked()
    }

    Keys.onPressed: (e) => {
        if (e.key === Qt.Key_Space && !e.isAutoRepeat) { b.keyDown = true; e.accepted = true }
    }
    Keys.onReleased: (e) => {
        if (e.key === Qt.Key_Space && !e.isAutoRepeat && b.keyDown) {
            b.keyDown = false
            e.accepted = true
            if (b.enabled && !b.busy) b.clicked()
        }
    }
}
