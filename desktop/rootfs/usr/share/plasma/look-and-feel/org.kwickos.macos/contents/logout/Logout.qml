import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.coreaddons as KCoreAddons
import org.kde.kirigami as Kirigami

import org.kde.plasma.private.sessions

Item {
    id: root
    height: screenGeometry.height
    width: screenGeometry.width

    signal logoutRequested()
    signal haltRequested()
    signal haltUpdateRequested()
    signal suspendRequested(int spdMethod)
    signal rebootRequested()
    signal rebootRequested2(int opt)
    signal rebootUpdateRequested()
    signal cancelRequested()
    signal lockScreenRequested()
    signal cancelSoftwareUpdateRequested()

    property alias backgroundColor: shade.color

    property real timeout: 60
    property real remainingTime: root.timeout
    readonly property bool showAllOptions: sdtype === ShutdownType.ShutdownTypeDefault
    readonly property bool halting: sdtype === ShutdownType.ShutdownTypeHalt || showAllOptions
    readonly property bool rebooting: sdtype === ShutdownType.ShutdownTypeReboot

    function primary() {
        if (rebooting) {
            softwareUpdatePending ? rebootUpdateRequested() : rebootRequested();
        } else if (halting) {
            softwareUpdatePending ? haltUpdateRequested() : haltRequested();
        } else {
            logoutRequested();
        }
    }

    onRemainingTimeChanged: {
        if (remainingTime <= 0) {
            primary();
        }
    }

    KCoreAddons.KUser {
        id: kuser
    }

    SessionsModel {
        id: sessionsModel
        includeUnusedSessions: false
    }

    QQC2.Action {
        onTriggered: root.cancelRequested()
        shortcut: "Escape"
    }

    Timer {
        id: countDown
        running: !root.showAllOptions
        repeat: true
        interval: 1000
        onTriggered: root.remainingTime--
    }

    Rectangle {
        id: shade
        anchors.fill: parent
        color: "black"
        opacity: 0.2
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.cancelRequested()
    }

    Kirigami.ShadowedRectangle {
        id: card
        Kirigami.Theme.inherit: false
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        anchors.centerIn: parent
        width: Math.max(Kirigami.Units.gridUnit * 18, buttons.implicitWidth + 2 * Kirigami.Units.gridUnit)
        height: column.implicitHeight + 2 * Kirigami.Units.gridUnit
        radius: 12
        color: Kirigami.Theme.backgroundColor
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
        shadow.size: 40
        shadow.yOffset: 12
        shadow.color: Qt.rgba(0, 0, 0, 0.45)

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        ColumnLayout {
            id: column
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: Kirigami.Units.gridUnit
            }
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: Kirigami.Units.iconSizes.huge
                implicitHeight: Kirigami.Units.iconSizes.huge
                source: kuser.faceIconUrl.toString().length > 0 ? kuser.faceIconUrl : "computer"
                fallback: "computer"
            }

            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                font.weight: Font.Bold
                textFormat: Text.PlainText
                text: {
                    if (root.rebooting) {
                        return softwareUpdatePending ? i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Install updates and restart your computer now?")
                                                     : i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Are you sure you want to restart your computer now?");
                    }
                    if (sdtype === ShutdownType.ShutdownTypeNone) {
                        return i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Are you sure you want to quit all applications and log out now?");
                    }
                    return softwareUpdatePending ? i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Install updates and shut down your computer now?")
                                                 : i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Are you sure you want to shut down your computer now?");
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                font: Kirigami.Theme.smallFont
                textFormat: Text.PlainText
                visible: countDown.running
                text: {
                    if (root.rebooting) {
                        return i18ndp("plasma_lookandfeel_org.kde.lookandfeel", "If you do nothing, the computer will restart automatically in 1 second.",
                                      "If you do nothing, the computer will restart automatically in %1 seconds.", root.remainingTime);
                    }
                    if (sdtype === ShutdownType.ShutdownTypeNone) {
                        return i18ndp("plasma_lookandfeel_org.kde.lookandfeel", "If you do nothing, you will be logged out automatically in 1 second.",
                                      "If you do nothing, you will be logged out automatically in %1 seconds.", root.remainingTime);
                    }
                    return i18ndp("plasma_lookandfeel_org.kde.lookandfeel", "If you do nothing, the computer will shut down automatically in 1 second.",
                                  "If you do nothing, the computer will shut down automatically in %1 seconds.", root.remainingTime);
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
                textFormat: Text.PlainText
                visible: sessionsModel.count > 1 && sdtype !== ShutdownType.ShutdownTypeNone
                text: i18ndp("plasma_lookandfeel_org.kde.lookandfeel",
                             "One other user is currently logged in. If the computer is shut down or restarted, that user may lose work.",
                             "%1 other users are currently logged in. If the computer is shut down or restarted, those users may lose work.",
                             sessionsModel.count - 1)
            }

            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.disabledTextColor
                textFormat: Text.PlainText
                visible: rebootToFirmwareSetup || rebootToBootLoaderMenu
                text: rebootToFirmwareSetup ? i18nd("plasma_lookandfeel_org.kde.lookandfeel", "When restarted, the computer will enter the firmware setup screen.")
                                            : i18nd("plasma_lookandfeel_org.kde.lookandfeel", "When restarted, the computer will enter the boot loader menu.")
            }

            RowLayout {
                id: buttons
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                QQC2.Button {
                    text: i18ndc("plasma_lookandfeel_org.kde.lookandfeel", "Suspend to RAM", "Sleep")
                    visible: root.showAllOptions && spdMethods.SuspendState
                    onClicked: root.suspendRequested(2)
                }
                QQC2.Button {
                    text: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Restart")
                    visible: root.showAllOptions && maysd
                    onClicked: softwareUpdatePending ? root.rebootUpdateRequested() : root.rebootRequested()
                }
                QQC2.Button {
                    text: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Log Out")
                    visible: root.showAllOptions && canLogout
                    onClicked: root.logoutRequested()
                }
                QQC2.Button {
                    id: cancelButton
                    text: i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Cancel")
                    onClicked: root.cancelRequested()
                }
                QQC2.Button {
                    id: primaryButton
                    Accessible.defaultButton: true
                    focus: true
                    implicitHeight: cancelButton.implicitHeight
                    implicitWidth: Math.max(cancelButton.implicitWidth, primaryLabel.implicitWidth + 2 * Kirigami.Units.gridUnit)
                    background: Rectangle {
                        radius: 6
                        color: primaryButton.down ? Qt.darker(Kirigami.Theme.highlightColor, 1.18) : primaryButton.hovered ? Qt.lighter(Kirigami.Theme.highlightColor, 1.06) : Kirigami.Theme.highlightColor
                        border.width: primaryButton.visualFocus ? 3 : 0
                        border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.5)
                    }
                    contentItem: QQC2.Label {
                        id: primaryLabel
                        text: primaryButton.text
                        color: "#ffffff"
                        font: primaryButton.font
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    visible: root.rebooting || sdtype === ShutdownType.ShutdownTypeNone ? true : maysd
                    text: {
                        if (root.rebooting) {
                            return i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Restart");
                        }
                        if (sdtype === ShutdownType.ShutdownTypeNone) {
                            return i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Log Out");
                        }
                        return i18nd("plasma_lookandfeel_org.kde.lookandfeel", "Shut Down");
                    }
                    onClicked: root.primary()
                    Keys.onReturnPressed: root.primary()
                    Keys.onEnterPressed: root.primary()
                }
            }
        }
    }
}
