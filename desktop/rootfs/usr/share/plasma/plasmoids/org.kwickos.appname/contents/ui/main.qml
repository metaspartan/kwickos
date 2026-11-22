import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.ksvg as KSvg
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager

PlasmoidItem {
    id: root

    property string appName: "Files"
    property bool hasWindow: false
    property var activeIndex: null
    property bool menuOpen: false
    property Item button: null

    preferredRepresentation: fullRepresentation
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    toolTipMainText: ""
    toolTipSubText: ""

    function refresh() {
        if (menuOpen) {
            return;
        }
        let idx = null;
        for (let i = 0; i < tasksModel.count; ++i) {
            const candidate = tasksModel.makeModelIndex(i);
            if (tasksModel.data(candidate, TaskManager.AbstractTasksModel.IsActive)) {
                idx = candidate;
                break;
            }
        }
        activeIndex = idx;
        if (idx && idx.valid) {
            const name = tasksModel.data(idx, TaskManager.AbstractTasksModel.AppName) || tasksModel.data(idx, Qt.DisplayRole) || "";
            appName = String(name).length > 0 ? String(name) : "Files";
            hasWindow = true;
        } else {
            appName = "Files";
            hasWindow = false;
        }
    }

    TaskManager.VirtualDesktopInfo {
        id: desktopInfo
    }

    TaskManager.ActivityInfo {
        id: activityInfo
    }

    TaskManager.TasksModel {
        id: tasksModel
        virtualDesktop: desktopInfo.currentDesktop
        activity: activityInfo.currentActivity
        filterByVirtualDesktop: false
        filterByScreen: false
        filterByActivity: true
        groupMode: TaskManager.TasksModel.GroupDisabled
        onActiveTaskChanged: settle.restart()
        onDataChanged: settle.restart()
        onCountChanged: settle.restart()
        onRowsInserted: settle.restart()
        onRowsRemoved: settle.restart()
        onLayoutChanged: settle.restart()
        onModelReset: settle.restart()
    }

    Timer {
        id: settle
        interval: 60
        onTriggered: root.refresh()
    }

    Timer {
        interval: 1500
        running: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: refresh()

    PlasmaExtras.Menu {
        id: menu
        placement: PlasmaExtras.Menu.BottomPosedLeftAlignedPopup
        onStatusChanged: {
            root.menuOpen = status !== PlasmaExtras.Menu.Closed;
            if (!root.menuOpen) {
                root.refresh();
            }
        }

        PlasmaExtras.MenuItem {
            text: "Hide " + root.appName
            enabled: root.hasWindow
            onClicked: tasksModel.requestToggleMinimized(root.activeIndex)
        }
        PlasmaExtras.MenuItem {
            separator: true
        }
        PlasmaExtras.MenuItem {
            text: "Quit " + root.appName
            enabled: root.hasWindow
            onClicked: tasksModel.requestClose(root.activeIndex)
        }
    }

    fullRepresentation: MouseArea {
        id: area

        Layout.minimumWidth: label.implicitWidth + Kirigami.Units.largeSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        Layout.maximumWidth: Layout.minimumWidth
        Layout.fillHeight: true
        Component.onCompleted: root.button = area
        onPressed: {
            if (root.menuOpen) {
                menu.close();
            } else {
                menu.visualParent = area;
                menu.openRelative();
            }
        }

        KSvg.FrameSvgItem {
            anchors.fill: parent
            imagePath: "widgets/menubaritem"
            prefix: root.menuOpen ? "pressed" : "normal"
        }

        PlasmaComponents3.Label {
            id: label
            anchors.centerIn: parent
            text: root.appName
            font.weight: Font.Bold
            textFormat: Text.PlainText
            elide: Text.ElideNone
        }
    }
}
