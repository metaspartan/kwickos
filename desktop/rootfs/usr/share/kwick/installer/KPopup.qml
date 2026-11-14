import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

FocusScope {
    id: b
    property var options: []
    property string current
    property string placeholder: "Choose…"
    signal picked(string id)
    implicitWidth: 240
    implicitHeight: 30
    activeFocusOnTab: enabled
    opacity: enabled ? 1 : 0.45

    readonly property var currentOption: {
        for (var i = 0; i < options.length; i++)
            if (options[i].id === current) return options[i]
        return null
    }

    Rectangle {
        anchors.fill: face
        anchors.margins: -3.5
        radius: face.radius + 3.5
        color: "transparent"
        border.width: 3
        border.color: Theme.focusRing
        visible: b.activeFocus
    }

    Rectangle {
        id: face
        anchors.fill: parent
        radius: 7
        color: ma.pressed ? Theme.buttonPressed : ma.containsMouse ? Theme.buttonHover : Theme.button
        border.width: 1
        border.color: Theme.dark ? "#1affffff" : "#1f000000"

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 11
            anchors.right: arrows.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: b.currentOption ? b.currentOption.label : b.placeholder
            color: b.currentOption ? Theme.text : Theme.sub
            font.family: Theme.sans
            font.pixelSize: 13
            elide: Text.ElideRight
        }

        Rectangle {
            id: arrows
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            height: parent.height - 8
            radius: 5
            color: Theme.accent
            Chevron {
                anchors.centerIn: parent
                width: 9
                height: 13
                shape: "updown"
                stroke: 1.6
                color: "#ffffff"
            }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { b.forceActiveFocus(); pop.open() }
    }

    Keys.onSpacePressed: pop.open()
    Keys.onDownPressed: pop.open()

    Popup {
        id: pop
        y: b.height + 4
        width: Math.max(b.width, 260)
        padding: 5
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: {
            Inst.modal++
            var i = 0
            for (var k = 0; k < b.options.length; k++) if (b.options[k].id === b.current) i = k
            lv.currentIndex = i
            lv.forceActiveFocus()
        }
        onClosed: { Inst.modal = Math.max(0, Inst.modal - 1); b.forceActiveFocus() }

        background: Rectangle {
            radius: 10
            color: Theme.dark ? "#323238" : "#fbfbfd"
            border.width: 1
            border.color: Theme.dark ? "#30ffffff" : "#22000000"
        }

        contentItem: ListView {
            id: lv
            implicitHeight: Math.min(contentHeight, 280)
            clip: true
            model: b.options
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: true
            highlightMoveDuration: 0
            Keys.onReturnPressed: { b.picked(b.options[currentIndex].id); pop.close() }
            Keys.onEnterPressed: { b.picked(b.options[currentIndex].id); pop.close() }
            Keys.onSpacePressed: { b.picked(b.options[currentIndex].id); pop.close() }
            delegate: Item {
                id: d
                required property var modelData
                required property int index
                width: lv.width
                height: modelData.sub ? 44 : 30
                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: lv.currentIndex === d.index ? Theme.accent : "transparent"
                }
                Chevron {
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10
                    height: 9
                    shape: "check"
                    stroke: 1.8
                    visible: d.modelData.id === b.current
                    color: lv.currentIndex === d.index ? "#ffffff" : Theme.text
                }
                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 26
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Text {
                        width: parent.width
                        text: d.modelData.label
                        color: lv.currentIndex === d.index ? "#ffffff" : Theme.text
                        font.family: Theme.sans
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        visible: !!d.modelData.sub
                        text: d.modelData.sub || ""
                        color: lv.currentIndex === d.index ? "#d9ffffff" : Theme.sub
                        font.family: Theme.sans
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: lv.currentIndex = d.index
                    onClicked: { b.picked(d.modelData.id); pop.close() }
                }
            }
        }
    }
}
