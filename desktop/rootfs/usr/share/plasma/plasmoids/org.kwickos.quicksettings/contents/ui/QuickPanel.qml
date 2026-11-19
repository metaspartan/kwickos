import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "file:///usr/share/kwick/qml/fluent"

FocusScope {
    id: panel

    required property var qs
    required property var battery
    property string page: ""
    readonly property bool hasBattery: battery.hasInternalBatteries

    width: 360
    height: page === "" ? main.implicitHeight : 420
    Keys.onEscapePressed: page !== "" ? page = "" : qs.close()

    ColumnLayout {
        id: main
        visible: panel.page === ""
        width: parent.width
        spacing: 0

        MediaCard {
            Layout.fillWidth: true
            media: panel.qs.media
            visible: !!panel.qs.media && panel.qs.media.active
        }

        Grid {
            Layout.leftMargin: 24
            Layout.topMargin: 24
            columns: 3
            columnSpacing: 12
            rowSpacing: 8

            QuickTile {
                label: panel.qs.net && panel.qs.net.wifiName ? panel.qs.net.wifiName : "Wi-Fi"
                icon: panel.qs.net && panel.qs.net.wifiOn ? "network-wireless-connected-100-symbolic" : "network-wireless-disconnected-symbolic"
                available: !!panel.qs.net && panel.qs.net.wifiAvailable
                on: available && panel.qs.net.wifiOn
                split: true
                onToggled: panel.qs.net.setWifi(!on)
                onExpand: panel.page = "wifi"
            }

            QuickTile {
                label: "Bluetooth"
                icon: on ? "bluetooth-active-symbolic" : "bluetooth-disabled-symbolic"
                available: !!panel.qs.bt && panel.qs.bt.available
                on: available && panel.qs.bt.on
                split: true
                onToggled: panel.qs.bt.setOn(!on)
                onExpand: panel.page = "bluetooth"
            }

            QuickTile {
                label: "VPN"
                icon: "network-vpn-symbolic"
                on: panel.qs.vpnUp.length > 0
                split: true
                onToggled: panel.qs.toggleVpn()
                onExpand: panel.page = "vpn"
            }

            QuickTile {
                label: "Airplane mode"
                icon: "network-flightmode-on-symbolic"
                on: panel.qs.airplane
                onToggled: panel.qs.setAirplane(!on)
            }

            QuickTile {
                label: "Energy saver"
                icon: "battery-profile-power-saver-symbolic"
                on: panel.qs.saver
                onToggled: panel.qs.setSaver(!on)
            }

            QuickTile {
                label: "Night light"
                icon: "night-light-symbolic"
                on: !!panel.qs.display && panel.qs.display.nightOn
                onToggled: panel.qs.toggleNight()
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.topMargin: 12
            Layout.preferredHeight: 40
            visible: !!panel.qs.display && panel.qs.display.available

            Kirigami.Icon {
                x: 32
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                source: "brightness-high-symbolic"
                isMask: true
                color: Fluent.text
            }

            FluentSlider {
                x: 60
                width: parent.width - 60 - 64
                anchors.verticalCenter: parent.verticalCenter
                value: panel.qs.display ? panel.qs.display.value : 0
                onMoved: v => panel.qs.display.setValue(Math.max(0.05, v))
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.preferredHeight: 40
            visible: !!panel.qs.sound && panel.qs.sound.available

            IconButton {
                x: 24
                anchors.verticalCenter: parent.verticalCenter
                icon: panel.qs.sound ? panel.qs.sound.icon : ""
                onClicked: panel.qs.sound.toggleMute()
            }

            FluentSlider {
                x: 60
                width: parent.width - 60 - 64
                anchors.verticalCenter: parent.verticalCenter
                value: panel.qs.sound && !panel.qs.sound.muted ? panel.qs.sound.value : 0
                onMoved: v => panel.qs.sound.setValue(v)
            }

            IconButton {
                anchors.right: parent.right
                anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                icon: "arrow-right"
                iconSize: 12
                onClicked: panel.page = "sound"
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 16
            Layout.preferredHeight: 48
            color: Fluent.footer
            radius: Fluent.overlayRadius - 1

            Rectangle {
                width: parent.width
                height: parent.radius
                color: parent.color
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Fluent.divider
            }

            Row {
                x: 24
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                visible: panel.hasBattery

                Kirigami.Icon {
                    width: 16
                    height: 16
                    source: panel.battery.pluggedIn ? "battery-100-charging-symbolic" : "battery-" + ("00" + Math.round(panel.battery.percent / 10) * 10).slice(-3) + "-symbolic"
                    isMask: true
                    color: Fluent.text
                }

                FluentText {
                    text: panel.battery.percent + "%"
                    font.pixelSize: Fluent.caption
                }
            }

            IconButton {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                icon: "configure-symbolic"
                onClicked: panel.qs.open("kwick-settings")
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: panel.page !== ""
        source: panel.page === "" ? "" : panel.page.charAt(0).toUpperCase() + panel.page.slice(1) + "Page.qml"
        onLoaded: {
            item.qs = panel.qs
            item.back.connect(() => panel.page = "")
        }
    }
}
