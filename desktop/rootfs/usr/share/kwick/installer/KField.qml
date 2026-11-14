import QtQuick

FocusScope {
    id: f
    property alias text: input.text
    property string placeholder
    property bool password: false
    property bool invalid: false
    property bool search: false
    property alias input: input
    property alias validator: input.validator
    property int maximumLength: 256
    signal edited()
    signal accepted()
    implicitWidth: 300
    implicitHeight: Theme.controlHeight
    activeFocusOnTab: true

    Rectangle {
        anchors.fill: box
        anchors.margins: -3.5
        radius: box.radius + 3.5
        color: "transparent"
        border.width: 3
        border.color: f.invalid ? Qt.rgba(Theme.bad.r, Theme.bad.g, Theme.bad.b, 0.5) : Theme.focusRing
        visible: input.activeFocus
    }

    Rectangle {
        id: box
        anchors.fill: parent
        radius: f.search ? height / 2 : 8
        color: Theme.field
        border.width: 1
        border.color: f.invalid ? Theme.bad : Theme.fieldLine
    }

    Item {
        id: glass
        visible: f.search
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 14
        height: 14
        Rectangle { width: 10; height: 10; radius: 5; color: "transparent"; border.width: 1.6; border.color: Theme.sub }
        Rectangle { x: 8.5; y: 9.5; width: 5.5; height: 1.6; radius: 0.8; color: Theme.sub; rotation: 45; transformOrigin: Item.Left }
    }

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: f.search ? 34 : 12
        anchors.rightMargin: clearBtn.visible ? 32 : 12
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.text
        font.family: Theme.sans
        font.pixelSize: Theme.bodySize
        selectionColor: Theme.accent
        selectedTextColor: Theme.accentText
        selectByMouse: true
        clip: true
        focus: true
        maximumLength: f.maximumLength
        echoMode: f.password ? TextInput.Password : TextInput.Normal
        passwordCharacter: "•"
        onTextEdited: f.edited()
        onAccepted: f.accepted()

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !input.text.length && !input.preeditText.length
            text: f.placeholder
            color: Theme.faint
            font: input.font
            elide: Text.ElideRight
            width: parent.width
        }
    }

    Rectangle {
        id: clearBtn
        visible: f.search && input.text.length > 0
        width: 16
        height: 16
        radius: 8
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.faint
        Rectangle { anchors.centerIn: parent; width: 8; height: 1.6; radius: 0.8; color: Theme.field; rotation: 45 }
        Rectangle { anchors.centerIn: parent; width: 8; height: 1.6; radius: 0.8; color: Theme.field; rotation: -45 }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: { input.text = ""; f.edited(); input.forceActiveFocus() }
        }
    }
}
