import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

ColumnLayout {
    id: sl
    property var items: []
    property string current
    property string placeholder: "Search"
    property int listHeight: 300
    property alias query: search.text
    property alias searchField: search
    signal picked(string id)
    signal activated(string id)
    spacing: 12
    Layout.fillWidth: true

    readonly property var shown: {
        var q = search.text.trim().toLowerCase()
        if (q === "") return items
        var words = q.split(/\s+/)
        return items.filter(function (it) {
            var hay = (it.title + " " + (it.sub || "") + " " + it.id).toLowerCase()
            return words.every(function (w) { return hay.indexOf(w) >= 0 })
        })
    }

    function indexOfCurrent() {
        for (var i = 0; i < shown.length; i++)
            if (shown[i].id === current) return i
        return -1
    }

    function step(d) {
        if (!shown.length) return
        var i = indexOfCurrent()
        i = i < 0 ? 0 : Math.max(0, Math.min(shown.length - 1, i + d))
        picked(shown[i].id)
        list.positionViewAtIndex(i, ListView.Contain)
    }

    function reveal() {
        var i = indexOfCurrent()
        if (i >= 0) list.positionViewAtIndex(i, ListView.Center)
    }

    onShownChanged: Qt.callLater(reveal)
    Component.onCompleted: Qt.callLater(reveal)

    KField {
        id: search
        Layout.fillWidth: true
        search: true
        placeholder: sl.placeholder
        Keys.onDownPressed: sl.step(1)
        Keys.onUpPressed: sl.step(-1)
        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_PageDown) { sl.step(8); e.accepted = true }
            else if (e.key === Qt.Key_PageUp) { sl.step(-8); e.accepted = true }
        }
        onAccepted: if (sl.current !== "") sl.activated(sl.current)
        onEdited: {
            if (sl.shown.length && sl.indexOfCurrent() < 0) sl.picked(sl.shown[0].id)
        }
    }

    Rectangle {
        Layout.preferredHeight: sl.listHeight
        Layout.fillWidth: true
        radius: Theme.radius
        color: Theme.card
        border.width: 1
        border.color: Theme.line

        ListView {
            id: list
            anchors.fill: parent
            anchors.margins: 1
            clip: true
            model: sl.shown
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: sl.indexOfCurrent()
            highlightMoveDuration: 0
            activeFocusOnTab: false
            topMargin: 6
            bottomMargin: 6
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool on: sl.current === modelData.id
                width: list.width
                height: modelData.sub ? 48 : 38

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    radius: 7
                    color: row.on ? Theme.accent : ma.containsMouse ? Theme.hover : "transparent"
                }

                ColumnLayout {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    anchors.right: tick.left
                    anchors.rightMargin: 10
                    spacing: 1
                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.title
                        color: row.on ? Theme.accentText : Theme.text
                        font.family: Theme.sans
                        font.pixelSize: Theme.bodySize
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !!row.modelData.sub
                        text: row.modelData.sub || ""
                        color: row.on ? "#d9ffffff" : Theme.sub
                        font.family: Theme.sans
                        font.pixelSize: Theme.smallSize
                        elide: Text.ElideRight
                    }
                }

                Text {
                    id: tick
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.trailing || ""
                    color: row.on ? "#d9ffffff" : Theme.sub
                    font.family: Theme.sans
                    font.pixelSize: Theme.smallSize
                }

                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sl.picked(row.modelData.id)
                    onDoubleClicked: sl.activated(row.modelData.id)
                }
            }

            Text {
                anchors.centerIn: parent
                visible: list.count === 0
                text: sl.items.length ? "No Results" : "Loading…"
                color: Theme.sub
                font.family: Theme.sans
                font.pixelSize: Theme.bodySize
            }
        }
    }
}
