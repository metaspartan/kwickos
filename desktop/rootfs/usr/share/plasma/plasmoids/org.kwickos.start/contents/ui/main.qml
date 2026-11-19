import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.private.kicker as Kicker
import org.kde.plasma.plasma5support as P5Support
import "file:///usr/share/kwick/qml/fluent"

PlasmoidItem {
    id: root

    property bool invoking: false

    readonly property Kicker.RootModel rootModel: Kicker.RootModel {
        autoPopulate: false
        appletInterface: root
        flat: true
        sorted: true
        showSeparators: false
        showTopLevelItems: false
        showAllApps: true
        showAllAppsCategorized: false
        showRecentApps: false
        showRecentDocs: false
        showPowerSession: false
        showFavoritesPlaceholder: false

        Component.onCompleted: {
            favoritesModel.initForClient("org.kwickos.start.favorites")
            probe.connectSource("grep -c 'Favorites-org.kwickos.start.favorites-' \"${XDG_CONFIG_HOME:-$HOME/.config}/kactivitymanagerd-statsrc\"")
        }
    }

    P5Support.DataSource {
        id: probe
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source)
            if (!(parseInt(data.stdout) > 0))
                root.rootModel.favoritesModel.portOldFavorites(Plasmoid.configuration.pinned)
        }
    }

    readonly property Kicker.RunnerModel runnerModel: Kicker.RunnerModel {
        appletInterface: root
        mergeResults: true
        favoritesModel: root.rootModel.favoritesModel
    }

    readonly property Kicker.RecentUsageModel recentModel: Kicker.RecentUsageModel {
        favoritesModel: root.rootModel.favoritesModel
    }

    function close() {
        flyout.visible = false
    }

    function exec(cmd) {
        runner.connectSource(cmd)
    }

    function invoke() {
        if (invoking)
            return
        invoking = true
        Qt.callLater(() => {
            invoking = false
            flyout.toggle()
        })
    }

    P5Support.DataSource {
        id: runner
        engine: "executable"
        onNewData: source => disconnectSource(source)
    }

    preferredRepresentation: compactRepresentation
    fullRepresentation: Item {}
    activationTogglesExpanded: false
    Plasmoid.icon: Plasmoid.configuration.icon
    toolTipMainText: flyout.visible ? "" : "Start"
    toolTipSubText: ""
    onExpandedChanged: () => {
        if (root.expanded) {
            root.expanded = false
            invoke()
        }
    }

    Connections {
        target: Plasmoid
        function onActivated() {
            root.invoke()
        }
    }

    compactRepresentation: TaskbarButton {
        icon: Plasmoid.icon
        mask: true
        tint: Fluent.accent
        open: flyout.visible
        onClicked: flyout.toggle()
        Component.onCompleted: flyout.anchorItem = this
    }

    Flyout {
        id: flyout
        centered: true
        onVisibleChanged: {
            if (visible) {
                root.rootModel.refresh()
                panel.reset()
            }
        }
        mainItem: StartPanel {
            id: panel
            start: root
            area: flyout.area
        }
    }
}
