import QtQuick
import "file:///usr/share/kwick/qml/fluent"

SubPage {
    id: page

    title: "VPN"
    link: "VPN settings"
    empty: "No VPN connections"
    onLinkClicked: qs.open("kwick-settings vpn")

    Repeater {
        model: page.qs ? page.qs.vpnProfiles : []

        delegate: PageRow {
            id: row
            required property var modelData
            readonly property bool up: modelData.state === "connected"
            icon: "network-vpn-symbolic"
            label: modelData.name
            detail: up ? "Connected" + (modelData.ip ? ", " + modelData.ip : "") : modelData.state === "connecting" ? "Connecting…" : "Not connected"
            active: up
            onClicked: page.qs.setVpn(modelData.id, !up)

            Toggle {
                checked: row.up || row.modelData.state === "connecting"
                onToggled: value => page.qs.setVpn(row.modelData.id, value)
            }
        }
    }
}
