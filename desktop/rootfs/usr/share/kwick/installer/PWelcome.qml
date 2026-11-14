import QtQuick
import QtQuick.Layouts

FocusScope {
    id: p
    property bool showNav: false
    property bool canGoBack: false
    property bool canContinue: true
    property bool strictContinue: true
    property bool attempted: false
    property bool busy: false
    property string continueText: "Continue"
    property string continueKind: "primary"
    property string backText: "Back"
    property var interceptNext: null
    property var interceptBack: null
    property bool picking: false

    function focusFirst() { installBtn.forceActiveFocus() }

    ColumnLayout {
        id: hero
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -24
        width: Math.min(560, parent.width - 64)
        spacing: 0

        Image {
            id: logo
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 116
            Layout.preferredHeight: 134
            source: "file:///usr/share/icons/hicolor/scalable/apps/kwickos-logo.svg"
            sourceSize.width: 232
            sourceSize.height: 268
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            opacity: 0
            scale: 0.9
            Component.onCompleted: { opacity = 1; scale = 1 }
            Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 34
            text: "Welcome to KwickOS"
            color: Theme.text
            font.family: Theme.sans
            font.pixelSize: Theme.heroSize
            font.weight: Font.Bold
            font.letterSpacing: -0.8
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 12
            text: "Install KwickOS on this computer, or keep trying it first. Nothing changes until you choose to install."
            color: Theme.sub
            font.family: Theme.sans
            font.pixelSize: Theme.subtitleSize + 1
            lineHeight: 1.2
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 14
            visible: Inst.backendMissing
            text: "The installer backend (" + Inst.backend + ") is missing, so KwickOS can’t be installed from this session."
            color: Theme.bad
            font.family: Theme.sans
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Column {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 40
            spacing: 14
            KButton {
                id: installBtn
                anchors.horizontalCenter: parent.horizontalCenter
                width: 240
                large: true
                kind: "primary"
                text: "Install KwickOS"
                enabled: !Inst.backendMissing
                KeyNavigation.down: tryBtn
                KeyNavigation.tab: tryBtn
                onClicked: Inst.navNext()
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
            }
            KButton {
                id: tryBtn
                anchors.horizontalCenter: parent.horizontalCenter
                width: 240
                large: true
                text: "Try KwickOS"
                KeyNavigation.up: installBtn
                KeyNavigation.tab: langBtn
                onClicked: Inst.quitRequested()
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
            }
        }
    }

    FocusScope {
        id: langBtn
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 34
        width: langRow.implicitWidth + 30
        height: 34
        activeFocusOnTab: true
        KeyNavigation.tab: installBtn

        Rectangle {
            anchors.fill: parent
            anchors.margins: -3.5
            radius: height / 2
            color: "transparent"
            border.width: 3
            border.color: Theme.focusRing
            visible: langBtn.activeFocus
        }
        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: langMa.pressed ? Theme.pressed : langMa.containsMouse ? Theme.hover : "transparent"
            border.width: 1
            border.color: Theme.lineStrong
        }
        Row {
            id: langRow
            anchors.centerIn: parent
            spacing: 8
            Image {
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                source: "icons/globe.svg"
                sourceSize.width: 32
                sourceSize.height: 32
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Inst.localeName(Inst.locale)
                color: Theme.text
                font.family: Theme.sans
                font.pixelSize: 13
            }
            Chevron {
                anchors.verticalCenter: parent.verticalCenter
                width: 9
                height: 12
                shape: "updown"
                stroke: 1.5
                color: Theme.sub
            }
        }
        MouseArea {
            id: langMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: p.openPicker()
        }
        Keys.onSpacePressed: p.openPicker()
        Keys.onReturnPressed: p.openPicker()
        Keys.onEnterPressed: p.openPicker()
    }

    function openPicker() {
        picking = true
        langList.query = ""
        langList.searchField.forceActiveFocus()
        Qt.callLater(langList.reveal)
    }
    function closePicker() {
        picking = false
        langBtn.forceActiveFocus()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: p.picking ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 200 } }
        MouseArea { anchors.fill: parent; onClicked: p.closePicker() }
    }

    Rectangle {
        id: picker
        width: Math.min(460, p.width - 64)
        height: Math.min(520, p.height - 60)
        anchors.centerIn: parent
        radius: 16
        color: Theme.dark ? "#2b2b30" : "#f6f6f8"
        border.width: 1
        border.color: Theme.dark ? "#26ffffff" : "#1a000000"
        opacity: p.picking ? 1 : 0
        scale: p.picking ? 1 : 0.96
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 14
            Text {
                Layout.fillWidth: true
                text: "Language"
                color: Theme.text
                font.family: Theme.sans
                font.pixelSize: 18
                font.weight: Font.Bold
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: -8
                text: "Used for dates, numbers and the installed system"
                color: Theme.sub
                font.family: Theme.sans
                font.pixelSize: 13
                horizontalAlignment: Text.AlignHCenter
            }
            SearchList {
                id: langList
                Layout.fillWidth: true
                Layout.fillHeight: true
                listHeight: picker.height - 196
                placeholder: "Search languages"
                current: Inst.locale
                items: Inst.locales.map(function (c) { return { id: c, title: Inst.localeName(c), sub: c } })
                onPicked: (id) => Inst.locale = id
                onActivated: (id) => { Inst.locale = id; p.closePicker() }
                Keys.onReturnPressed: p.closePicker()
                Keys.onEnterPressed: p.closePicker()
                Keys.onEscapePressed: p.closePicker()
            }
            KButton {
                Layout.alignment: Qt.AlignRight
                text: "Done"
                kind: "primary"
                onClicked: p.closePicker()
            }
        }
    }
}
