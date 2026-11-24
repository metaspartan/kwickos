pragma Singleton
import QtQuick
import QtCore

QtObject {
    property var colors: ({})
    readonly property var scheme: colors[light ? "light" : "dark"] || ({})
    readonly property color accent: scheme.accent || (light ? "#ff9500" : "#ff9f0a")
    readonly property color fill: scheme.fill || (light ? "#d97f00" : "#d28308")
    readonly property color fillHover: scheme.hover || (light ? "#c87500" : "#c17907")
    readonly property color fillPressed: scheme.pressed || (light ? "#b66b00" : "#b06e07")
    readonly property color accentText: scheme.text || (light ? "#9c5b00" : "#ff9f0a")
    readonly property color selection: scheme.selected || (light ? "#e07a00" : "#d06f00")
    readonly property color selectionText: scheme.selectedtext || "#ffffff"
    readonly property color textSelection: scheme.textsel || (light ? "#ffdfb3" : "#896b42")
    readonly property bool sidebarNeutral: (colors.sidebarSelection || "neutral") === "neutral"
    readonly property color sidebarSelection: sidebarNeutral ? (light ? "#14000000" : "#1affffff") : selection
    readonly property color sidebarSelectionText: sidebarNeutral ? text : selectionText
    readonly property bool tint: colors.tint === true
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
    readonly property color info: light ? "#007aff" : "#0a84ff"
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
        const cr = new XMLHttpRequest()
        cr.open("GET", StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/kwick/colors.json", false)
        try {
            cr.send()
            colors = JSON.parse(cr.responseText)
        } catch (e) {
        }
    }
}
