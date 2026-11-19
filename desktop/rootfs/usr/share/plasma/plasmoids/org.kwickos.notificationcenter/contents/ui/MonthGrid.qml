import QtQuick
import "file:///usr/share/kwick/qml/fluent"

Item {
    id: grid

    property date today: new Date()
    property date month: new Date(today.getFullYear(), today.getMonth(), 1)
    readonly property date first: new Date(month.getFullYear(), month.getMonth(), 1 - month.getDay())
    readonly property int cell: 40
    readonly property int pitch: Math.floor((width - 24) / 7)

    function shift(n) {
        month = new Date(month.getFullYear(), month.getMonth() + n, 1)
    }

    implicitHeight: 48 + 32 + pitch * 6 + 12

    MouseArea {
        anchors.fill: parent
        onWheel: wheel => grid.shift(wheel.angleDelta.y > 0 ? -1 : 1)
    }

    MouseArea {
        id: title
        x: 12
        y: 8
        width: label.implicitWidth + 16
        height: 32
        hoverEnabled: true
        onClicked: grid.month = new Date(grid.today.getFullYear(), grid.today.getMonth(), 1)

        Subtle {
            anchors.fill: parent
            hovered: title.containsMouse
            pressed: title.pressed
        }

        FluentText {
            id: label
            anchors.centerIn: parent
            text: Qt.formatDate(grid.month, "MMMM yyyy")
            strong: true
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 12
        y: 8
        spacing: 4

        IconButton {
            icon: "arrow-up"
            iconSize: 12
            onClicked: grid.shift(-1)
        }

        IconButton {
            icon: "arrow-down"
            iconSize: 12
            onClicked: grid.shift(1)
        }
    }

    Row {
        x: 12
        y: 48

        Repeater {
            model: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

            delegate: FluentText {
                required property string modelData
                width: grid.pitch
                height: 32
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: modelData
                font.pixelSize: Fluent.caption
            }
        }
    }

    Grid {
        x: 12
        y: 80
        columns: 7

        Repeater {
            model: 42

            delegate: Item {
                id: day
                required property int index
                readonly property date date: new Date(grid.first.getFullYear(), grid.first.getMonth(), grid.first.getDate() + index)
                readonly property bool inMonth: date.getMonth() === grid.month.getMonth()
                readonly property bool isToday: date.toDateString() === grid.today.toDateString()
                width: grid.pitch
                height: grid.pitch

                MouseArea {
                    id: hit
                    anchors.centerIn: parent
                    width: grid.cell
                    height: grid.cell
                    hoverEnabled: true

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: day.isToday ? (hit.pressed ? Fluent.accentPressed : hit.containsMouse ? Fluent.accentHover : Fluent.accent)
                                           : hit.pressed ? Fluent.subtlePressed : hit.containsMouse ? Fluent.subtleHover : "transparent"
                    }

                    FluentText {
                        anchors.centerIn: parent
                        text: day.date.getDate()
                        color: day.isToday ? Fluent.onAccent : day.inMonth ? Fluent.text : Fluent.text3
                        font.weight: day.isToday ? Font.DemiBold : Font.Normal
                    }
                }
            }
        }
    }
}
