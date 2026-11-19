import QtQuick

SubPage {
    id: page

    title: "Bluetooth"
    switchable: !!qs && !!qs.bt && qs.bt.available
    on: switchable && qs.bt.on
    link: "More Bluetooth settings"
    empty: !switchable ? "No Bluetooth adapter" : !on ? "Bluetooth is turned off" : "No paired devices"
    onToggled: value => qs.bt.setOn(value)
    onLinkClicked: qs.open("kwick-bluetooth settings")

    Repeater {
        model: page.on ? page.qs.bt.devices : []

        delegate: PageRow {
            required property var modelData
            icon: modelData.icon + "-symbolic"
            label: modelData.name
            detail: modelData.connected ? "Connected" + (modelData.battery >= 0 ? ", battery " + modelData.battery + "%" : "") : "Paired"
            active: modelData.connected
            onClicked: page.qs.bt.toggle(modelData)
        }
    }
}
