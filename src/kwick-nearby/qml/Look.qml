import QtQuick

QtObject {
    readonly property bool dark: Nearby.dark
    readonly property color accent: Nearby.accent
    readonly property color ink: dark ? "#ffffff" : "#000000"
    readonly property color label: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.92 : 0.86)
    readonly property color secondary: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.55 : 0.5)
    readonly property color tertiary: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.3 : 0.28)
    readonly property color hairline: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.1 : 0.09)
    readonly property color hover: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.08 : 0.05)
    readonly property color pressed: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.14 : 0.09)
    readonly property color window: dark ? "#1e1e1e" : "#f6f6f6"
    readonly property color toolbar: dark ? "#262626" : "#ededed"
    readonly property color panel: dark ? Qt.rgba(0.17, 0.17, 0.18, 0.98) : Qt.rgba(0.97, 0.97, 0.97, 0.99)
    readonly property color menu: dark ? Qt.rgba(0.2, 0.2, 0.21, 0.99) : Qt.rgba(0.99, 0.99, 0.99, 0.995)
    readonly property color field: dark ? "#2b2b2b" : "#ffffff"
    readonly property color border: dark ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(0, 0, 0, 0.12)
    readonly property color control: dark ? Qt.rgba(1, 1, 1, 0.14) : "#ffffff"
    readonly property color controlHover: dark ? Qt.rgba(1, 1, 1, 0.2) : "#f5f5f5"
    readonly property color controlPressed: dark ? Qt.rgba(1, 1, 1, 0.26) : "#e8e8e8"
    readonly property color good: dark ? "#30d158" : "#28a745"
    readonly property color bad: dark ? "#ff453a" : "#ff3b30"
    readonly property real ratio: Math.max(0.8, Math.min(1.3, Nearby.radius / 10))
    readonly property real radius: Math.round(12 * ratio)
    readonly property real small: Math.round(7 * ratio)
    readonly property string sans: "Inter"

    function avatarColors(type) {
        if (type === "mobile")
            return ["#5ad06b", "#1fa463"]
        if (type === "web")
            return ["#ffb340", "#f27c1b"]
        if (type === "server" || type === "headless")
            return ["#9a9aa1", "#5f5f66"]
        return ["#5aa9ff", "#2b6fe0"]
    }

    function deviceIcon(type) {
        if (type === "mobile")
            return "phone"
        if (type === "web")
            return "globe"
        if (type === "server")
            return "server"
        if (type === "headless")
            return "terminal"
        return "laptop"
    }
}
