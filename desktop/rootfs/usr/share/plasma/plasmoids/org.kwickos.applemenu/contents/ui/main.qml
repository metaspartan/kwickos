import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.private.sessions as Sessions
import org.kde.coreaddons as KCoreAddons
import org.kde.ksvg as KSvg
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    property bool menuOpen: false
    property Item button: null
    readonly property string userName: user.fullName || user.loginName

    function run(cmd) {
        exec.connectSource(cmd)
    }

    function openMenu() {
        menu.visualParent = button
        menu.openRelative()
    }

    preferredRepresentation: fullRepresentation
    Plasmoid.icon: "kwickos-menubar"
    Plasmoid.title: "KwickOS"
    toolTipMainText: ""
    toolTipSubText: ""

    Plasmoid.onActivated: openMenu()

    P5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: source => disconnectSource(source)
    }

    Sessions.SessionManagement {
        id: session
    }

    KCoreAddons.KUser {
        id: user
    }

    PlasmaExtras.Menu {
        id: menu
        placement: PlasmaExtras.Menu.BottomPosedLeftAlignedPopup
        onStatusChanged: root.menuOpen = status !== PlasmaExtras.Menu.Closed

        PlasmaExtras.MenuItem {
            text: "About This Computer"
            onClicked: root.run("kwick-settings about")
        }
        PlasmaExtras.MenuItem { separator: true }
        PlasmaExtras.MenuItem {
            text: "System Settings…"
            onClicked: root.run("kwick-settings")
        }
        PlasmaExtras.MenuItem {
            text: "App Store…"
            onClicked: root.run("kwick-store || plasma-discover")
        }
        PlasmaExtras.MenuItem {
            text: "Software Update…"
            onClicked: root.run("kwick-software-update || kwick-settings software-update")
        }
        PlasmaExtras.MenuItem { separator: true }
        PlasmaExtras.MenuItem {
            text: "Force Quit…\tMeta+Ctrl+Esc"
            onClicked: root.run("qdbus6 org.kde.KWin /KWin org.kde.KWin.killWindow")
        }
        PlasmaExtras.MenuItem { separator: true }
        PlasmaExtras.MenuItem {
            text: "Sleep"
            visible: session.canSuspend
            onClicked: session.suspend()
        }
        PlasmaExtras.MenuItem {
            text: "Restart…"
            visible: session.canReboot
            onClicked: session.requestReboot()
        }
        PlasmaExtras.MenuItem {
            text: "Shut Down…"
            visible: session.canShutdown
            onClicked: session.requestShutdown()
        }
        PlasmaExtras.MenuItem { separator: true }
        PlasmaExtras.MenuItem {
            text: "Lock Screen\tMeta+L"
            visible: session.canLock
            onClicked: session.lock()
        }
        PlasmaExtras.MenuItem {
            text: "Log Out " + root.userName + "…\tCtrl+Alt+Del"
            visible: session.canLogout
            onClicked: session.requestLogout()
        }
    }

    fullRepresentation: MouseArea {
        id: compact

        Layout.minimumWidth: icon.width + frame.margins.left + frame.margins.right
        Layout.preferredWidth: Layout.minimumWidth
        Layout.maximumWidth: Layout.minimumWidth
        Layout.fillHeight: true
        Component.onCompleted: root.button = compact
        onPressed: root.menuOpen ? menu.close() : root.openMenu()

        KSvg.FrameSvgItem {
            id: frame
            anchors.fill: parent
            imagePath: "widgets/menubaritem"
            prefix: root.menuOpen ? "pressed" : "normal"
        }

        Kirigami.Icon {
            id: icon
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.smallMedium
            height: width
            source: "kwickos-menubar"
            isMask: true
            color: Kirigami.Theme.textColor
        }
    }
}
