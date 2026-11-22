import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

ColumnLayout {
    id: page
    property string title
    property string subtitle
    property var items: []
    property var packages: []
    property var agents: []
    property var arch: []
    property var aur: []
    property bool loading: false
    property bool archLoading: false
    property string archError: ""
    property bool search: false
    property string filter: "all"
    property int limit: 60
    readonly property var all: items.concat(agents).concat(arch).concat(aur).concat(packages)
    readonly property var shown: (filter === "all" ? all : all.filter(function (a) { return (a.srcs || [a.src]).indexOf(filter) >= 0 })).slice(0, limit)
    readonly property var present: {
        var s = {}
        page.all.forEach(function (a) { (a.srcs || [a.src]).forEach(function (x) { s[x] = true }) })
        return s
    }
    spacing: 14

    onTitleChanged: { filter = "all"; limit = 60 }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text { Layout.fillWidth: true; text: page.title; color: Look.text; font.family: Look.display; font.pixelSize: Look.titleSize; font.weight: Look.win ? Font.DemiBold : Font.Bold; elide: Text.ElideRight }
            Text { visible: text !== ""; text: page.loading ? "Searching…" : page.subtitle !== "" ? page.subtitle : page.search ? (page.all.length ? page.all.length + " result" + (page.all.length === 1 ? "" : "s") : "") : ""; color: Look.sub; font.family: Look.sans; font.pixelSize: 13 }
        }
        BusyIndicator { running: page.loading || page.archLoading; visible: running; implicitWidth: 24; implicitHeight: 24 }
    }

    Seg {
        visible: page.search && Object.keys(page.present).length > 1
        options: [{ id: "all", label: "All" }].concat(["flathub", "apt", "arch", "aur", "agent"].filter(function (s) { return page.present[s] }).map(function (s) { return { id: s, label: Look.sourceName(s) } }))
        current: page.filter
        onPicked: function (id) { page.filter = id; page.limit = 60 }
    }

    Text {
        visible: !page.loading && !page.archLoading && page.all.length === 0
        Layout.fillWidth: true
        Layout.topMargin: 40
        horizontalAlignment: Text.AlignHCenter
        text: page.search ? "No results" : "Nothing here yet"
        color: Look.sub
        font.family: Look.display
        font.pixelSize: 20
        font.weight: Font.DemiBold
    }

    Text {
        visible: page.archError !== ""
        Layout.fillWidth: true
        text: "Arch search: " + page.archError
        color: Look.warn
        font.family: Look.sans
        font.pixelSize: 12
        wrapMode: Text.WordWrap
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
                    detail: modelData.plain ? "Debian package  ·  " + (modelData.summary || "") : modelData.src === "aur" ? (modelData.summary || "") + (modelData.votes !== undefined ? "  ·  " + modelData.votes + " votes" : "") : ""
                }
            }
        }
    }

    Btn {
        visible: page.all.length > page.limit && page.filter === "all" || (page.filter !== "all" && page.shown.length === page.limit)
        Layout.alignment: Qt.AlignHCenter
        text: "Show More"
        onClicked: page.limit += 60
    }

    Item { implicitHeight: 8 }
}
