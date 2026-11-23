import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as P5Support
import org.kde.notificationmanager as NotificationManager
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property var net: netSource.item
    readonly property var bt: btSource.item
    readonly property var display: displaySource.item
    readonly property var sound: soundSource.item
    readonly property var media: playerSource.item
    readonly property var nearby: nearbySource.item
    property double now: Date.now()
    property string page: ""
    readonly property bool focusOn: {
        const until = focusSettings.notificationsInhibitedUntil
        return (!isNaN(until.getTime()) && until.getTime() > now) || focusSettings.notificationsInhibitedByApplication
    }

    function run(cmd) {
        exec.connectSource(cmd)
    }

    function settings(module) {
        root.expanded = false
        run("kcmshell6 " + module + " || systemsettings " + module)
    }

    function setFocus(on) {
        if (on) {
            const until = new Date()
            until.setFullYear(until.getFullYear() + 1)
            focusSettings.notificationsInhibitedUntil = until
        } else {
            focusSettings.notificationsInhibitedUntil = undefined
            focusSettings.revokeApplicationInhibitions()
        }
        focusSettings.save()
        now = Date.now()
    }

    function enableNight() {
        run("kwriteconfig6 --notify --file kwinrc --group NightColor --key Mode Constant; kwriteconfig6 --notify --file kwinrc --group NightColor --key Active true")
    }

    Plasmoid.icon: "kwick-controlcenter-symbolic"
    Plasmoid.title: "Control Center"
    toolTipMainText: "Control Center"
    toolTipSubText: ""
    onExpandedChanged: {
        now = Date.now()
        if (!root.expanded)
            page = ""
        else if (root.nearby)
            root.nearby.refresh()
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: source => disconnectSource(source)
    }

    NotificationManager.Settings {
        id: focusSettings
    }

    Loader { id: netSource; source: "NetworkSource.qml" }
    Loader { id: btSource; source: "BluetoothSource.qml" }
    Loader { id: displaySource; source: "DisplaySource.qml" }
    Loader { id: soundSource; source: "SoundSource.qml" }
    Loader { id: playerSource; source: "PlayerSource.qml" }
    Loader { id: nearbySource; source: "NearbySource.qml"; onLoaded: item.watching = Qt.binding(() => root.expanded) }

    Connections {
        target: root.display
        function onEnableNight() {
            root.enableNight()
        }
    }

    compactRepresentation: MouseArea {
        id: compact
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded

        Kirigami.Icon {
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.smallMedium
            height: width
            source: "kwick-controlcenter-symbolic"
            isMask: true
            color: Kirigami.Theme.textColor
        }
    }

    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 17
        Layout.preferredWidth: Layout.minimumWidth
        Layout.maximumWidth: Layout.minimumWidth
        Layout.minimumHeight: (root.page === "nearby" ? nearbyDetail : root.page ? detail : panel).implicitHeight
        Layout.preferredHeight: Layout.minimumHeight
        Layout.maximumHeight: Layout.minimumHeight

        BluetoothPage {
            id: detail
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            visible: root.page === "bluetooth"
            bt: root.bt
            onBack: root.page = ""
            onOpenSettings: {
                root.expanded = false
                root.run("kwick-bluetooth settings")
            }
        }

        NearbyPage {
            id: nearbyDetail
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            visible: root.page === "nearby"
            nearby: root.nearby
            onBack: root.page = ""
            onShare: {
                root.expanded = false
                root.run("kwick-nearby --choose")
            }
            onOpenSettings: {
                root.expanded = false
                root.run("sh -c 'KWICK_SETTINGS_PAGE=nearby exec kwick-settings'")
            }
        }

        ColumnLayout {
            id: panel
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            visible: root.page === ""
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Tile {
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true

                    ToggleRow {
                        visible: !!root.net && root.net.wifiAvailable
                        icon: "network-wireless-symbolic"
                        title: "Wi-Fi"
                        on: !!root.net && root.net.wifiOn
                        subtitle: !root.net ? "" : root.net.wifiName || (root.net.wifiOn ? "On" : "Off")
                        onClicked: root.net.setWifi(!root.net.wifiOn)
                    }
                    ToggleRow {
                        visible: !!root.bt
                        icon: "bluetooth-active-symbolic"
                        title: "Bluetooth"
                        hasDetails: true
                        on: !!root.bt && root.bt.on
                        subtitle: !root.bt ? "" : !root.bt.available ? "Not Available" : !root.bt.on ? "Off" : root.bt.connected > 0 ? root.bt.connected + " Connected" : "On"
                        onClicked: if (root.bt.available) root.bt.setOn(!root.bt.on)
                        onDetails: root.page = "bluetooth"
                    }
                    ToggleRow {
                        visible: !!root.nearby && root.nearby.available
                        icon: "kwick-nearby-symbolic"
                        title: "Nearby Share"
                        hasDetails: true
                        on: !!root.nearby && root.nearby.on
                        subtitle: root.nearby ? root.nearby.subtitle : ""
                        onClicked: root.nearby.toggle()
                        onDetails: root.page = "nearby"
                    }
                    ToggleRow {
                        icon: "network-wired-symbolic"
                        title: "Network"
                        on: !!root.net && root.net.wiredName !== ""
                        subtitle: !root.net ? "" : root.net.wiredName !== "" ? "Connected" : "Not Connected"
                        onClicked: root.settings("kcm_networkmanagement")
                    }
                }

                ColumnLayout {
                    Layout.preferredWidth: 1
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    Tile {
                        Layout.fillHeight: true
                        ToggleRow {
                            icon: "night-light-symbolic"
                            title: "Focus"
                            on: root.focusOn
                            subtitle: root.focusOn ? "Do Not Disturb" : ""
                            onClicked: root.setFocus(!root.focusOn)
                        }
                    }

                    Tile {
                        Layout.fillHeight: true
                        visible: !!root.display && root.display.nightAvailable
                        ToggleRow {
                            icon: "redshift-status-day-symbolic"
                            title: "Night Light"
                            on: !!root.display && root.display.nightOn
                            onClicked: root.display.toggleNight()
                        }
                    }
                }
            }

            SliderTile {
                visible: !!root.display && root.display.available
                title: "Display"
                icon: "brightness-high-symbolic"
                value: root.display ? root.display.value : 0
                onMoved: v => root.display.setValue(Math.max(0.05, v))
            }

            SliderTile {
                title: "Sound"
                icon: root.sound ? root.sound.icon : "audio-volume-muted-symbolic"
                value: root.sound && !root.sound.muted ? root.sound.value : 0
                barActive: !!root.sound && root.sound.available
                onMoved: v => root.sound.setValue(v)
                onIconClicked: root.sound.toggleMute()
            }

            Tile {
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        implicitWidth: 40
                        implicitHeight: 40
                        radius: 8
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
                        clip: true

                        Image {
                            anchors.fill: parent
                            visible: status === Image.Ready
                            source: root.media && root.media.active ? root.media.art : ""
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 80
                            sourceSize.height: 80
                        }

                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: 22
                            height: 22
                            visible: !(root.media && root.media.active && root.media.art)
                            source: root.media && root.media.active && root.media.appIcon ? root.media.appIcon : "media-playback-start-symbolic"
                            opacity: root.media && root.media.active ? 1 : 0.45
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: root.media && root.media.active ? (root.media.track || root.media.identity) : "Not Playing"
                            font.weight: Font.DemiBold
                            opacity: root.media && root.media.active ? 1 : 0.55
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                        }
                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: root.media && root.media.active ? root.media.artist : ""
                            font: Kirigami.Theme.smallFont
                            opacity: 0.6
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                        }
                    }

                    Repeater {
                        model: [
                            { icon: root.media && root.media.playing ? "media-playback-pause-symbolic" : "media-playback-start-symbolic", act: "toggle" },
                            { icon: "media-skip-forward-symbolic", act: "next" }
                        ]
                        delegate: MouseArea {
                            required property var modelData
                            implicitWidth: 24
                            implicitHeight: 24
                            enabled: !!root.media && root.media.active
                            opacity: enabled ? 1 : 0.35
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.media[modelData.act]()

                            Kirigami.Icon {
                                anchors.centerIn: parent
                                width: 18
                                height: 18
                                source: parent.modelData.icon
                            }
                        }
                    }
                }
            }
        }
    }
}
