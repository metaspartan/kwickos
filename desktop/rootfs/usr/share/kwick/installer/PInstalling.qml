import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

PageFrame {
    id: p
    readonly property bool failed: Inst.finished && !Inst.succeeded
    showNav: failed
    canContinue: true
    continueText: "Quit Installer"
    continueKind: "primary"
    interceptNext: function () { Inst.quitRequested(); return true }
    interceptBack: function () { Inst.navTo(6); return true }
    maxWidth: 560

    Item {
        Layout.fillWidth: true
        Layout.topMargin: Math.max(0, Math.min(90, (p.height - 440) / 2 - 40))
        implicitHeight: 168

        Repeater {
            model: 3
            Rectangle {
                id: ring
                required property int index
                anchors.centerIn: parent
                width: 120
                height: 120
                radius: 60
                color: "transparent"
                border.width: 1.5
                border.color: p.failed ? Theme.warn : Theme.accent
                opacity: 0
                visible: !p.failed && !Inst.succeeded
                SequentialAnimation on scale {
                    running: ring.visible
                    loops: Animation.Infinite
                    PauseAnimation { duration: ring.index * 1400 }
                    NumberAnimation { from: 0.85; to: 1.55; duration: 4200; easing.type: Easing.OutSine }
                }
                SequentialAnimation on opacity {
                    running: ring.visible
                    loops: Animation.Infinite
                    PauseAnimation { duration: ring.index * 1400 }
                    NumberAnimation { from: 0.55; to: 0; duration: 4200; easing.type: Easing.OutSine }
                }
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: 132
            height: 132
            radius: 66
            color: Theme.accent
            opacity: p.failed ? 0 : 0.08
            SequentialAnimation on scale {
                running: !p.failed
                loops: Animation.Infinite
                NumberAnimation { from: 0.94; to: 1.04; duration: 2600; easing.type: Easing.InOutSine }
                NumberAnimation { from: 1.04; to: 0.94; duration: 2600; easing.type: Easing.InOutSine }
            }
        }

        Image {
            anchors.centerIn: parent
            width: 96
            height: 96
            source: p.failed ? "icons/error.svg" : Inst.succeeded ? "icons/done.svg" : "file:///usr/share/icons/hicolor/scalable/apps/kwickos-logo.svg"
            sourceSize.width: 192
            sourceSize.height: 192
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }
    }

    Text {
        Layout.fillWidth: true
        Layout.topMargin: 10
        text: p.failed ? "Installation Failed" : Inst.succeeded ? "Installation Complete" : "Installing KwickOS"
        color: Theme.text
        font.family: Theme.sans
        font.pixelSize: Theme.titleSize
        font.weight: Font.Bold
        font.letterSpacing: -0.4
        horizontalAlignment: Text.AlignHCenter
    }

    Text {
        Layout.fillWidth: true
        Layout.leftMargin: 20
        Layout.rightMargin: 20
        text: p.failed ? Inst.error : (Inst.statusText !== "" ? Inst.stepTitle + " · " + Inst.statusText : Inst.stepTitle)
        color: p.failed ? Theme.text : Theme.sub
        font.family: Theme.sans
        font.pixelSize: Theme.subtitleSize
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        maximumLineCount: p.failed ? 6 : 2
        elide: Text.ElideRight
    }

    Text {
        Layout.fillWidth: true
        visible: p.failed
        text: "Your computer hasn’t been restarted. Check the details below, then go back to try again."
        color: Theme.sub
        font.family: Theme.sans
        font.pixelSize: 13
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: 14
        Layout.leftMargin: 30
        Layout.rightMargin: 30
        visible: !p.failed
        spacing: 10

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 8
            radius: 4
            color: Theme.track
            Rectangle {
                height: parent.height
                radius: 4
                width: Math.max(height, parent.width * Inst.progress)
                color: Theme.accent
                Behavior on width { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
                Rectangle {
                    id: sheen
                    width: 80
                    height: parent.height
                    radius: 4
                    opacity: 0.35
                    visible: !Inst.succeeded && parent.width > 100
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "#00ffffff" }
                        GradientStop { position: 0.5; color: "#ffffffff" }
                        GradientStop { position: 1; color: "#00ffffff" }
                    }
                    NumberAnimation on x {
                        running: sheen.visible
                        loops: Animation.Infinite
                        from: -80
                        to: sheen.parent.width
                        duration: 2400
                        easing.type: Easing.InOutSine
                    }
                }
                clip: true
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Text {
                Layout.fillWidth: true
                text: Inst.succeeded ? "Finishing up…" : Inst.eta !== "" ? Inst.eta : "Estimating time remaining…"
                color: Theme.sub
                font.family: Theme.sans
                font.pixelSize: 12
            }
            Text {
                text: Math.round(Inst.progress * 100) + "%"
                color: Theme.sub
                font.family: Theme.sans
                font.pixelSize: 12
                font.features: ({ "tnum": 1 })
            }
        }
    }

    Disclosure {
        id: details
        Layout.topMargin: 8
        title: "Details"
        open: p.failed

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Math.max(120, Math.min(220, p.height - 520))
            radius: 10
            color: Theme.dark ? "#141417" : "#fafafc"
            border.width: 1
            border.color: Theme.line

            ListView {
                id: logView
                anchors.fill: parent
                anchors.margins: 10
                clip: true
                model: Inst.log
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { }
                property bool follow: true
                onMovementEnded: follow = atYEnd
                onCountChanged: if (follow) Qt.callLater(positionViewAtEnd)
                delegate: Text {
                    required property string line
                    width: logView.width - 12
                    text: line
                    color: line.indexOf("Error:") === 0 ? Theme.bad : line.indexOf("▸") === 0 ? Theme.text : Theme.sub
                    font.family: Theme.mono
                    font.pixelSize: 11
                    font.weight: line.indexOf("▸") === 0 ? Font.DemiBold : Font.Normal
                    wrapMode: Text.WrapAnywhere
                    topPadding: line.indexOf("▸") === 0 ? 4 : 0
                }
                Text {
                    anchors.centerIn: parent
                    visible: logView.count === 0
                    text: "Waiting for the installer…"
                    color: Theme.faint
                    font.family: Theme.sans
                    font.pixelSize: 12
                }
            }
        }
    }
}
