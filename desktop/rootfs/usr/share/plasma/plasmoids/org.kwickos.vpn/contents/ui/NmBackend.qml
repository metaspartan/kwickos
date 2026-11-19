import QtQuick
import org.kde.plasma.networkmanagement as PlasmaNM

Item {
    id: nm

    property var profiles: []
    readonly property var states: ["disconnected", "connecting", "connected", "disconnecting", "disconnected"]

    function rebuild() {
        const seen = {}
        const list = []
        for (let i = 0; i < rows.count; i++) {
            const row = rows.objectAt(i)
            if (row && row.vpn && !seen[row.profile.id]) {
                seen[row.profile.id] = true
                list.push(row.profile)
            }
        }
        profiles = list.sort((a, b) => a.name.localeCompare(b.name))
    }

    function address(details) {
        const pairs = details || []
        for (let i = 0; i + 1 < pairs.length; i += 2) {
            if (/^IPv4 Address$/i.test(pairs[i]))
                return pairs[i + 1]
        }
        return ""
    }

    Instantiator {
        id: rows
        model: PlasmaNM.NetworkModel {}
        delegate: QtObject {
            readonly property bool plugin: model.Type === PlasmaNM.Enums.Vpn
            readonly property bool vpn: plugin || model.ConnectionIcon === "network-vpn"
            readonly property var profile: ({
                id: model.Uuid,
                name: model.Name,
                type: plugin ? model.VpnType : "wireguard",
                state: nm.states[model.ConnectionState] || "disconnected",
                ip: plugin ? "" : nm.address(model.ConnectionDetails),
                since: model.ConnectionState === PlasmaNM.Enums.Activated && model.TimeStamp ? model.TimeStamp.getTime() : 0
            })
            onProfileChanged: if (vpn) Qt.callLater(nm.rebuild)
        }
        onObjectAdded: Qt.callLater(nm.rebuild)
        onObjectRemoved: Qt.callLater(nm.rebuild)
    }
}
