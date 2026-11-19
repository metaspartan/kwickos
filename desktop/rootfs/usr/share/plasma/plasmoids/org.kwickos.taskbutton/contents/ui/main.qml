import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import "file:///usr/share/kwick/qml/fluent"

PlasmoidItem {
    id: root

    preferredRepresentation: compactRepresentation
    fullRepresentation: Item {}
    Plasmoid.icon: Plasmoid.configuration.icon
    Plasmoid.title: Plasmoid.configuration.title
    toolTipMainText: Plasmoid.configuration.title
    toolTipSubText: ""

    P5Support.DataSource {
        id: runner
        engine: "executable"
        onNewData: source => disconnectSource(source)
    }

    compactRepresentation: TaskbarButton {
        icon: Plasmoid.icon
        onClicked: runner.connectSource(Plasmoid.configuration.command)
    }
}
