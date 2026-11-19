import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.coreaddons as KCoreAddons
import org.kde.plasma.private.sessions as Sessions
import "file:///usr/share/kwick/qml/fluent"

FocusScope {
    id: panel

    required property var start
    required property size area
    readonly property var favorites: start.rootModel.favoritesModel
    readonly property int cols: area.width >= 1366 ? 8 : 6
    readonly property int pad: 28
    readonly property int recentCols: cols >= 8 ? 3 : 2
    readonly property int inset: pad + 32
    readonly property bool searching: search.text.length > 0
    readonly property var results: searching && start.runnerModel.count > 0 ? start.runnerModel.modelForRow(0) : null
    readonly property string view: Plasmoid.configuration.allView
    property int folder: -1
    property bool allPins: Plasmoid.configuration.showAllPins

    function reset() {
        search.text = ""
        folder = -1
        body.contentY = 0
        search.forceActiveFocus()
    }

    function run(model, row) {
        if (model && model.trigger(row, "", null))
            start.close()
    }

    function categoryModel(row) {
        return start.rootModel.modelForRow(row)
    }

    width: cols * 96 + pad * 2
    height: Math.min(864, area.height - 24)
    focus: true

    Keys.onEscapePressed: {
        if (folder >= 0)
            folder = -1
        else if (searching)
            search.text = ""
        else
            start.close()
    }

    Sessions.SessionManagement {
        id: session
    }

    KCoreAddons.KUser {
        id: user
    }

    Item {
        id: top
        width: parent.width
        height: 72

        Rectangle {
            id: field
            x: 32
            y: 20
            width: parent.width - 64
            height: 32
            radius: 16
            color: Fluent.textBox
            border.width: 1
            border.color: Fluent.controlStroke

            Kirigami.Icon {
                id: lens
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                source: "system-search-symbolic"
                isMask: true
                color: Fluent.text2
            }

            TextInput {
                id: search
                anchors.left: lens.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                color: Fluent.text
                selectionColor: Kirigami.Theme.highlightColor
                font.family: Fluent.family
                font.pixelSize: Fluent.body
                clip: true
                focus: true
                onTextChanged: panel.start.runnerModel.query = text
                Keys.onReturnPressed: panel.run(panel.results, 0)
                Keys.onEnterPressed: panel.run(panel.results, 0)
                Keys.onDownPressed: results.forceActiveFocus()

                FluentText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: search.text.length === 0
                    text: "Search for apps, settings, and documents"
                    level: 2
                }
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Fluent.divider
        }
    }

    Flickable {
        id: body
        visible: !panel.searching
        anchors.top: top.bottom
        anchors.bottom: foot.top
        width: parent.width
        contentHeight: content.height + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

        Column {
            id: content
            y: 16
            width: parent.width
            spacing: 0

            SectionHeader {
                x: panel.inset
                width: parent.width - panel.inset * 2
                title: "Pinned"
                action: panel.favorites.count > panel.cols * 2 ? (panel.allPins ? "Show less" : "Show all") : ""
                actionIcon: panel.allPins ? "arrow-up" : "arrow-down"
                onTriggered: panel.allPins = !panel.allPins
            }

            Item { width: 1; height: 8 }

            Grid {
                x: panel.pad
                columns: panel.cols

                Repeater {
                    model: panel.favorites

                    delegate: AppTile {
                        required property int index
                        required property var model
                        visible: panel.allPins || index < panel.cols * 2
                        label: model.display
                        iconSource: model.decoration
                        onLaunch: panel.run(panel.favorites, index)
                        onMenu: (mx, my) => {
                            pinMenu.favoriteId = model.favoriteId
                            pinMenu.pinned = true
                            pinMenu.popup(this, mx, my)
                        }
                    }
                }
            }

            Item { width: 1; height: 20; visible: recent.count > 0 }

            SectionHeader {
                x: panel.inset
                width: parent.width - panel.inset * 2
                visible: recent.count > 0
                title: "Recommended"
            }

            Item { width: 1; height: 8; visible: recent.count > 0 }

            Grid {
                x: panel.pad + 20
                columns: panel.recentCols
                columnSpacing: 8
                rowSpacing: 4

                Repeater {
                    id: recent
                    model: panel.start.recentModel

                    delegate: ListRow {
                        required property int index
                        required property var model
                        visible: index < panel.recentCols * 2
                        width: (panel.width - (panel.pad + 20) * 2 - (panel.recentCols - 1) * 8) / panel.recentCols
                        iconSize: 32
                        label: model.display
                        detail: model.description || "Recently added"
                        iconSource: model.decoration
                        onLaunch: panel.run(panel.start.recentModel, index)
                    }
                }
            }

            Item { width: 1; height: 20 }

            SectionHeader {
                x: panel.inset
                width: parent.width - panel.inset * 2
                title: "All"
                action: "View: " + panel.view.charAt(0).toUpperCase() + panel.view.slice(1)
                actionIcon: "arrow-down"
                onTriggered: viewMenu.popup(this, width - viewMenu.implicitWidth, height + 4)
            }

            Item { width: 1; height: 8 }

            Loader {
                x: panel.pad
                width: panel.cols * 96
                sourceComponent: panel.view === "list" ? listView : panel.view === "grid" ? gridView : categoryView
            }
        }
    }

    Component {
        id: categoryView

        Flow {
            Repeater {
                model: panel.start.rootModel

                delegate: CategoryTile {
                    required property int index
                    required property var model
                    visible: index > 0
                    label: model.display
                    apps: index > 0 ? panel.categoryModel(index) : null
                    onOpen: panel.folder = index
                    onLaunch: row => panel.run(apps, row)
                }
            }
        }
    }

    Component {
        id: gridView

        Flow {
            Repeater {
                model: panel.categoryModel(0)

                delegate: AppTile {
                    required property int index
                    required property var model
                    label: model.display
                    iconSource: model.decoration
                    onLaunch: panel.run(panel.categoryModel(0), index)
                    onMenu: (mx, my) => {
                        pinMenu.favoriteId = model.favoriteId
                        pinMenu.pinned = panel.favorites.isFavorite(model.favoriteId)
                        pinMenu.popup(this, mx, my)
                    }
                }
            }
        }
    }

    Component {
        id: listView

        ListView {
            interactive: false
            height: contentHeight
            model: panel.categoryModel(0)
            section.property: "group"
            section.criteria: ViewSection.FirstCharacter
            section.delegate: Item {
                required property string section
                width: ListView.view.width
                height: 36

                FluentText {
                    x: 32
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.section
                    strong: true
                }
            }

            delegate: ListRow {
                required property int index
                required property var model
                x: 20
                width: ListView.view.width - 40
                label: model.display
                iconSource: model.decoration
                onLaunch: panel.run(panel.categoryModel(0), index)
                onMenu: (mx, my) => {
                    pinMenu.favoriteId = model.favoriteId
                    pinMenu.pinned = panel.favorites.isFavorite(model.favoriteId)
                    pinMenu.popup(this, mx, my)
                }
            }
        }
    }

    ListView {
        id: results
        visible: panel.searching
        anchors.top: top.bottom
        anchors.topMargin: 12
        anchors.bottom: foot.top
        x: 20
        width: parent.width - 40
        clip: true
        model: panel.results
        currentIndex: 0
        highlightFollowsCurrentItem: true
        keyNavigationEnabled: true
        Keys.onReturnPressed: panel.run(panel.results, currentIndex)
        Keys.onUpPressed: currentIndex > 0 ? decrementCurrentIndex() : search.forceActiveFocus()

        header: FluentText {
            visible: results.count > 0
            x: 12
            height: 32
            verticalAlignment: Text.AlignVCenter
            text: "Best match"
            strong: true
        }

        delegate: ListRow {
            required property int index
            required property var model
            width: ListView.view.width
            iconSize: index === 0 ? 32 : 24
            label: model.display
            detail: model.description || ""
            iconSource: model.decoration
            selected: ListView.isCurrentItem
            onLaunch: panel.run(panel.results, index)
        }

        FluentText {
            anchors.centerIn: parent
            visible: results.count === 0
            text: "No results"
            level: 1
        }
    }

    Rectangle {
        id: foot
        anchors.bottom: parent.bottom
        width: parent.width
        height: 64
        color: Fluent.footer
        radius: Fluent.overlayRadius

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

        MouseArea {
            id: account
            x: 44
            anchors.verticalCenter: parent.verticalCenter
            width: who.implicitWidth + 24
            height: 40
            hoverEnabled: true
            onClicked: userMenu.popup(this, 0, -userMenu.implicitHeight - 4)

            Subtle {
                anchors.fill: parent
                hovered: account.containsMouse
                pressed: account.pressed
            }

            RowLayout {
                id: who
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Item {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32

                    Rectangle {
                        anchors.fill: parent
                        radius: 16
                        color: Fluent.control
                        visible: face.status !== Image.Ready
                    }

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                        source: "user-symbolic"
                        isMask: true
                        color: Fluent.text
                        visible: face.status !== Image.Ready
                    }

                    Kirigami.ShadowedImage {
                        id: face
                        anchors.fill: parent
                        radius: 16
                        source: user.faceIconUrl
                        visible: status === Image.Ready
                    }
                }

                FluentText {
                    text: user.fullName || user.loginName
                    font.pixelSize: Fluent.caption
                }
            }
        }

        IconButton {
            id: power
            anchors.right: parent.right
            anchors.rightMargin: 52
            anchors.verticalCenter: parent.verticalCenter
            width: 40
            height: 40
            icon: "system-shutdown-symbolic"
            onClicked: powerMenu.popup(this, width - powerMenu.implicitWidth, -powerMenu.implicitHeight - 4)
        }
    }

    MenuPopup {
        id: powerMenu
        MenuEntry { icon: "system-lock-screen-symbolic"; text: "Lock"; visible: session.canLock; onTriggered: { powerMenu.close(); panel.start.close(); session.lock() } }
        MenuEntry { icon: "system-suspend-symbolic"; text: "Sleep"; visible: session.canSuspend; onTriggered: { powerMenu.close(); panel.start.close(); session.suspend() } }
        MenuEntry { icon: "system-shutdown-symbolic"; text: "Shut down"; visible: session.canShutdown; onTriggered: { powerMenu.close(); panel.start.close(); session.requestShutdown() } }
        MenuEntry { icon: "system-reboot-symbolic"; text: "Restart"; visible: session.canReboot; onTriggered: { powerMenu.close(); panel.start.close(); session.requestReboot() } }
    }

    MenuPopup {
        id: userMenu
        MenuEntry { text: "Change account settings"; onTriggered: { userMenu.close(); panel.start.close(); panel.start.exec("kcmshell6 kcm_users") } }
        MenuEntry { text: "Lock"; visible: session.canLock; onTriggered: { userMenu.close(); panel.start.close(); session.lock() } }
        MenuEntry { text: "Sign out"; visible: session.canLogout; onTriggered: { userMenu.close(); panel.start.close(); session.requestLogout() } }
    }

    MenuPopup {
        id: viewMenu
        MenuEntry { text: "Category"; onTriggered: { viewMenu.close(); Plasmoid.configuration.allView = "category" } }
        MenuEntry { text: "Grid"; onTriggered: { viewMenu.close(); Plasmoid.configuration.allView = "grid" } }
        MenuEntry { text: "List"; onTriggered: { viewMenu.close(); Plasmoid.configuration.allView = "list" } }
    }

    MenuPopup {
        id: pinMenu
        property string favoriteId
        property bool pinned
        MenuEntry {
            icon: pinMenu.pinned ? "window-unpin-symbolic" : "window-pin-symbolic"
            text: pinMenu.pinned ? "Unpin from Start" : "Pin to Start"
            onTriggered: {
                pinMenu.close()
                if (pinMenu.pinned)
                    panel.favorites.removeFavorite(pinMenu.favoriteId)
                else
                    panel.favorites.addFavorite(pinMenu.favoriteId, -1)
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        visible: panel.folder >= 0
        onClicked: panel.folder = -1

        Rectangle {
            anchors.fill: parent
            radius: Fluent.overlayRadius
            color: Qt.rgba(0, 0, 0, 0.3)
        }

        Rectangle {
            id: folderBox
            readonly property var apps: panel.folder >= 0 ? panel.categoryModel(panel.folder) : null
            anchors.centerIn: parent
            width: Math.min(4, panel.cols) * 96 + 48
            height: Math.min(parent.height - 96, folderGrid.implicitHeight + 88)
            radius: Fluent.overlayRadius
            color: Fluent.menu
            border.width: 1
            border.color: Fluent.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)

            MouseArea { anchors.fill: parent }

            FluentText {
                x: 24
                y: 20
                text: panel.folder >= 0 ? panel.start.rootModel.data(panel.start.rootModel.index(panel.folder, 0), Qt.DisplayRole) : ""
                font.pixelSize: Fluent.subtitle
                strong: true
            }

            Flickable {
                x: 24
                y: 64
                width: parent.width - 48
                height: parent.height - 88
                contentHeight: folderGrid.implicitHeight
                clip: true

                Grid {
                    id: folderGrid
                    columns: Math.min(4, panel.cols)

                    Repeater {
                        model: folderBox.apps

                        delegate: AppTile {
                            required property int index
                            required property var model
                            label: model.display
                            iconSource: model.decoration
                            onLaunch: panel.run(folderBox.apps, index)
                        }
                    }
                }
            }
        }
    }
}
