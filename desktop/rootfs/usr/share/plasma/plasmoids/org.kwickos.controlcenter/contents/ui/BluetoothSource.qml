import QtQuick
import org.kde.bluezqt as BluezQt

QtObject {
    id: bt

    readonly property var manager: BluezQt.Manager
    readonly property bool available: manager.adapters.length > 0
    readonly property bool on: manager.bluetoothOperational
    property int revision: 0
    readonly property var devices: {
        revision
        const list = []
        for (let i = 0; i < manager.devices.length; i++) {
            const d = manager.devices[i]
            if (d.paired)
                list.push({
                    device: d,
                    name: d.name || d.address,
                    connected: d.connected,
                    battery: d.battery ? d.battery.percentage : -1,
                    icon: d.icon || "bluetooth-active"
                })
        }
        return list.sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))
    }
    readonly property int connected: devices.filter(d => d.connected).length

    function setOn(value) {
        manager.bluetoothBlocked = !value
        for (let i = 0; i < manager.adapters.length; i++)
            manager.adapters[i].powered = value
    }

    function toggle(entry) {
        if (entry.connected)
            entry.device.disconnectFromDevice()
        else
            entry.device.connectToDevice()
    }

    property Connections watcher: Connections {
        target: bt.manager
        function onDeviceAdded() { bt.revision++ }
        function onDeviceRemoved() { bt.revision++ }
        function onDeviceChanged() { bt.revision++ }
        function onAdapterChanged() { bt.revision++ }
    }
}
