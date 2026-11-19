import QtQuick
import org.kde.plasma.private.brightnesscontrolplugin

Item {
    id: display

    readonly property bool available: screens.isBrightnessAvailable && list.count > 0
    readonly property real value: list.count > 0 && list.itemAt(0) ? list.itemAt(0).level : 0
    readonly property bool nightAvailable: night.available
    readonly property bool nightOn: night.enabled && !night.inhibited

    signal enableNight()

    function setValue(v) {
        const row = list.itemAt(0)
        if (row)
            screens.setBrightness(row.displayName, Math.round(v * row.maxBrightness))
    }

    function toggleNight() {
        if (night.enabled)
            night.toggleInhibition()
        else
            display.enableNight()
    }

    ScreenBrightnessControl {
        id: screens
        isSilent: true
    }

    NightLightControl {
        id: night
    }

    Repeater {
        id: list
        model: screens.displays
        delegate: Item {
            required property string displayName
            required property int brightness
            required property int maxBrightness
            readonly property real level: maxBrightness > 0 ? brightness / maxBrightness : 0
        }
    }
}
