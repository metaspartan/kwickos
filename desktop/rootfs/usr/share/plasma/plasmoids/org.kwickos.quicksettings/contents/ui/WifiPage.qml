import QtQuick
import org.kde.plasma.networkmanagement as PlasmaNM

SubPage {
    id: page

    title: "Wi-Fi"
    switchable: true
    on: !!qs && !!qs.net && qs.net.wifiOn
    link: "More Wi-Fi settings"
    empty: on ? "No networks found" : "Wi-Fi is turned off"
    onToggled: value => qs.net.setWifi(value)
    onLinkClicked: qs.open("kcmshell6 kcm_networkmanagement")

    PlasmaNM.Handler {
        id: handler
    }

    PlasmaNM.AppletProxyModel {
        id: networks
        sourceModel: PlasmaNM.NetworkModel {}
    }

    Repeater {
        model: page.on ? networks : null

        delegate: PageRow {
            required property var model
            readonly property bool connected: model.ConnectionState === PlasmaNM.Enums.Activated
            readonly property bool secured: model.SecurityType > PlasmaNM.Enums.NoneSecurity
            visible: model.Type === PlasmaNM.Enums.Wireless
            height: visible ? 52 : 0
            icon: "network-wireless-connected-" + (Math.round(model.Signal / 20) * 20 || "00") + "-symbolic"
            label: model.Name
            detail: connected ? (secured ? "Connected, secured" : "Connected")
                  : model.ConnectionState === PlasmaNM.Enums.Activating ? "Connecting…"
                  : secured ? "Secured" : "Open"
            active: connected
            onClicked: {
                if (connected)
                    handler.deactivateConnection(model.ConnectionPath, model.DevicePath)
                else if (model.Uuid)
                    handler.activateConnection(model.ConnectionPath, model.DevicePath, model.SpecificPath)
                else
                    handler.addAndActivateConnection(model.DevicePath, model.SpecificPath)
            }
        }
    }
}
