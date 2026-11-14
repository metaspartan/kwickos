import QtQuick
import QtQuick.Layouts

PageFrame {
    id: p
    icon: "icons/summary.svg"
    title: "Ready to Install"
    subtitle: "Check your choices. Go back to change anything."
    maxWidth: 580
    iconSize: 56
    continueText: Inst.mode === "erase" ? "Erase and Install" : "Install"
    continueKind: "destructive"
    canContinue: !Inst.planLoading && !Inst.planBlocking
    busy: Inst.planLoading
    interceptNext: function () { Inst.requestInstall(); return true }

    readonly property var d: Inst.diskByPath(Inst.disk)

    Component.onCompleted: Inst.loadPlan()

    readonly property var rows: {
        var r = []
        r.push({ k: "Language", v: Inst.localeName(Inst.locale) + ", " + Inst.keymapName(Inst.keymap) + " keyboard" })
        r.push({ k: "Time zone", v: Inst.zoneCity(Inst.timezone) + ", " + Inst.zoneRegion(Inst.timezone) })
        r.push({ k: "Look", v: Inst.layoutName(Inst.layout) + " layout" })
        if (Inst.mode === "erase")
            r.push({ k: "Disk", v: "Erase " + Inst.diskTitle(d) + " (" + Inst.bytes(d ? d.size : 0) + ")" })
        else {
            var parts = ["system on " + Inst.rootPart.replace("/dev/", "")]
            if (Inst.efiPart) parts.push("EFI on " + Inst.efiPart.replace("/dev/", ""))
            if (Inst.homePart) parts.push("home on " + Inst.homePart.replace("/dev/", ""))
            r.push({ k: "Disk", v: Inst.diskTitle(d) + ": " + parts.join(", ") })
        }
        var st = Inst.fsName(Inst.fs)
        if (Inst.encrypt && Inst.mode === "erase") st += ", encrypted"
        r.push({ k: "Storage", v: st + " · " + Inst.swapName(Inst.swap) })
        if (Inst.bootloader) r.push({ k: "Boot loader", v: Inst.bootName(Inst.bootloader) })
        r.push({ k: "Account", v: Inst.fullname.trim() + " (" + Inst.user + ")" + (Inst.autologin ? ", logs in automatically" : "") })
        r.push({ k: "Computer name", v: Inst.hostname })
        return r
    }

    KCard {
        Repeater {
            model: p.rows
            delegate: Item {
                id: row
                required property var modelData
                required property int index
                Layout.fillWidth: true
                implicitHeight: Math.max(38, val.implicitHeight + 20)
                Text {
                    id: key
                    x: 18
                    width: 128
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.k
                    color: Theme.sub
                    font.family: Theme.sans
                    font.pixelSize: Theme.bodySize
                }
                Text {
                    id: val
                    anchors.left: key.right
                    anchors.leftMargin: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.v
                    color: Theme.text
                    font.family: Theme.sans
                    font.pixelSize: Theme.bodySize
                    wrapMode: Text.WordWrap
                }
                Rectangle {
                    visible: row.index < p.rows.length - 1
                    height: 1
                    color: Theme.line
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: warnRow.implicitHeight + 24
        radius: Theme.radius
        color: Qt.rgba(Theme.bad.r, Theme.bad.g, Theme.bad.b, Theme.dark ? 0.13 : 0.08)
        border.width: 1
        border.color: Qt.rgba(Theme.bad.r, Theme.bad.g, Theme.bad.b, 0.35)
        RowLayout {
            id: warnRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12
            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 22
                implicitHeight: 22
                radius: 11
                color: Theme.bad
                Text { anchors.centerIn: parent; text: "!"; color: "#ffffff"; font.family: Theme.sans; font.pixelSize: 14; font.weight: Font.Bold }
            }
            Text {
                Layout.fillWidth: true
                text: Inst.dryRun
                      ? "This is a dry run. The installer will go through every step without changing your disks."
                      : Inst.mode === "erase"
                        ? "All files, apps and operating systems on " + Inst.diskTitle(p.d) + " will be permanently erased."
                        : "The partitions you chose will be formatted, and everything on them will be lost."
                color: Theme.text
                font.family: Theme.sans
                font.pixelSize: 13
                lineHeight: 1.15
                wrapMode: Text.WordWrap
            }
        }
    }

    Text {
        Layout.fillWidth: true
        visible: Inst.planError !== ""
        text: (Inst.planBlocking ? "" : "The plan couldn’t be checked in advance: ") + Inst.planError
        color: Inst.planBlocking ? Theme.bad : Theme.warn
        font.family: Theme.sans
        font.pixelSize: 12
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }

    Text {
        Layout.fillWidth: true
        visible: Inst.planWarn !== ""
        text: Inst.planWarn
        color: Theme.warn
        font.family: Theme.sans
        font.pixelSize: 12
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }

    Disclosure {
        title: "Show Installation Steps"
        visible: Inst.planNotes().length > 0
        KCard {
            padding: 14
            spacing: 6
            Repeater {
                model: Inst.planNotes()
                delegate: Text {
                    required property string modelData
                    required property int index
                    Layout.fillWidth: true
                    text: (index + 1) + ".  " + modelData
                    color: Theme.sub
                    font.family: Theme.sans
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
