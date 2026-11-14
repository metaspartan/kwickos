import QtQuick

FocusScope {
    id: seg
    property var options: []
    property string current
    property bool fill: false
    signal picked(string id)
    implicitHeight: 32
    implicitWidth: row.implicitWidth + 6
    activeFocusOnTab: enabled
    opacity: enabled ? 1 : 0.45

    readonly property int idx: {
        for (var i = 0; i < options.length; i++)
            if (options[i].id === current) return i
        return -1
    }

    Rectangle {
        anchors.fill: bg
        anchors.margins: -3.5
        radius: bg.radius + 3.5
        color: "transparent"
        border.width: 3
        border.color: Theme.focusRing
        visible: seg.activeFocus
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: 9
        color: Theme.segBg

        Rectangle {
            id: thumb
            visible: seg.idx >= 0
            y: 3
            height: parent.height - 6
            radius: 7
            color: Theme.segOn
            border.width: Theme.dark ? 0 : 0.5
            border.color: "#1f000000"
            property Item target: seg.idx >= 0 && rep.count > seg.idx ? rep.itemAt(seg.idx) : null
            x: target ? row.x + target.x : 3
            width: target ? target.width : 0
            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }

        Row {
            id: row
            anchors.verticalCenter: parent.verticalCenter
            x: 3
            spacing: 0
            Repeater {
                id: rep
                model: seg.options
                delegate: Item {
                    id: item
                    required property var modelData
                    required property int index
                    readonly property bool on: seg.current === modelData.id
                    width: seg.fill ? (seg.width - 6) / seg.options.length : label.implicitWidth + 28
                    height: seg.height - 6
                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: item.modelData.label
                        color: Theme.text
                        font.family: Theme.sans
                        font.pixelSize: 13
                        font.weight: item.on ? Font.DemiBold : Font.Normal
                    }
                    Rectangle {
                        visible: !item.on && item.index > 0 && seg.idx !== item.index - 1
                        width: 1
                        height: parent.height - 12
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.lineStrong
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { seg.forceActiveFocus(); seg.picked(item.modelData.id) }
                    }
                }
            }
        }
    }

    Keys.onLeftPressed: if (idx > 0) picked(options[idx - 1].id)
    Keys.onRightPressed: if (idx < options.length - 1) picked(options[idx + 1].id)
}
