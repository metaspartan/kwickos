import QtQuick
import org.kde.plasma.networkmanagement as PlasmaNM

Item {
    id: net

    property string wifiName: ""
    property string wiredName: ""
    property bool wifiDevice: false
    readonly property bool wifiAvailable: wifiDevice && enabled.wirelessHwEnabled
    readonly property bool wifiOn: enabled.wirelessEnabled

    function setWifi(on) {
        handler.enableWireless(on)
    }

    function rebuild() {
        let wifi = ""
        let wired = ""
        let device = false
        for (let i = 0; i < rows.count; i++) {
            const row = rows.objectAt(i)
            if (!row)
                continue
            device = device || row.kind === PlasmaNM.Enums.Wireless
            if (!row.active)
                continue
            if (row.kind === PlasmaNM.Enums.Wireless && !wifi)
                wifi = row.name
            else if (row.kind === PlasmaNM.Enums.Wired && !wired)
                wired = row.name
        }
        wifiName = wifi
        wiredName = wired
        wifiDevice = device
    }

    PlasmaNM.EnabledConnections {
        id: enabled
    }

    PlasmaNM.Handler {
        id: handler
    }

    Instantiator {
        id: rows
        model: PlasmaNM.NetworkModel {}
        delegate: QtObject {
            readonly property int kind: model.Type
            readonly property string name: model.Name
            readonly property bool active: model.ConnectionState === PlasmaNM.Enums.Activated
            onActiveChanged: Qt.callLater(net.rebuild)
            onNameChanged: Qt.callLater(net.rebuild)
        }
        onObjectAdded: Qt.callLater(net.rebuild)
        onObjectRemoved: Qt.callLater(net.rebuild)
    }
}
