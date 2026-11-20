import QtQuick
import org.kde.plasma.private.volume

SubPage {
    id: page

    title: "Sound output"
    link: "More volume settings"
    empty: "No output devices"
    onLinkClicked: qs.open("kcmshell6 kcm_pulseaudio || systemsettings kcm_pulseaudio")

    Repeater {
        model: SinkModel {}

        delegate: PageRow {
            required property var model
            visible: model.Name !== "auto_null"
            height: visible ? 40 : 0
            icon: "audio-speakers-symbolic"
            label: model.Description
            active: model.Default
            onClicked: model.PulseObject.default = true
        }
    }
}
