pragma Singleton
import QtQuick

QtObject {
    property bool dark: true
    property color accent: "#0a84ff"
    readonly property color accentPressed: Qt.darker(accent, 1.18)
    readonly property color accentHover: Qt.lighter(accent, 1.08)
    readonly property color accentSoft: Qt.rgba(accent.r, accent.g, accent.b, dark ? 0.22 : 0.14)
    readonly property color focusRing: Qt.rgba(accent.r, accent.g, accent.b, 0.55)

    readonly property color bg: dark ? "#1c1c1f" : "#f5f5f7"
    readonly property color bgTop: dark ? "#222227" : "#fbfbfd"
    readonly property color card: dark ? "#28282d" : "#ffffff"
    readonly property color cardHi: dark ? "#323238" : "#f2f2f5"
    readonly property color field: dark ? "#2f2f35" : "#ffffff"
    readonly property color fieldLine: dark ? "#24ffffff" : "#26000000"
    readonly property color line: dark ? "#14ffffff" : "#12000000"
    readonly property color lineStrong: dark ? "#26ffffff" : "#22000000"
    readonly property color hover: dark ? "#0dffffff" : "#08000000"
    readonly property color pressed: dark ? "#1affffff" : "#12000000"
    readonly property color button: dark ? "#3a3a40" : "#ffffff"
    readonly property color buttonHover: dark ? "#44444b" : "#f4f4f6"
    readonly property color buttonPressed: dark ? "#505057" : "#e6e6ea"
    readonly property color segBg: dark ? "#323238" : "#e4e4e9"
    readonly property color segOn: dark ? "#5b5b62" : "#ffffff"
    readonly property color track: dark ? "#3a3a41" : "#e1e1e6"
    readonly property color knobOff: dark ? "#48484f" : "#e2e2e7"

    readonly property color text: dark ? "#f5f5f7" : "#1d1d1f"
    readonly property color sub: dark ? "#a1a1a8" : "#6e6e73"
    readonly property color faint: dark ? "#6c6c72" : "#a1a1a6"
    readonly property color accentText: "#ffffff"

    readonly property color good: dark ? "#30d158" : "#28b14c"
    readonly property color warn: dark ? "#ff9f0a" : "#e08600"
    readonly property color bad: dark ? "#ff453a" : "#e5372c"
    readonly property color badPressed: Qt.darker(bad, 1.15)
    readonly property color shadow: dark ? "#80000000" : "#30000000"
    readonly property color scrim: dark ? "#8c000000" : "#4d000000"

    readonly property string sans: "Inter"
    readonly property string mono: "JetBrains Mono"

    readonly property int titleSize: 30
    readonly property int heroSize: 40
    readonly property int subtitleSize: 15
    readonly property int bodySize: 14
    readonly property int smallSize: 12
    readonly property int radius: 12
    readonly property int controlHeight: 36
    readonly property int contentWidth: 600
    readonly property int motion: 320
}
