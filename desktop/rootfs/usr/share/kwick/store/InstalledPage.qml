import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

ColumnLayout {
    id: page
    property string filter: "all"
    property string query: ""
    readonly property var items: Store.installed || []
    readonly property var present: {
        var s = {}
        page.items.forEach(function (a) { s[a.src] = true })
        return s
    }
    readonly property var shown: items.filter(function (a) {
        if (page.filter === "system") { if (!a.system) return false }
        else if (page.filter !== "all" && a.src !== page.filter) return false
        if (page.filter !== "system" && page.filter !== "all" && a.system) return false
        if (page.filter === "all" && a.system && !page.showSystem) return false
        return page.query === "" || (a.name || "").toLowerCase().indexOf(page.query) >= 0
    })
    property bool showSystem: false
    spacing: 14

    Component.onCompleted: if (!Store.installedLoaded) Store.loadInstalled()

    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text { Layout.fillWidth: true; text: Look.win ? "Library" : "Installed"; color: Look.text; font.family: Look.display; font.pixelSize: Look.titleSize; font.weight: Look.win ? Font.DemiBold : Font.Bold }
            Text { text: page.shown.length + " app" + (page.shown.length === 1 ? "" : "s"); color: Look.sub; font.family: Look.sans; font.pixelSize: 13 }
        }
        BusyIndicator { running: Store.installedLoading; visible: running; implicitWidth: 24; implicitHeight: 24 }
        SearchField {
            Layout.preferredWidth: 220
            placeholder: "Filter"
            onTextChanged: page.query = text.toLowerCase()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        Seg {
            options: [{ id: "all", label: "All" }].concat(["flathub", "apt", "arch", "aur", "agent", "model"].filter(function (s) { return page.present[s] }).map(function (s) { return { id: s, label: Look.sourceName(s) } })).concat([{ id: "system", label: "Included with KwickOS" }])
            current: page.filter
            onPicked: function (id) { page.filter = id }
        }
        Item { Layout.fillWidth: true }
    }

    Rectangle {
        Layout.fillWidth: true
        visible: page.shown.length > 0
        implicitHeight: list.implicitHeight + (Look.gnu ? 2 : 0)
        radius: Look.gnu ? 12 : 0
        color: "transparent"
        border.width: Look.gnu ? 1 : 0
        border.color: Look.cardStroke
        clip: Look.gnu
        ColumnLayout {
            id: list
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Look.gnu ? 1 : 0
            spacing: 0
            Repeater {
                model: page.shown
                delegate: AppRow {
                    required property var modelData
                    required property int index
                    app: modelData
                    last: index === page.shown.length - 1
                    removable: !modelData.system && Store.isInstalled(modelData)
                    detail: (modelData.installedVer ? modelData.installedVer : "") + (modelData.size ? "  ·  " + modelData.size : "") + (modelData.system ? "  ·  Included with KwickOS" : "")
                    onRemoveClicked: ApplicationWindow.window.confirmRemove(modelData)
                }
            }
        }
    }

    Text {
        visible: Store.installedLoaded && page.shown.length === 0
        Layout.fillWidth: true
        Layout.topMargin: 30
        horizontalAlignment: Text.AlignHCenter
        text: page.query !== "" ? "No matching apps" : "No apps from this source"
        color: Look.sub
        font.family: Look.sans
        font.pixelSize: 15
    }

    Item { implicitHeight: 8 }
}
