pragma Singleton
import QtQuick
import QtCore

QtObject {
    id: look

    property string layout: "macos"
    property bool light: false
    property color systemAccent: "#ff9f0a"
    property string systemAccentText: ""

    readonly property bool mac: layout === "macos"
    readonly property bool win: layout === "windows"
    readonly property bool gnu: layout === "linux"

    readonly property string sans: win ? "Selawik" : gnu ? "Ubuntu Sans" : "Inter"
    readonly property string display: win ? "Selawik" : gnu ? "Ubuntu Sans" : "Inter Display"
    readonly property string mono: win ? "Cascadia Code" : gnu ? "Ubuntu Sans Mono" : "JetBrains Mono"

    readonly property color accent: win ? (light ? "#005fb8" : "#60cdff") : gnu ? (light ? "#3584e4" : "#3584e4") : systemAccent
    readonly property color accentText: win ? (light ? "#005fb8" : "#60cdff") : gnu ? (light ? "#1c71d8" : "#78aeed") : (light ? (systemAccentText !== "" ? systemAccentText : Qt.darker(systemAccent, 1.08)) : Qt.lighter(systemAccent, 1.12))
    readonly property color onAccent: win && !light ? "#000000" : "#ffffff"

    readonly property color window: mac ? (light ? "#ffffff" : "#1e1e1e") : win ? (light ? "#f3f3f3" : "#202020") : (light ? "#fafafb" : "#222226")
    readonly property color sidebar: mac ? (light ? "#ebebeb" : "#2b2b2b") : win ? window : (light ? "#ebebed" : "#2e2e32")
    readonly property color content: mac ? window : win ? (light ? "#f9f9f9" : "#272727") : (light ? "#fafafb" : "#222226")
    readonly property color contentStroke: win ? (light ? Qt.rgba(0, 0, 0, 0.06) : Qt.rgba(0, 0, 0, 0.25)) : "transparent"
    readonly property color card: mac ? (light ? "#f5f5f7" : "#2c2c2e") : win ? (light ? "#ffffff" : "#2d2d2d") : (light ? "#ffffff" : "#353539")
    readonly property color cardHover: mac ? (light ? "#ececf0" : "#363638") : win ? (light ? "#f6f6f6" : "#323232") : (light ? "#f4f4f6" : "#3d3d41")
    readonly property color cardStroke: mac ? (light ? Qt.rgba(0, 0, 0, 0.05) : Qt.rgba(1, 1, 1, 0.06)) : win ? (light ? Qt.rgba(0, 0, 0, 0.07) : Qt.rgba(0, 0, 0, 0.3)) : (light ? Qt.rgba(0, 0, 0, 0.08) : Qt.rgba(0, 0, 0, 0.35))
    readonly property color field: mac ? (light ? "#e3e3e5" : "#3a3a3c") : win ? (light ? "#ffffff" : "#2d2d2d") : (light ? "#e6e6e8" : "#3a3a3e")
    readonly property color fieldStroke: win ? (light ? Qt.rgba(0, 0, 0, 0.12) : Qt.rgba(1, 1, 1, 0.08)) : "transparent"
    readonly property color popup: mac ? (light ? "#f6f6f6" : "#2e2e2e") : win ? (light ? "#f9f9f9" : "#2c2c2c") : (light ? "#ffffff" : "#36363a")
    readonly property color hover: light ? Qt.rgba(0, 0, 0, 0.05) : Qt.rgba(1, 1, 1, 0.07)
    readonly property color pressed: light ? Qt.rgba(0, 0, 0, 0.09) : Qt.rgba(1, 1, 1, 0.11)
    readonly property color selected: mac ? (light ? Qt.rgba(0, 0, 0, 0.09) : Qt.rgba(1, 1, 1, 0.1)) : win ? (light ? Qt.rgba(0, 0, 0, 0.05) : Qt.rgba(1, 1, 1, 0.07)) : (light ? Qt.rgba(0, 0, 0, 0.08) : Qt.rgba(1, 1, 1, 0.1))
    readonly property color line: mac ? (light ? "#d8d8dc" : "#3a3a3c") : win ? (light ? Qt.rgba(0, 0, 0, 0.08) : Qt.rgba(1, 1, 1, 0.08)) : (light ? Qt.rgba(0, 0, 0, 0.1) : Qt.rgba(1, 1, 1, 0.1))

    readonly property color text: mac ? (light ? "#1d1d1f" : "#f5f5f7") : win ? (light ? "#1b1b1b" : "#ffffff") : (light ? Qt.rgba(0, 0, 0.02, 0.8) : "#ffffff")
    readonly property color sub: mac ? (light ? "#6e6e73" : "#98989d") : win ? (light ? "#5d5d5d" : "#c5c5c5") : (light ? Qt.rgba(0, 0, 0.02, 0.55) : Qt.rgba(1, 1, 1, 0.6))
    readonly property color faint: mac ? (light ? "#a1a1a6" : "#6e6e73") : win ? (light ? "#8a8a8a" : "#9d9d9d") : (light ? Qt.rgba(0, 0, 0.02, 0.4) : Qt.rgba(1, 1, 1, 0.4))

    readonly property color getBg: mac ? (light ? "#e8e8ed" : "#3a3a3c") : win ? accent : (light ? "#3584e4" : "#3584e4")
    readonly property color getBgHover: mac ? (light ? "#dcdce1" : "#464648") : win ? Qt.rgba(accent.r, accent.g, accent.b, 0.9) : "#3c8ce8"
    readonly property color getText: mac ? accentText : win ? onAccent : "#ffffff"
    readonly property color openBg: mac ? getBg : win ? (light ? "#fbfbfb" : "#373737") : (light ? Qt.rgba(0, 0, 0.02, 0.08) : Qt.rgba(1, 1, 1, 0.1))
    readonly property color openText: mac ? accentText : text

    readonly property color good: light ? "#248a3d" : "#30d158"
    readonly property color warn: light ? "#b25000" : "#ff9f0a"
    readonly property color bad: light ? "#d70015" : "#ff453a"
    readonly property color goodBg: light ? "#e3f4e8" : "#1c3524"
    readonly property color warnBg: light ? "#fff2df" : "#3a2a12"
    readonly property color badBg: light ? "#fde4e2" : "#41201d"

    readonly property int radius: mac ? 12 : win ? 8 : 12
    readonly property int controlRadius: mac ? 7 : win ? 4 : 6
    readonly property int iconRadius: mac ? 22 : win ? 8 : 16
    readonly property int titleSize: mac ? 26 : win ? 28 : 22
    readonly property int body: win ? 14 : 13
    readonly property int small: win ? 12 : 12
    readonly property int section: mac ? 19 : win ? 20 : 17

    function sourceName(s) {
        return { flathub: "Flathub", apt: "Debian", arch: "Arch Linux", aur: "AUR", agent: "KwickOS Agents", model: "Local AI" }[s] || s || ""
    }

    function sourceTint(s) {
        return { flathub: light ? "#2a6ad4" : "#5aa1ff", apt: light ? "#c70036" : "#ff5a7a", arch: light ? "#1478b8" : "#3ab0f0", aur: light ? "#b25000" : "#ff9f0a", agent: light ? "#8944ab" : "#bf5af2", model: light ? "#8944ab" : "#bf5af2" }[s] || sub
    }

    function readCfg(name) {
        const req = new XMLHttpRequest()
        req.open("GET", StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/kwick/" + name, false)
        try {
            req.send()
            return req.responseText.trim()
        } catch (e) {
            return ""
        }
    }

    Component.onCompleted: {
        const l = readCfg("layout")
        layout = ["macos", "windows", "linux"].indexOf(l) >= 0 ? l : "macos"
        light = readCfg("appearance") === "light"
    }
}
