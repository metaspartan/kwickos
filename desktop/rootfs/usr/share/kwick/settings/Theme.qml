pragma Singleton
import QtQuick
import QtCore

QtObject {
    property color accent: light ? "#ff9500" : "#ff9f0a"
    property color selection: light ? "#e17b00" : "#d06f00"
    readonly property color textSelection: Qt.rgba(accent.r, accent.g, accent.b, light ? 0.3 : 0.4)
    property bool light: false
    readonly property color bg: light ? "#f5f5f5" : "#1e1e1e"
    readonly property color sidebar: light ? "#e8e8e8" : "#282828"
    readonly property color card: light ? "#ffffff" : "#292929"
    readonly property color cardHi: light ? "#f0f0f0" : "#343434"
    readonly property color field: light ? "#ffffff" : "#363636"
    readonly property color popup: light ? "#f6f6f6" : "#323232"
    readonly property color control: light ? "#ffffff" : "#3fffffff"
    readonly property color controlHover: light ? "#f7f7f7" : "#4cffffff"
    readonly property color controlPressed: light ? "#ebebeb" : "#59ffffff"
    readonly property color controlText: light ? "#d8000000" : "#ffffff"
    readonly property color track: light ? "#d9d9d9" : "#464646"
    readonly property color hover: light ? "#0f000000" : "#19ffffff"
    readonly property color line: light ? "#19000000" : "#19ffffff"
    readonly property color lineStrong: light ? "#26000000" : "#26ffffff"
    readonly property color text: light ? "#d8000000" : "#d8ffffff"
    readonly property color sub: light ? "#8c000000" : "#8cffffff"
    readonly property color faint: light ? "#3f000000" : "#3fffffff"
    readonly property color good: light ? "#28cd41" : "#32d74b"
    readonly property color warn: light ? "#ff9500" : "#ff9f0a"
    readonly property color bad: light ? "#ff3b30" : "#ff453a"
    readonly property color goodBg: light ? "#dcf5e1" : "#1e3a28"
    readonly property color warnBg: light ? "#fff1d6" : "#2e2412"
    readonly property color badBg: light ? "#fde3e1" : "#40201e"
    readonly property color warnText: light ? "#7a4a00" : "#f5d9a8"
    readonly property string sans: "Inter"
    readonly property string mono: "JetBrains Mono"

    Component.onCompleted: {
        const req = new XMLHttpRequest()
        req.open("GET", StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/kwick/appearance", false)
        req.send()
        light = req.responseText.trim() === "light"
    }
}
