import QtQuick

Rectangle {
    id: p
    property string kind: "macos"
    property bool dockSide: false
    property string dockAt: "bottom"
    implicitWidth: 200
    implicitHeight: 124
    radius: 10
    clip: true
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: "#1a1440" }
        GradientStop { position: 0.55; color: "#2b1d6b" }
        GradientStop { position: 1; color: "#0f6b78" }
    }

    Rectangle {
        id: win
        radius: 5
        color: "#2c2c32"
        border.width: 1
        border.color: "#26ffffff"
        width: parent.width * 0.5
        height: parent.height * 0.5
        x: p.kind === "windows" ? (parent.width - width) / 2 : parent.width * 0.22
        y: p.kind === "windows" ? parent.height * 0.14 : p.kind === "linux" ? parent.height * 0.2 : parent.height * 0.16
        Row {
            x: 6
            y: 5
            spacing: 3
            visible: p.kind !== "windows"
            Repeater { model: ["#ff5f57", "#febc2e", "#28c840"]; Rectangle { width: 5; height: 5; radius: 2.5; color: modelData } }
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 6
            y: 5
            spacing: 3
            visible: p.kind === "windows"
            Repeater { model: 3; Rectangle { width: 5; height: 1.5; color: "#aaaaaa"; y: 2 } }
        }
        Rectangle { x: 6; y: 17; width: parent.width - 12; height: 3; radius: 1.5; color: "#3d3d45" }
        Rectangle { x: 6; y: 25; width: (parent.width - 12) * 0.6; height: 3; radius: 1.5; color: "#3d3d45" }
    }

    Rectangle {
        visible: p.kind === "macos" || p.kind === "linux"
        width: parent.width
        height: 8
        color: p.kind === "macos" ? "#50000000" : "#e61a1b26"
        Rectangle { x: 6; y: 2.5; width: 8; height: 3; radius: 1.5; color: "#c0ffffff" }
        Rectangle { anchors.right: parent.right; anchors.rightMargin: 6; y: 2.5; width: 12; height: 3; radius: 1.5; color: "#90ffffff" }
    }

    Rectangle {
        visible: p.kind === "macos"
        width: parent.width * 0.5
        height: 16
        radius: 8
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        color: "#66ffffff"
        border.width: 1
        border.color: "#40ffffff"
        Row {
            anchors.centerIn: parent
            spacing: 4
            Repeater { model: 5; Rectangle { width: 9; height: 9; radius: 3; color: ["#0a84ff", "#30d158", "#ff9f0a", "#bf5af2", "#ff453a"][index] } }
        }
    }

    Rectangle {
        visible: p.kind === "windows"
        width: parent.width
        height: 12
        anchors.bottom: parent.bottom
        color: "#d9202024"
        Row {
            anchors.centerIn: parent
            spacing: 3
            Repeater { model: 5; Rectangle { width: 6; height: 6; radius: 1.5; color: index === 0 ? "#60cdff" : "#b0ffffff" } }
        }
    }

    Rectangle {
        visible: p.kind === "linux"
        width: parent.width
        height: 11
        anchors.bottom: parent.bottom
        color: "#f01a1b26"
        Row {
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Repeater { model: 4; Rectangle { width: 10; height: 5; radius: 1.5; color: index === 0 ? "#5e81f4" : "#80ffffff" } }
        }
    }
}
