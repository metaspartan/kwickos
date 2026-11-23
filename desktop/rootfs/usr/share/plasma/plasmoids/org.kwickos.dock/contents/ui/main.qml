import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtCore
import Qt.labs.folderlistmodel
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import org.kde.ksvg as KSvg
import org.kde.taskmanager as TaskManager

PlasmoidItem {
    id: root
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false

    preferredRepresentation: fullRepresentation

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property int edge: Plasmoid.location
    readonly property bool farEdge: edge === PlasmaCore.Types.BottomEdge || edge === PlasmaCore.Types.RightEdge
    readonly property real outer: vertical ? width : height
    readonly property real floatGap: Plasmoid.formFactor === PlasmaCore.Types.Horizontal || vertical ? Math.max(0, Plasmoid.configuration.floatGap) : 0
    readonly property real nearOffset: farEdge ? 0 : floatGap
    readonly property real thickness: Math.max(1, outer - floatGap)
    readonly property real gap: Math.max(3, Math.round(thickness * 0.147))
    readonly property real iconSize: Math.max(16, Math.round(thickness - 2 * gap))
    readonly property real cell: Math.round(iconSize + 10)
    readonly property real pad: 4
    readonly property bool showTrash: Plasmoid.configuration.showTrash
    readonly property real sepSlot: showTrash ? 13 : 0
    readonly property real dockLength: pad * 2 + tasksModel.count * cell + (showTrash ? sepSlot + cell : 0)
    readonly property real maxScale: Math.max(1.0, Math.min(1.3, (iconSize + gap - 1) / iconSize))
    readonly property bool magnify: Plasmoid.configuration.magnify
    property real pointer: -1
    property Item hoveredItem: null
    property string hoveredName: ""
    property Item menuTask: null
    property bool menuOpen: false
    property bool ready: false

    function crossPos(size, fromEdge) {
        return farEdge ? thickness - fromEdge - size : fromEdge;
    }

    function scaleAt(center) {
        if (!magnify || pointer < 0) {
            return 1.0;
        }
        const d = (pointer - center) / (cell * 1.1);
        return 1.0 + (maxScale - 1.0) * Math.exp(-d * d);
    }

    function quote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    function launcherUrls(v) {
        let list = [];
        const raw = Array.isArray(v) ? v : (v ? [v] : []);
        for (let i = 0; i < raw.length; ++i) {
            String(raw[i]).split(",").forEach(s => {
                if (s.trim().length > 0) {
                    list.push(s.trim());
                }
            });
        }
        return list;
    }

    function syncPins() {
        const ids = tasksModel.launcherList.map(u => decodeURIComponent(String(u).replace(/^.*[\/:]/, "")));
        exe.run("kwick-dock sync " + quote(ids.join(",")));
    }

    function setHover(item, name) {
        hoveredItem = item;
        hoveredName = name || "";
    }

    function clearHover(item) {
        if (hoveredItem === item) {
            hoveredItem = null;
            hoveredName = "";
        }
    }

    function activate(task) {
        const idx = tasksModel.makeModelIndex(task.index);
        if (task.model.IsGroupParent) {
            const n = tasksModel.rowCount(idx);
            let best = null;
            let bestOrder = -1;
            let activeRow = -1;
            for (let i = 0; i < n; ++i) {
                const child = tasksModel.makeModelIndex(task.index, i);
                const order = tasksModel.data(child, TaskManager.AbstractTasksModel.StackingOrder);
                if (tasksModel.data(child, TaskManager.AbstractTasksModel.IsActive)) {
                    activeRow = i;
                }
                if (order > bestOrder) {
                    bestOrder = order;
                    best = child;
                }
            }
            if (activeRow >= 0) {
                tasksModel.requestActivate(tasksModel.makeModelIndex(task.index, (activeRow + 1) % n));
            } else if (best) {
                tasksModel.requestActivate(best);
            }
            return;
        }
        if (!task.running) {
            task.launchBounce();
        }
        tasksModel.requestActivate(idx);
    }

    readonly property real menuItemHeight: 22
    readonly property real menuSeparatorHeight: 13
    readonly property real menuPadding: 5.5
    readonly property real menuTextMargin: 42

    function menuWidth(menu) {
        let widest = 0;
        for (let i = 0; i < menu.content.length; ++i) {
            const entry = menu.content[i];
            if (entry.visible && !entry.separator) {
                menuMetrics.text = entry.text;
                widest = Math.max(widest, menuMetrics.advanceWidth);
            }
        }
        return Math.ceil(widest + menuTextMargin);
    }

    function menuHeight(menu) {
        let h = 2 * menuPadding;
        for (let i = 0; i < menu.content.length; ++i) {
            const entry = menu.content[i];
            if (entry.visible) {
                h += entry.separator ? menuSeparatorHeight : menuItemHeight;
            }
        }
        return h;
    }

    function popupMenu(menu, item) {
        const w = menuWidth(menu);
        const p = item.mapToItem(root, 0, 0);
        menu.minimumWidth = w;
        menu.maximumWidth = w;
        if (vertical) {
            const h = menuHeight(menu);
            menuAnchor.x = p.x;
            menuAnchor.y = p.y + item.height / 2 - h / 2;
            menuAnchor.width = item.width;
            menuAnchor.height = h;
            menu.placement = edge === PlasmaCore.Types.LeftEdge ? PlasmaExtras.Menu.RightPosedTopAlignedPopup : PlasmaExtras.Menu.LeftPosedTopAlignedPopup;
        } else {
            menuAnchor.x = p.x + item.width / 2 - w / 2;
            menuAnchor.y = p.y;
            menuAnchor.width = w;
            menuAnchor.height = item.height;
            menu.placement = edge === PlasmaCore.Types.TopEdge ? PlasmaExtras.Menu.BottomPosedLeftAlignedPopup : PlasmaExtras.Menu.TopPosedLeftAlignedPopup;
        }
        menu.visualParent = menuAnchor;
        menu.openRelative();
    }

    function openMenu(task) {
        menuTask = task;
        popupMenu(taskMenu, task);
    }

    property Item panelRoot: null
    property int panelTries: 0

    function findPanelRoot() {
        let p = root.parent;
        while (p) {
            if (p.touchingWindowDirect !== undefined && p.floatingnessTarget !== undefined) {
                return p;
            }
            p = p.parent;
        }
        return null;
    }

    Timer {
        interval: 400
        repeat: true
        running: root.panelRoot === null && root.panelTries < 30
        triggeredOnStart: true
        onTriggered: {
            root.panelTries++;
            root.panelRoot = root.findPanelRoot();
        }
    }

    function insetBackground() {
        if (!panelRoot) {
            return;
        }
        const g = floatGap;
        const kids = panelRoot.children;
        for (let i = 0; i < kids.length; ++i) {
            const c = kids[i];
            if (c.imagePath === undefined || !c.anchors || !c.anchors.fill || String(c.imagePath).indexOf("panel-background") < 0) {
                continue;
            }
            c.anchors.topMargin = edge === PlasmaCore.Types.TopEdge ? g : 0;
            c.anchors.bottomMargin = edge === PlasmaCore.Types.BottomEdge ? g : 0;
            c.anchors.leftMargin = edge === PlasmaCore.Types.LeftEdge ? g : 0;
            c.anchors.rightMargin = edge === PlasmaCore.Types.RightEdge ? g : 0;
            if (g > 0) {
                c.enabledBorders = KSvg.FrameSvg.AllBorders;
            }
        }
    }

    onPanelRootChanged: insetBackground()
    onFloatGapChanged: insetBackground()
    onEdgeChanged: insetBackground()

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
        screenGeometry: Plasmoid.containment.screenGeometry
        filterByVirtualDesktop: false
        filterByScreen: false
        filterByActivity: true
        groupMode: TaskManager.TasksModel.GroupApplications
        groupInline: false
        sortMode: TaskManager.TasksModel.SortManual
        launchInPlace: true
        separateLaunchers: false
        hideActivatedLaunchers: true
        launcherList: root.launcherUrls(Plasmoid.configuration.launchers)
        onLauncherListChanged: {
            if (root.ready && String(launcherList) !== String(root.launcherUrls(Plasmoid.configuration.launchers))) {
                Plasmoid.configuration.launchers = launcherList;
                root.syncPins();
            }
            pinOrder.restart();
        }
        onCountChanged: pinOrder.restart()
        onRowsInserted: pinOrder.restart()
        Component.onCompleted: root.ready = true
    }

    function pinPosition(row) {
        const url = tasksModel.data(tasksModel.makeModelIndex(row), TaskManager.AbstractTasksModel.LauncherUrlWithoutIcon);
        return url ? tasksModel.launcherPosition(url) : -1;
    }

    function keepPinOrder() {
        const n = tasksModel.count;
        for (let t = 0; t < n; ++t) {
            let best = -1;
            let bestPos = -1;
            for (let r = t; r < n; ++r) {
                const p = pinPosition(r);
                if (p >= 0 && (bestPos < 0 || p < bestPos)) {
                    bestPos = p;
                    best = r;
                }
            }
            if (best < 0) {
                return;
            }
            if (best !== t) {
                tasksModel.move(best, t);
            }
        }
    }

    Timer {
        id: pinOrder
        interval: 250
        onTriggered: root.keepPinOrder()
    }

    Connections {
        target: Plasmoid.configuration
        function onLaunchersChanged() {
            const urls = root.launcherUrls(Plasmoid.configuration.launchers);
            if (String(tasksModel.launcherList) !== String(urls)) {
                tasksModel.launcherList = urls;
            }
        }
    }

    P5Support.DataSource {
        id: exe
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => disconnectSource(source)
        function run(cmd) {
            connectSource(cmd);
        }
    }

    FolderListModel {
        id: trashFiles
        folder: StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/Trash/files"
        showHidden: true
        showDirs: true
        showDotAndDotDot: false
    }

    PlasmaCore.Dialog {
        id: label
        type: PlasmaCore.Dialog.Tooltip
        flags: Qt.WindowDoesNotAcceptFocus | Qt.WindowStaysOnTopHint
        location: Plasmoid.location
        visualParent: root.hoveredItem
        visible: root.hoveredItem !== null && root.hoveredName.length > 0 && !root.menuOpen
        mainItem: PlasmaComponents3.Label {
            text: root.hoveredName
            leftPadding: 4
            rightPadding: 4
            font.weight: Font.Medium
        }
    }

    Item {
        id: menuAnchor
    }

    TextMetrics {
        id: menuMetrics
        font: Qt.application.font
    }

    PlasmaExtras.Menu {
        id: taskMenu
        readonly property var m: root.menuTask ? root.menuTask.model : null
        readonly property bool running: root.menuTask ? root.menuTask.running : false
        readonly property string url: m && m.LauncherUrlWithoutIcon ? String(m.LauncherUrlWithoutIcon) : ""
        readonly property bool pinned: url.length > 0 && tasksModel.launcherPosition(url) !== -1
        onStatusChanged: root.menuOpen = status !== PlasmaExtras.Menu.Closed

        PlasmaExtras.MenuItem {
            text: "Open"
            visible: !taskMenu.running
            onClicked: root.activate(root.menuTask)
        }
        PlasmaExtras.MenuItem {
            text: "New Window"
            visible: taskMenu.running && taskMenu.url.length > 0
            onClicked: tasksModel.requestNewInstance(tasksModel.makeModelIndex(root.menuTask.index))
        }
        PlasmaExtras.MenuItem {
            separator: true
        }
        PlasmaExtras.MenuItem {
            text: "Keep in Dock"
            visible: !taskMenu.pinned && taskMenu.url.length > 0
            onClicked: tasksModel.requestAddLauncher(taskMenu.url)
        }
        PlasmaExtras.MenuItem {
            text: "Remove from Dock"
            visible: taskMenu.pinned
            onClicked: tasksModel.requestRemoveLauncher(taskMenu.url)
        }
        PlasmaExtras.MenuItem {
            separator: true
            visible: taskMenu.running
        }
        PlasmaExtras.MenuItem {
            text: "Quit"
            visible: taskMenu.running
            onClicked: tasksModel.requestClose(tasksModel.makeModelIndex(root.menuTask.index))
        }
    }

    PlasmaExtras.Menu {
        id: trashMenu
        onStatusChanged: root.menuOpen = status !== PlasmaExtras.Menu.Closed
        PlasmaExtras.MenuItem {
            text: "Open"
            onClicked: Qt.openUrlExternally("trash:/")
        }
        PlasmaExtras.MenuItem {
            text: "Empty Trash"
            enabled: trashFiles.count > 0
            onClicked: exe.run("ktrash6 --empty")
        }
    }

    fullRepresentation: Item {
        id: dock

        Layout.minimumWidth: root.vertical ? -1 : root.dockLength
        Layout.preferredWidth: root.vertical ? root.outer : root.dockLength
        Layout.maximumWidth: root.vertical ? -1 : root.dockLength
        Layout.minimumHeight: root.vertical ? root.dockLength : -1
        Layout.preferredHeight: root.vertical ? root.dockLength : root.outer
        Layout.maximumHeight: root.vertical ? root.dockLength : -1
        Layout.fillWidth: root.vertical
        Layout.fillHeight: !root.vertical

        HoverHandler {
            id: hover
            onHoveredChanged: if (!hovered) root.pointer = -1
            onPointChanged: root.pointer = hovered ? (root.vertical ? point.position.y : point.position.x) : -1
        }

        Repeater {
            model: tasksModel
            delegate: Item {
                id: task

                required property var model
                required property int index

                readonly property real along: root.pad + index * root.cell
                readonly property bool running: model.IsWindow === true || model.IsGroupParent === true
                readonly property bool starting: model.IsStartup === true
                readonly property bool attention: model.IsDemandingAttention === true
                readonly property real zoom: root.scaleAt(along + root.cell / 2)
                property real lift: 0
                property bool kicked: false

                function launchBounce() {
                    kicked = true;
                    kickTimer.restart();
                }

                function publishGeometry() {
                    if (!running || !task.Window.window) {
                        return;
                    }
                    const p = icon.mapToGlobal(0, 0);
                    tasksModel.requestPublishDelegateGeometry(tasksModel.makeModelIndex(index), Qt.rect(p.x, p.y, icon.width, icon.height), task);
                }

                onAlongChanged: publishTimer.restart()
                onRunningChanged: publishTimer.restart()
                onWidthChanged: publishTimer.restart()
                onHeightChanged: publishTimer.restart()
                Component.onCompleted: publishTimer.restart()

                Timer {
                    id: publishTimer
                    interval: 250
                    onTriggered: task.publishGeometry()
                }

                Connections {
                    target: task.Window.window
                    function onXChanged() { publishTimer.restart(); }
                    function onYChanged() { publishTimer.restart(); }
                    function onWidthChanged() { publishTimer.restart(); }
                    function onHeightChanged() { publishTimer.restart(); }
                }

                readonly property int kids: model.ChildCount || 0
                onKidsChanged: publishTimer.restart()

                x: root.vertical ? root.nearOffset : along
                y: root.vertical ? along : root.nearOffset
                width: root.vertical ? root.thickness : root.cell
                height: root.vertical ? root.cell : root.thickness
                z: zoom

                Kirigami.Icon {
                    id: icon
                    roundToIconSize: false
                    source: task.model.decoration
                    width: root.iconSize
                    height: root.iconSize
                    x: root.vertical ? root.crossPos(root.iconSize, root.gap + task.lift) : (root.cell - root.iconSize) / 2
                    y: root.vertical ? (root.cell - root.iconSize) / 2 : root.crossPos(root.iconSize, root.gap + task.lift)
                    transformOrigin: root.edge === PlasmaCore.Types.LeftEdge ? Item.Left
                                   : root.edge === PlasmaCore.Types.RightEdge ? Item.Right
                                   : root.edge === PlasmaCore.Types.TopEdge ? Item.Top : Item.Bottom
                    scale: task.zoom
                    Behavior on scale {
                        NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                    }
                    layer.enabled: mouse.pressed
                    layer.effect: MultiEffect {
                        brightness: -0.32
                    }
                }

                Rectangle {
                    width: 4
                    height: 4
                    radius: 2
                    color: Kirigami.Theme.textColor
                    opacity: task.running || task.starting ? 0.82 : 0.0
                    x: root.vertical ? root.crossPos(4, 4) : (root.cell - 4) / 2
                    y: root.vertical ? (root.cell - 4) / 2 : root.crossPos(4, 4)
                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }
                }

                Timer {
                    id: kickTimer
                    interval: 1700
                    onTriggered: task.kicked = false
                }

                SequentialAnimation {
                    id: bounce
                    running: task.starting || task.attention || task.kicked
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation {
                        target: task
                        property: "lift"
                        to: Math.min(root.gap - 1, root.iconSize * 0.3)
                        duration: 280
                        easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        target: task
                        property: "lift"
                        to: 0
                        duration: 280
                        easing.type: Easing.InQuad
                    }
                    PauseAnimation {
                        duration: task.attention ? 380 : 60
                    }
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onEntered: root.setHover(task, task.model.AppName || task.model.display)
                    onExited: root.clearHover(task)
                    onClicked: mouseEvent => {
                        if (mouseEvent.button === Qt.RightButton) {
                            root.openMenu(task);
                        } else {
                            root.activate(task);
                        }
                    }
                }
            }
        }

        Rectangle {
            visible: root.showTrash
            readonly property real along: root.pad + tasksModel.count * root.cell + (root.sepSlot - 1) / 2
            readonly property real span: root.iconSize * 0.74
            width: root.vertical ? span : 1
            height: root.vertical ? 1 : span
            x: root.vertical ? root.nearOffset + root.crossPos(span, root.gap + (root.iconSize - span) / 2) : along
            y: root.vertical ? along : root.nearOffset + root.crossPos(span, root.gap + (root.iconSize - span) / 2)
            color: Kirigami.Theme.textColor
            opacity: 0.28
        }

        Item {
            id: trash
            visible: root.showTrash
            readonly property real along: root.pad + tasksModel.count * root.cell + root.sepSlot
            readonly property real zoom: root.scaleAt(along + root.cell / 2)
            x: root.vertical ? root.nearOffset : along
            y: root.vertical ? along : root.nearOffset
            width: root.vertical ? root.thickness : root.cell
            height: root.vertical ? root.cell : root.thickness
            z: zoom

            Kirigami.Icon {
                id: trashIcon
                roundToIconSize: false
                source: trashFiles.count > 0 ? "user-trash-full" : "user-trash"
                width: root.iconSize
                height: root.iconSize
                x: root.vertical ? root.crossPos(root.iconSize, root.gap) : (root.cell - root.iconSize) / 2
                y: root.vertical ? (root.cell - root.iconSize) / 2 : root.crossPos(root.iconSize, root.gap)
                transformOrigin: root.edge === PlasmaCore.Types.LeftEdge ? Item.Left
                               : root.edge === PlasmaCore.Types.RightEdge ? Item.Right
                               : root.edge === PlasmaCore.Types.TopEdge ? Item.Top : Item.Bottom
                scale: trash.zoom
                Behavior on scale {
                    NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                }
                layer.enabled: trashMouse.pressed || drop.containsDrag
                layer.effect: MultiEffect {
                    brightness: -0.32
                }
            }

            DropArea {
                id: drop
                anchors.fill: parent
                onDropped: dropEvent => {
                    if (dropEvent.hasUrls) {
                        exe.run("kioclient move " + dropEvent.urls.map(u => root.quote(String(u))).join(" ") + " trash:/");
                        dropEvent.acceptProposedAction();
                    }
                }
            }

            MouseArea {
                id: trashMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onEntered: root.setHover(trash, "Trash")
                onExited: root.clearHover(trash)
                onClicked: mouseEvent => {
                    if (mouseEvent.button === Qt.RightButton) {
                        root.popupMenu(trashMenu, trash);
                    } else {
                        Qt.openUrlExternally("trash:/");
                    }
                }
            }
        }
    }
}
