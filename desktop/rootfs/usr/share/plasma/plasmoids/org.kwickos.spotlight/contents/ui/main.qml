import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import org.kde.ksvg as KSvg
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    function search() {
        exec.connectSource("kwick-search")
    }

    preferredRepresentation: fullRepresentation
    Plasmoid.icon: "kwick-spotlight-symbolic"
    Plasmoid.title: "Spotlight"
    toolTipMainText: "Search"
    toolTipSubText: "Search apps, files and settings"
    Plasmoid.onActivated: search()

    P5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: source => disconnectSource(source)
    }

    fullRepresentation: MouseArea {
        id: button

        Layout.minimumWidth: icon.width + frame.margins.left + frame.margins.right
        Layout.preferredWidth: Layout.minimumWidth
        Layout.maximumWidth: Layout.minimumWidth
        Layout.fillHeight: true
        onClicked: root.search()

        KSvg.FrameSvgItem {
            id: frame
            anchors.fill: parent
            imagePath: "widgets/menubaritem"
            prefix: button.pressed ? "pressed" : "normal"
        }

        Kirigami.Icon {
            id: icon
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.smallMedium
            height: width
            source: "kwick-spotlight-symbolic"
            isMask: true
            color: Kirigami.Theme.textColor
        }
    }
}
