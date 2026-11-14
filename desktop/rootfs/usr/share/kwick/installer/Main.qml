import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls.Basic

ApplicationWindow {
    id: win
    visible: true
    title: "Install KwickOS"
    width: Math.round(Math.min(1060, Screen.desktopAvailableWidth * 0.9))
    height: Math.round(Math.min(740, Screen.desktopAvailableHeight * 0.9))
    minimumWidth: 720
    minimumHeight: 560
    color: Theme.bg

    property int page: 0
    property int dir: 1
    property bool allowClose: false
    property alias canvas: canvas
    property alias confirmSheet: confirm
    readonly property var pages: ["PWelcome.qml", "PKeyboard.qml", "PRegion.qml", "PLook.qml", "PDisk.qml", "PAccount.qml", "PSummary.qml", "PInstalling.qml", "PDone.qml"]
    readonly property Item cur: stack.currentItem

    function go(i) {
        if (i < 0 || i >= pages.length || i === page || stack.busy) return
        dir = i > page ? 1 : -1
        page = i
        stack.replace(null, Qt.resolvedUrl(pages[i]), {}, StackView.ReplaceTransition)
    }

    function next() {
        if (!cur || !cur.showNav || stack.busy || confirm.shown || busySheet.shown) return
        if (!cur.canContinue) {
            cur.attempted = true
            return
        }
        if (cur.interceptNext && cur.interceptNext()) return
        go(page + 1)
    }

    function back() {
        if (!cur || !cur.showNav || !cur.canGoBack || stack.busy || confirm.shown || busySheet.shown) return
        if (cur.interceptBack && cur.interceptBack()) return
        go(page - 1)
    }

    Component.onCompleted: Inst.load()

    onClosing: (close) => {
        if (Inst.running) {
            close.accepted = false
            busySheet.show()
            return
        }
        if (!allowClose) {
            close.accepted = false
            allowClose = true
            Inst.cleanup(function () { Qt.quit() })
        }
    }

    Connections {
        target: Inst
        function onNavNext() { win.next() }
        function onNavBack() { win.back() }
        function onNavTo(i) { win.go(i) }
        function onRequestInstall() { confirm.show() }
        function onQuitRequested() { win.close() }
        function onFinishedChanged() {
            if (Inst.finished && Inst.succeeded && win.page === 7) doneTimer.start()
        }
    }

    Timer {
        id: doneTimer
        interval: 900
        onTriggered: win.go(8)
    }

    Item {
    id: canvas
    anchors.fill: parent

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.bgTop }
            GradientStop { position: 0.45; color: Theme.bg }
        }
    }

    StackView {
        id: stack
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: nav.top
        initialItem: Qt.resolvedUrl(win.pages[0])
        focus: true

        onCurrentItemChanged: if (currentItem) Qt.callLater(function () { if (stack.currentItem && stack.currentItem.focusFirst) stack.currentItem.focusFirst() })

        replaceEnter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.motion; easing.type: Easing.OutCubic }
                NumberAnimation { property: "x"; from: win.dir * 56; to: 0; duration: Theme.motion + 80; easing.type: Easing.OutCubic }
            }
        }
        replaceExit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 180; easing.type: Easing.InCubic }
                NumberAnimation { property: "x"; from: 0; to: -win.dir * 40; duration: 220; easing.type: Easing.InCubic }
            }
        }
    }

    Item {
        id: nav
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 84
        opacity: win.cur && win.cur.showNav ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 220 } }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 32
            anchors.verticalCenter: parent.verticalCenter
            visible: Inst.dryRun
            text: "Dry run – nothing will be changed"
            color: Theme.warn
            font.family: Theme.sans
            font.pixelSize: Theme.smallSize
            font.weight: Font.Medium
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 32
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            KButton {
                id: backBtn
                text: win.cur && win.cur.backText ? win.cur.backText : "Back"
                visible: win.cur ? win.cur.canGoBack : false
                onClicked: win.back()
            }
            KButton {
                id: nextBtn
                text: win.cur ? win.cur.continueText : "Continue"
                kind: win.cur ? win.cur.continueKind : "primary"
                enabled: win.cur ? (win.cur.canContinue || !win.cur.strictContinue) : false
                busy: win.cur ? !!win.cur.busy : false
                onClicked: win.next()
            }
        }
    }

    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: !confirm.shown && !busySheet.shown && Inst.modal === 0 && !!win.cur && win.cur.showNav
        onActivated: win.next()
    }
    Shortcut {
        sequences: ["Alt+Left", "Ctrl+["]
        enabled: !confirm.shown && !busySheet.shown && Inst.modal === 0
        onActivated: win.back()
    }
    Shortcut {
        sequences: ["Alt+Right", "Ctrl+]"]
        enabled: !confirm.shown && !busySheet.shown && Inst.modal === 0
        onActivated: win.next()
    }
    Shortcut {
        sequences: ["Ctrl+Q"]
        onActivated: win.close()
    }

    Sheet {
        id: confirm
        readonly property var d: Inst.diskByPath(Inst.disk)
        title: Inst.mode === "erase"
               ? "Erase “" + Inst.diskTitle(d) + "” and install KwickOS?"
               : "Install KwickOS on the selected partitions?"
        message: Inst.dryRun
                 ? "This is a dry run. The installer will walk through every step without writing to the disk."
                 : Inst.mode === "erase"
                   ? "Everything on this " + Inst.bytes(d ? d.size : 0) + " disk will be permanently erased. You can’t undo this action."
                   : "The partitions you chose will be formatted, and the data on them will be lost. You can’t undo this action."
        confirmText: Inst.mode === "erase" ? "Erase and Install" : "Install"
        destructive: true
        onConfirmed: {
            Inst.start()
            win.go(7)
        }
    }

    Sheet {
        id: busySheet
        single: true
        title: "KwickOS is still installing"
        message: "Quitting now would leave this computer unable to start. Please wait until the installation is complete."
        confirmText: "OK"
    }
    }
}
