import QtQuick
import KwickCapture

QtObject {
    readonly property bool dark: Capture.dark
    readonly property color accent: Capture.accent
    readonly property color ink: dark ? "#ffffff" : "#000000"
    readonly property color label: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.92 : 0.86)
    readonly property color secondary: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.55 : 0.5)
    readonly property color tertiary: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.3 : 0.28)
    readonly property color hairline: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.1 : 0.09)
    readonly property color hover: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.09 : 0.055)
    readonly property color pressed: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.15 : 0.1)
    readonly property color selected: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.17 : 0.1)
    readonly property color panel: dark ? Qt.rgba(0.14, 0.14, 0.15, 0.97) : Qt.rgba(0.965, 0.965, 0.965, 0.98)
    readonly property color menu: dark ? Qt.rgba(0.17, 0.17, 0.18, 0.98) : Qt.rgba(0.975, 0.975, 0.975, 0.99)
    readonly property color border: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(0, 0, 0, 0.12)
    readonly property color window: dark ? "#1e1e1e" : "#f5f5f5"
    readonly property color toolbar: dark ? "#2a2a2a" : "#ececec"
    readonly property color card: dark ? "#292929" : "#ffffff"
    readonly property color field: dark ? "#363636" : "#ffffff"
    readonly property color control: dark ? Qt.rgba(1, 1, 1, 0.16) : "#ffffff"
    readonly property color controlHover: dark ? Qt.rgba(1, 1, 1, 0.22) : "#f7f7f7"
    readonly property color danger: dark ? "#ff453a" : "#ff3b30"
    readonly property real ratio: Math.max(0.8, Math.min(1.3, Capture.radius / 10))
    readonly property real radius: Math.round(12 * ratio)
    readonly property real small: Math.round(7 * ratio)
    readonly property string sans: "Inter"
    readonly property string mono: "JetBrains Mono"

    function icon(name, tint) {
        return "image://capture/icon/" + name + "/" + tint.toString().substring(1)
    }
}
