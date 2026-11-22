import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

Rectangle {
    id: pick
    property var options: []
    property string current
    signal picked(string id)
    readonly property var currentOption: {
        for (var i = 0; i < options.length; i++)
            if (options[i].id === current) return options[i]
        return null
    }
    readonly property var rows: {
        var out = []
        var last = ""
        options.forEach(function (o) {
            if (o.group && o.group !== last) {
                out.push({ header: o.group })
                last = o.group
            }
            out.push(o)
        })
        return out
    }
    implicitWidth: Math.max(170, label.implicitWidth + 44)
    implicitHeight: 26
    radius: 7
    color: area.pressed ? Theme.controlPressed : area.containsMouse ? Theme.controlHover : Theme.control
    border.width: Theme.light ? 1 : 0
    border.color: Theme.lineStrong

    Text {
        id: label
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.right: chevrons.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        text: pick.currentOption ? pick.currentOption.label : ""
        color: Theme.controlText
        font.family: Theme.sans
        font.pixelSize: 13
        elide: Text.ElideRight
    }

    Rectangle {
        id: chevrons
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        width: 18
        height: 18
        radius: 5
        color: Theme.accent
        Canvas {
            anchors.centerIn: parent
            width: 8
            height: 12
            onPaint: {
                var c = getContext("2d")
                c.reset()
                c.strokeStyle = "#ffffff"
                c.lineWidth = 1.5
                c.lineCap = "round"
                c.lineJoin = "round"
                c.beginPath()
                c.moveTo(1, 4.5); c.lineTo(4, 1.5); c.lineTo(7, 4.5)
                c.moveTo(1, 7.5); c.lineTo(4, 10.5); c.lineTo(7, 7.5)
                c.stroke()
            }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: menu.open()
    }

    Popup {
        id: menu
        y: pick.height + 4
        x: pick.width - width
        width: 340
        height: Math.min(list.contentHeight + 12, 460)
        padding: 6
        margins: 12
        onOpened: list.positionViewAtIndex(Math.max(0, pick.rows.indexOf(pick.currentOption)), ListView.Center)
        background: Rectangle { radius: 10; color: Theme.popup; border.width: 1; border.color: Theme.lineStrong }
        contentItem: ListView {
            id: list
            clip: true
            model: pick.rows
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { }
            delegate: Item {
                id: row
                required property var modelData
                readonly property bool header: row.modelData.header !== undefined
                readonly property bool on: !header && row.modelData.id === pick.current
                width: list.width
                height: header ? 28 : 42
                Text {
                    visible: row.header
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 5
                    text: row.header ? row.modelData.header : ""
                    color: Theme.sub
                    font.family: Theme.sans
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                Rectangle {
                    visible: !row.header
                    anchors.fill: parent
                    radius: 6
                    color: rowArea.containsMouse ? Theme.accent : "transparent"
                    Text {
                        x: 9
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.on ? "✓" : ""
                        color: rowArea.containsMouse ? "#ffffff" : Theme.text
                        font.family: Theme.sans
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.leftMargin: 26
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text { Layout.fillWidth: true; text: row.header ? "" : row.modelData.label; color: rowArea.containsMouse ? "#ffffff" : Theme.text; font.family: Theme.sans; font.pixelSize: 13; elide: Text.ElideRight }
                        Text { Layout.fillWidth: true; text: row.header ? "" : row.modelData.sub; color: rowArea.containsMouse ? "#d9ffffff" : Theme.sub; font.family: Theme.sans; font.pixelSize: 11; elide: Text.ElideRight }
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { menu.close(); pick.picked(row.modelData.id) }
                    }
                }
            }
        }
    }
}
