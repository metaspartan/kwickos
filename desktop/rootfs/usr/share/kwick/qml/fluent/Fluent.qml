pragma Singleton
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    readonly property bool dark: Kirigami.Theme.backgroundColor.hslLightness < 0.5
    readonly property string family: Kirigami.Theme.defaultFont.family

    readonly property color text: dark ? "#ffffff" : Qt.rgba(0, 0, 0, 0.894)
    readonly property color text2: dark ? Qt.rgba(1, 1, 1, 0.786) : Qt.rgba(0, 0, 0, 0.62)
    readonly property color text3: dark ? Qt.rgba(1, 1, 1, 0.545) : Qt.rgba(0, 0, 0, 0.447)
    readonly property color textDisabled: dark ? Qt.rgba(1, 1, 1, 0.364) : Qt.rgba(0, 0, 0, 0.361)

    readonly property color accent: dark ? "#60cdff" : "#005fb8"
    readonly property color accentHover: dark ? Qt.rgba(0.376, 0.804, 1, 0.9) : Qt.rgba(0, 0.373, 0.722, 0.9)
    readonly property color accentPressed: dark ? Qt.rgba(0.376, 0.804, 1, 0.8) : Qt.rgba(0, 0.373, 0.722, 0.8)
    readonly property color onAccent: dark ? "#000000" : "#ffffff"

    readonly property color subtleHover: dark ? Qt.rgba(1, 1, 1, 0.061) : Qt.rgba(0, 0, 0, 0.037)
    readonly property color subtlePressed: dark ? Qt.rgba(1, 1, 1, 0.042) : Qt.rgba(0, 0, 0, 0.024)
    readonly property color control: dark ? Qt.rgba(1, 1, 1, 0.061) : Qt.rgba(1, 1, 1, 0.7)
    readonly property color controlHover: dark ? Qt.rgba(1, 1, 1, 0.084) : Qt.rgba(0.976, 0.976, 0.976, 0.5)
    readonly property color controlPressed: dark ? Qt.rgba(1, 1, 1, 0.033) : Qt.rgba(0.976, 0.976, 0.976, 0.3)
    readonly property color controlStroke: dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.059)
    readonly property color strongStroke: dark ? Qt.rgba(1, 1, 1, 0.545) : Qt.rgba(0, 0, 0, 0.447)
    readonly property color card: dark ? Qt.rgba(1, 1, 1, 0.051) : Qt.rgba(1, 1, 1, 0.7)
    readonly property color cardStroke: dark ? Qt.rgba(0, 0, 0, 0.1) : Qt.rgba(0, 0, 0, 0.059)
    readonly property color divider: dark ? Qt.rgba(1, 1, 1, 0.082) : Qt.rgba(0, 0, 0, 0.059)
    readonly property color footer: dark ? Qt.rgba(0, 0, 0, 0.14) : Qt.rgba(0, 0, 0, 0.035)
    readonly property color textBox: dark ? Qt.rgba(0, 0, 0, 0.3) : Qt.rgba(1, 1, 1, 0.7)
    readonly property color sliderTrack: dark ? Qt.rgba(1, 1, 1, 0.545) : Qt.rgba(0, 0, 0, 0.447)
    readonly property color thumb: dark ? "#454545" : "#ffffff"
    readonly property color menu: dark ? "#2c2c2c" : "#f9f9f9"

    readonly property int radius: 4
    readonly property int overlayRadius: 8
    readonly property int gap: 12
    readonly property int caption: 12
    readonly property int body: 14
    readonly property int subtitle: 20
}
