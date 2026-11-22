import QtQuick

Rectangle {
    id: p
    property string kind: "plasma"
    property string layout: "macos"
    property bool lightMode: false
    readonly property bool tiled: kind === "hyprland" || kind === "sway" || kind === "dms" || kind === "noctalia"
    readonly property color winBg: lightMode ? "#f4f4f6" : "#2c2c2e"
    readonly property color winLine: lightMode ? "#1f000000" : "#26ffffff"
    readonly property color ink: lightMode ? "#33000000" : "#40ffffff"
    readonly property color accent: kind === "dms" ? (lightMode ? "#6750a4" : "#b69df8") : kind === "noctalia" ? (lightMode ? "#8a7a00" : "#fff59b") : layout === "windows" ? "#3b9cff" : layout === "linux" ? "#7c8cff" : "#0a84ff"
    implicitWidth: 240
    implicitHeight: 140
    radius: 10
    clip: true
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: p.lightMode ? "#c9d6f2" : p.kind === "dms" ? "#20183a" : p.kind === "noctalia" ? "#14141c" : "#1a1440" }
        GradientStop { position: 0.55; color: p.lightMode ? "#dccff5" : p.kind === "dms" ? "#3a2a5e" : p.kind === "noctalia" ? "#23233a" : "#2b1d6b" }
        GradientStop { position: 1; color: p.lightMode ? "#bfe3e8" : p.kind === "dms" ? "#1d3b4f" : p.kind === "noctalia" ? "#2e2a3c" : "#0f6b78" }
    }

    component Lines: Item {
        Rectangle { x: 6; y: 6; width: parent.width - 12; height: 3; radius: 1.5; color: p.ink }
        Rectangle { x: 6; y: 13; width: (parent.width - 12) * 0.62; height: 3; radius: 1.5; color: p.ink }
        Rectangle { x: 6; y: 20; width: (parent.width - 12) * 0.8; height: 3; radius: 1.5; color: p.ink; visible: parent.height > 30 }
    }

    Rectangle {
        visible: !p.tiled
        radius: 5
        color: p.winBg
        border.width: 1
        border.color: p.winLine
        width: parent.width * 0.52
        height: parent.height * 0.5
        x: parent.width * 0.22
        y: parent.height * 0.2
        Row {
            x: 6
            y: 5
            spacing: 3
            visible: p.kind === "plasma" && p.layout === "macos" || p.kind === "gnome" && p.layout === "macos"
            Repeater { model: ["#ff5f57", "#febc2e", "#28c840"]; Rectangle { width: 5; height: 5; radius: 2.5; color: modelData } }
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 6
            y: 5
            spacing: 3
            visible: !(p.layout === "macos")
            Repeater { model: 3; Rectangle { width: 5; height: 5; radius: 2.5; color: index === 2 ? p.accent : p.ink } }
        }
        Lines { anchors.fill: parent; anchors.topMargin: 12 }
    }

    Item {
        id: tiles
        visible: p.tiled
        readonly property real gap: p.kind === "sway" ? 2 : 5
        readonly property real topPad: p.kind === "dms" || p.kind === "noctalia" ? 22 : p.kind === "sway" ? 13 : 16
        readonly property real rad: p.kind === "sway" ? 0 : p.kind === "dms" ? 7 : 5
        x: gap + (p.kind === "noctalia" ? 0 : 0)
        y: topPad
        width: parent.width - 2 * gap
        height: parent.height - topPad - gap - (p.kind === "hyprland" && p.layout === "macos" ? 18 : 0)
        Rectangle {
            width: (parent.width - tiles.gap) * 0.55
            height: parent.height
            radius: tiles.rad
            color: p.winBg
            border.width: p.kind === "sway" ? 1 : 1.5
            border.color: p.accent
            Lines { anchors.fill: parent; anchors.topMargin: 4 }
        }
        Rectangle {
            x: (parent.width - tiles.gap) * 0.55 + tiles.gap
            width: parent.width - x
            height: (parent.height - tiles.gap) / 2
            radius: tiles.rad
            color: p.winBg
            border.width: 1
            border.color: p.winLine
            Lines { anchors.fill: parent; anchors.topMargin: 4 }
        }
        Rectangle {
            x: (parent.width - tiles.gap) * 0.55 + tiles.gap
            y: (parent.height - tiles.gap) / 2 + tiles.gap
            width: parent.width - x
            height: (parent.height - tiles.gap) / 2
            radius: tiles.rad
            color: p.winBg
            border.width: 1
            border.color: p.winLine
            Lines { anchors.fill: parent; anchors.topMargin: 4 }
        }
    }

    Rectangle {
        visible: p.kind === "plasma" && p.layout === "macos" || p.kind === "hyprland" && p.layout !== "windows" || p.kind === "sway"
        width: parent.width
        height: p.kind === "sway" ? 9 : p.kind === "hyprland" ? 11 : 8
        color: p.kind === "sway" ? (p.lightMode ? "#e8e8e8" : "#1d1d1f") : p.lightMode ? "#b3ffffff" : "#59000000"
        Row {
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Repeater {
                model: p.kind === "plasma" ? 4 : 5
                Rectangle { width: p.kind === "plasma" ? (index === 0 ? 5 : 10) : 5; height: p.kind === "plasma" ? 2.5 : 5; radius: 1.5; color: p.kind !== "plasma" && index === 0 ? p.accent : p.ink }
            }
        }
        Rectangle { anchors.centerIn: parent; visible: p.kind !== "plasma"; width: 22; height: 3; radius: 1.5; color: p.ink }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Repeater { model: 3; Rectangle { width: index === 2 ? 14 : 5; height: 3; radius: 1.5; color: p.ink } }
        }
    }

    Rectangle {
        visible: p.kind === "gnome"
        width: parent.width
        height: 9
        color: p.lightMode ? "#f0f0f0" : "#000000"
        Rectangle { x: 6; anchors.verticalCenter: parent.verticalCenter; width: 14; height: 4; radius: 2; color: p.lightMode ? "#40000000" : "#59ffffff" }
        Rectangle { anchors.centerIn: parent; width: 26; height: 3; radius: 1.5; color: p.lightMode ? "#59000000" : "#bfffffff" }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Repeater { model: 3; Rectangle { width: 4; height: 4; radius: 2; color: p.lightMode ? "#59000000" : "#bfffffff" } }
        }
    }

    Rectangle {
        visible: p.kind === "dms" || p.kind === "noctalia"
        x: 5
        y: 5
        width: parent.width - 10
        height: 13
        radius: p.kind === "dms" ? 6.5 : 4
        color: p.lightMode ? "#e6fbf8ff" : p.kind === "dms" ? "#e6211f26" : "#f0101016"
        border.width: p.kind === "noctalia" ? 1 : 0
        border.color: "#26ffffff"
        Row {
            x: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2.5
            Rectangle { width: 9; height: 9; radius: 4.5; color: p.accent; visible: p.kind === "noctalia" }
            Repeater {
                model: 4
                Rectangle { width: index === 0 ? 12 : 5; height: 5; radius: 2.5; color: index === 0 ? p.accent : p.lightMode ? "#40000000" : "#59ffffff"; anchors.verticalCenter: parent.verticalCenter }
            }
        }
        Rectangle {
            anchors.centerIn: parent
            width: 30
            height: 8
            radius: 4
            color: p.kind === "dms" ? (p.lightMode ? "#e8def8" : "#4a4458") : "transparent"
            Rectangle { anchors.centerIn: parent; width: 20; height: 3; radius: 1.5; color: p.lightMode ? "#59000000" : "#d9ffffff" }
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2.5
            Repeater {
                model: 3
                Rectangle { width: index === 2 ? 16 : 7; height: 7; radius: 3.5; color: index === 2 ? (p.kind === "dms" ? (p.lightMode ? "#e8def8" : "#4a4458") : "#2a2a36") : p.lightMode ? "#33000000" : "#40ffffff" }
            }
        }
    }

    Rectangle {
        visible: p.kind === "plasma" && p.layout === "macos" || p.kind === "gnome" || p.kind === "hyprland" && p.layout === "macos"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        width: 82
        height: 13
        radius: 4
        color: p.lightMode ? "#99ffffff" : "#4dffffff"
        border.width: 1
        border.color: p.lightMode ? "#33ffffff" : "#26ffffff"
        Row {
            anchors.centerIn: parent
            spacing: 3
            Repeater {
                model: ["#0a84ff", "#30d158", "#ff9f0a", "#bf5af2", "#64d2ff", "#ff453a"]
                Rectangle { width: 9; height: 9; radius: 2.5; color: modelData }
            }
        }
    }

    Rectangle {
        visible: p.kind === "plasma" && p.layout !== "macos" || p.kind === "hyprland" && p.layout === "windows"
        anchors.bottom: parent.bottom
        width: parent.width
        height: 13
        color: p.lightMode ? "#d9f3f3f3" : "#e6202020"
        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: p.layout === "windows" ? (parent.width - width) / 2 : 6
            spacing: 4
            Repeater {
                model: 5
                Rectangle { width: 8; height: 8; radius: 2; color: index === 0 ? p.accent : p.lightMode ? "#40000000" : "#4dffffff" }
            }
        }
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 3
            radius: 1.5
            color: p.lightMode ? "#59000000" : "#8cffffff"
        }
    }
}
