import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.networkmanagement as PlasmaNM
import org.kde.plasma.private.batterymonitor
import org.kde.plasma.private.battery
import org.kde.kirigami as Kirigami
import "file:///usr/share/kwick/qml/fluent"

PlasmoidItem {
    id: root

    readonly property string cc: "file:///usr/share/plasma/plasmoids/org.kwickos.controlcenter/contents/ui/"
    readonly property string vpnDir: "file:///usr/share/plasma/plasmoids/org.kwickos.vpn/contents/ui/"
    readonly property var net: make(cc + "NetworkSource.qml")
    readonly property var bt: make(cc + "BluetoothSource.qml")
    readonly property var display: make(cc + "DisplaySource.qml")
    readonly property var sound: make(cc + "SoundSource.qml")
    readonly property var media: make(cc + "PlayerSource.qml")
    readonly property var vpn: make(vpnDir + "NmBackend.qml")
    readonly property var vpnExec: make(vpnDir + "Exec.qml")
    readonly property var vpnProfiles: vpn ? vpn.profiles : []
    readonly property var vpnUp: vpnProfiles.filter(p => p.state === "connected" || p.state === "connecting")
    readonly property bool airplane: PlasmaNM.Configuration.airplaneModeEnabled
    readonly property bool saver: profiles.activeProfile === "power-saver"
    readonly property string netIcon: airplane ? "network-flightmode-on"
        : net && net.wifiName ? "network-wireless-connected-100"
        : net && net.wiredName ? "network-wired-activated"
        : "network-offline"

    function make(url) {
        const c = Qt.createComponent(url)
        if (c.status !== Component.Ready) {
            console.warn("quicksettings:", c.errorString())
            return null
        }
        return c.createObject(root)
    }

    function run(cmd) {
        exec.connectSource(cmd)
    }

    function close() {
        flyout.visible = false
    }

    function open(cmd) {
        close()
        run(cmd)
    }

    function setSaver(on) {
        profiles.setProfile(on ? "power-saver" : profiles.configuredProfile || "balanced")
    }

    function setVpn(id, on) {
        if (vpnExec)
            vpnExec.run("kwick-vpn " + (on ? "up " : "down ") + vpnExec.quote(id) + " 2>&1")
    }

    function toggleVpn() {
        if (vpnUp.length > 0)
            vpnUp.forEach(p => setVpn(p.id, false))
        else if (vpnProfiles.length > 0)
            setVpn(vpnProfiles[0].id, true)
        else
            panel.page = "vpn"
    }

    function setAirplane(on) {
        handler.enableAirplaneMode(on)
        PlasmaNM.Configuration.airplaneModeEnabled = on
    }

    function toggleNight() {
        if (!display)
            return
        if (display.nightAvailable)
            display.toggleNight()
        else
            enableNight()
    }

    function enableNight() {
        run("kwriteconfig6 --file kwinrc --group NightColor --key Active true")
        run("kwriteconfig6 --file kwinrc --group NightColor --key Mode Constant")
        reconfigure.start()
    }

    preferredRepresentation: compactRepresentation
    fullRepresentation: Item {}
    Plasmoid.icon: "systemsettings-quick-settings"
    Plasmoid.title: "Quick Settings"
    toolTipMainText: flyout.visible ? "" : net && net.wifiName ? net.wifiName : net && net.wiredName ? "Ethernet" : "Not connected"
    toolTipSubText: sound && sound.available ? "Volume " + Math.round(sound.value * 100) + "%" : ""

    P5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: source => disconnectSource(source)
    }

    PlasmaNM.Handler {
        id: handler
    }

    PowerProfilesControl {
        id: profiles
    }

    BatteryControlModel {
        id: battery
    }

    Timer {
        id: reconfigure
        interval: 300
        onTriggered: root.run("qdbus6 org.kde.KWin /KWin reconfigure")
    }

    Connections {
        target: root.display
        function onEnableNight() {
            root.enableNight()
        }
    }

    compactRepresentation: TaskbarButton {
        open: flyout.visible
        onClicked: flyout.toggle()
        onWheel: wheel => {
            if (root.sound)
                root.sound.setValue(root.sound.value + (wheel.angleDelta.y > 0 ? 0.02 : -0.02))
        }
        Component.onCompleted: flyout.anchorItem = this

        Row {
            spacing: 8

            Repeater {
                model: [root.vpnUp.length > 0 ? "network-vpn" : root.netIcon,
                        root.sound ? root.sound.icon.replace("-symbolic", "") : "audio-volume-high",
                        battery.hasInternalBatteries ? (battery.pluggedIn ? "battery-100-charging" : "battery-" + ("00" + Math.round(battery.percent / 10) * 10).slice(-3)) : ""]

                delegate: Kirigami.Icon {
                    required property string modelData
                    visible: modelData !== ""
                    width: 16
                    height: 16
                    source: modelData + "-symbolic"
                    isMask: true
                    color: Fluent.text
                }
            }
        }
    }

    Flyout {
        id: flyout
        onVisibleChanged: if (visible) panel.page = ""
        mainItem: QuickPanel {
            id: panel
            qs: root
            battery: battery
        }
    }
}
