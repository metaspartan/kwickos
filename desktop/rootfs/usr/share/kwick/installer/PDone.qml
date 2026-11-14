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
    property string continueText: "Restart Now"
    property string continueKind: "primary"
    property string backText: "Back"
    property var interceptNext: null
    property var interceptBack: null
    property bool restarting: false

    function focusFirst() { restartBtn.forceActiveFocus() }

    ColumnLayout {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -20
        width: Math.min(520, parent.width - 64)
        spacing: 0

        Image {
            id: check
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 108
            Layout.preferredHeight: 108
            source: "icons/done.svg"
            sourceSize.width: 216
            sourceSize.height: 216
            smooth: true
            scale: 0.6
            opacity: 0
            Component.onCompleted: { scale = 1; opacity = 1 }
            Behavior on scale { NumberAnimation { duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 30
            text: Inst.dryRun ? "Dry Run Complete" : "KwickOS Is Installed"
            color: Theme.text
            font.family: Theme.sans
            font.pixelSize: Theme.heroSize - 4
            font.weight: Font.Bold
            font.letterSpacing: -0.6
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 12
            text: Inst.dryRun
                  ? "Every step ran without touching your disks. Run the installer again without --dry-run to install for real."
                  : "Remove the installation media when the screen goes dark. Your computer will then start KwickOS, ready for " + (Inst.fullname.trim().split(/\s+/)[0] || "you") + "."
            color: Theme.sub
            font.family: Theme.sans
            font.pixelSize: Theme.subtitleSize + 1
            lineHeight: 1.2
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Column {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 40
            spacing: 14
            KButton {
                id: restartBtn
                anchors.horizontalCenter: parent.horizontalCenter
                width: 240
                large: true
                kind: "primary"
                text: p.restarting ? "Restarting…" : "Restart Now"
                enabled: !p.restarting
                KeyNavigation.down: laterBtn
                KeyNavigation.tab: laterBtn
                onClicked: {
                    if (Inst.dryRun) { Inst.quitRequested(); return }
                    p.restarting = true
                    Inst.reboot()
                }
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
            }
            KButton {
                id: laterBtn
                anchors.horizontalCenter: parent.horizontalCenter
                width: 240
                large: true
                text: "Keep Trying KwickOS"
                KeyNavigation.up: restartBtn
                KeyNavigation.tab: restartBtn
                onClicked: Inst.quitRequested()
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
            }
        }
    }
}
