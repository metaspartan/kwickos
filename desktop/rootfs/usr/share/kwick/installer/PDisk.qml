import QtQuick
import QtQuick.Layouts

PageFrame {
    id: p
    icon: "icons/drive-internal.svg"
    title: "Select a Disk"
    subtitle: "Choose the disk where you want to install KwickOS."
    maxWidth: 640
    canContinue: Inst.diskValid()
    firstFocus: tiles

    readonly property var sel: Inst.diskByPath(Inst.disk)
    readonly property var usableDisks: Inst.disks.filter(function (d) { return Inst.usable(d) })

    Component.onCompleted: {
        if (!Inst.disksLoaded) Inst.loadDisks()
        if (Inst.mode === "manual") Inst.loadPartitions()
    }

    Connections {
        target: Inst
        function onDiskChanged() { if (Inst.mode === "manual") Inst.loadPartitions() }
        function onModeChanged() {
            if (Inst.mode === "manual") { Inst.loadPartitions(); Inst.encrypt = false }
        }
    }

    function partOptions(allowNone) {
        var o = allowNone ? [{ id: "", label: "None" }] : []
        Inst.partitions.forEach(function (x) {
            var bits = [Inst.bytes(x.size)]
            if (x.fstype) bits.push(x.fstype)
            if (x.label) bits.push("“" + x.label + "”")
            o.push({ id: x.path, label: x.path.replace("/dev/", "") + "  ·  " + bits.join(", "), sub: "" })
        })
        return o
    }

    function moveSel(d) {
        var list = Inst.disks
        var i = -1
        for (var k = 0; k < list.length; k++) if (list[k].path === Inst.disk) i = k
        for (var j = i + d; j >= 0 && j < list.length; j += d) {
            if (Inst.usable(list[j])) { Inst.disk = list[j].path; return }
        }
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: 160
        visible: !Inst.disksLoaded
        Column {
            anchors.centerIn: parent
            spacing: 12
            Spinner { anchors.horizontalCenter: parent.horizontalCenter; size: 22 }
            Text { text: "Looking for disks…"; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 13 }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: Inst.disksLoaded && p.usableDisks.length === 0
        spacing: 12
        Text {
            Layout.fillWidth: true
            Layout.topMargin: 20
            text: Inst.disksError !== "" ? Inst.disksError : "No disk large enough for KwickOS was found. Connect a disk of at least " + Inst.bytes(Inst.minDiskBytes) + ", then check again."
            color: Inst.disksError !== "" ? Theme.bad : Theme.sub
            font.family: Theme.sans
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
        KButton {
            Layout.alignment: Qt.AlignHCenter
            text: "Check Again"
            onClicked: Inst.loadDisks()
        }
    }

    FocusScope {
        id: tiles
        Layout.fillWidth: true
        implicitHeight: flow.implicitHeight
        visible: Inst.disksLoaded && Inst.disks.length > 0
        activeFocusOnTab: true
        Keys.onLeftPressed: p.moveSel(-1)
        Keys.onRightPressed: p.moveSel(1)

        Flow {
            id: flow
            width: Math.min(parent.width, Inst.disks.length * 172 - 12)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            Repeater {
                model: Inst.disks
                delegate: Item {
                    id: tile
                    required property var modelData
                    readonly property bool ok: Inst.usable(modelData)
                    readonly property bool on: Inst.disk === modelData.path
                    width: 160
                    height: 176

                    Rectangle {
                        anchors.fill: parent
                        radius: 14
                        color: tile.on ? Theme.accentSoft : tma.containsMouse && tile.ok ? Theme.hover : "transparent"
                        border.width: tile.on ? 2 : 0
                        border.color: Theme.accent
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -4
                        radius: 18
                        color: "transparent"
                        border.width: 3
                        border.color: Theme.focusRing
                        visible: tile.on && tiles.activeFocus
                    }

                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 12
                        width: parent.width - 20
                        spacing: 4
                        opacity: tile.ok ? 1 : 0.42

                        Image {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 76
                            height: 76
                            source: tile.modelData.removable || tile.modelData.transport === "usb" ? "icons/drive-external.svg" : "icons/drive-internal.svg"
                            sourceSize.width: 152
                            sourceSize.height: 152
                            smooth: true
                        }
                        Text {
                            width: parent.width
                            topPadding: 4
                            text: Inst.diskTitle(tile.modelData)
                            color: Theme.text
                            font.family: Theme.sans
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                        }
                        Text {
                            width: parent.width
                            text: Inst.bytes(tile.modelData.size) + (tile.modelData.size > 0 ? " · " : "") + Inst.transportName(tile.modelData)
                            color: Theme.sub
                            font.family: Theme.sans
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            visible: !tile.ok
                            text: tile.modelData.live ? "KwickOS installer" : "Too small"
                            color: Theme.sub
                            font.family: Theme.sans
                            font.pixelSize: 11
                            font.italic: true
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    MouseArea {
                        id: tma
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: tile.ok
                        cursorShape: tile.ok ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: { Inst.disk = tile.modelData.path; tiles.forceActiveFocus() }
                    }
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: 10
        spacing: 14
        visible: Inst.disksLoaded && p.usableDisks.length > 0
        opacity: p.sel ? 1 : 0.5
        enabled: !!p.sel

        KSeg {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 320
            fill: true
            options: [{ id: "erase", label: "Erase Disk" }, { id: "manual", label: "Use Partitions" }]
            current: Inst.mode
            onPicked: (id) => Inst.mode = id
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            text: !p.sel ? "Select a disk to continue."
                  : Inst.mode === "erase"
                    ? "KwickOS will use the whole of “" + Inst.diskTitle(p.sel) + "”. Everything on it will be erased."
                    : "Install into partitions that already exist on “" + Inst.diskTitle(p.sel) + "”. The partitions you choose will be formatted."
            color: Theme.sub
            font.family: Theme.sans
            font.pixelSize: 13
            lineHeight: 1.15
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        KCard {
            visible: Inst.mode === "manual" && !!p.sel
            KRow {
                title: "System"
                subtitle: "Required. KwickOS is installed here."
                KPopup {
                    implicitWidth: 250
                    options: p.partOptions(false)
                    current: Inst.rootPart
                    placeholder: Inst.partitions.length ? "Choose…" : "No partitions"
                    onPicked: (id) => Inst.rootPart = id
                }
            }
            KRow {
                title: "EFI system partition"
                subtitle: Inst.firmware === "uefi" ? "Required on this computer" : "Optional on BIOS computers"
                KPopup {
                    implicitWidth: 250
                    options: p.partOptions(Inst.firmware !== "uefi")
                    current: Inst.efiPart
                    placeholder: Inst.partitions.length ? "Choose…" : "No partitions"
                    onPicked: (id) => Inst.efiPart = id
                }
            }
            KRow {
                title: "Home"
                subtitle: "Optional. Keeps your files on their own partition."
                last: true
                KPopup {
                    implicitWidth: 250
                    options: p.partOptions(true)
                    current: Inst.homePart
                    onPicked: (id) => Inst.homePart = id
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: Inst.mode === "manual" && !!p.sel && text !== ""
            text: {
                if (Inst.partitions.length === 0) return "This disk has no partitions. Choose Erase Disk, or partition it first with a disk utility."
                if (Inst.rootPart === "") return "Choose a partition for the system."
                if (Inst.rootPart === Inst.efiPart) return "The system and EFI partitions must be different."
                if (Inst.homePart !== "" && (Inst.homePart === Inst.rootPart || Inst.homePart === Inst.efiPart)) return "Home needs its own partition."
                if (Inst.firmware === "uefi" && Inst.efiPart === "") return "This computer starts with UEFI, so an EFI system partition is required."
                return ""
            }
            color: Theme.bad
            font.family: Theme.sans
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Disclosure {
            id: adv
            Layout.topMargin: 6
            title: "Advanced Options"
            open: Inst.encrypt || Inst.fs !== "ext4"

            KCard {
                KRow {
                    title: "File system"
                    subtitle: Inst.fs === "btrfs" ? "Snapshots and compression" : Inst.fs === "xfs" ? "Fast with very large files" : "The dependable default"
                    KSeg {
                        options: [{ id: "ext4", label: "ext4" }, { id: "btrfs", label: "Btrfs" }, { id: "xfs", label: "XFS" }]
                        current: Inst.fs
                        onPicked: (id) => Inst.fs = id
                    }
                }
                KRow {
                    title: "Swap"
                    subtitle: Inst.swap === "zram" ? "Compressed memory, no disk space used" : Inst.swap === "none" ? "Not recommended with little memory" : "A swap file on the system disk"
                    KSeg {
                        options: [{ id: "zram", label: "zram" }, { id: "file:4G", label: "4 GB File" }, { id: "none", label: "None" }]
                        current: Inst.swap
                        onPicked: (id) => Inst.swap = id
                    }
                }
                KRow {
                    title: "Encrypt the disk"
                    subtitle: Inst.mode === "erase" ? "You’ll enter a passphrase every time the computer starts" : "Available when erasing the disk"
                    last: !Inst.encrypt
                    dim: Inst.mode !== "erase"
                    KToggle {
                        enabled: Inst.mode === "erase"
                        checked: Inst.encrypt && Inst.mode === "erase"
                        onToggled: (v) => Inst.encrypt = v
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: 16
                    Layout.topMargin: 12
                    visible: Inst.encrypt && Inst.mode === "erase"
                    spacing: 10
                    KField {
                        id: pp1
                        Layout.fillWidth: true
                        password: true
                        placeholder: "Passphrase"
                        text: Inst.passphrase
                        invalid: p.attempted && Inst.passphrase.length < 8
                        onEdited: Inst.passphrase = text
                    }
                    KField {
                        Layout.fillWidth: true
                        password: true
                        placeholder: "Verify passphrase"
                        text: Inst.passphrase2
                        invalid: Inst.passphrase2 !== "" && Inst.passphrase2 !== Inst.passphrase
                        onEdited: Inst.passphrase2 = text
                    }
                    Text {
                        Layout.fillWidth: true
                        text: Inst.passphrase.length > 0 && Inst.passphrase.length < 8 ? "Use at least 8 characters."
                              : Inst.passphrase2 !== "" && Inst.passphrase2 !== Inst.passphrase ? "The passphrases don’t match."
                              : "If you forget this passphrase, your data can’t be recovered."
                        color: (Inst.passphrase.length > 0 && Inst.passphrase.length < 8) || (Inst.passphrase2 !== "" && Inst.passphrase2 !== Inst.passphrase) ? Theme.bad : Theme.sub
                        font.family: Theme.sans
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Text {
                Layout.leftMargin: 4
                Layout.topMargin: 4
                visible: Inst.bootloaders.length > 0
                text: "BOOT LOADER" + (Inst.firmware ? "  ·  " + Inst.firmware.toUpperCase() + " FIRMWARE" : "")
                color: Theme.sub
                font.family: Theme.sans
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.letterSpacing: 0.4
            }

            KCard {
                visible: Inst.bootloaders.length > 0
                Repeater {
                    model: Inst.bootloaders
                    delegate: KRow {
                        id: br
                        required property string modelData
                        required property int index
                        title: Inst.bootName(modelData)
                        subtitle: Inst.bootSub(modelData)
                        last: index === Inst.bootloaders.length - 1
                        Rectangle {
                            visible: br.modelData === Inst.bootDefault
                            implicitWidth: rec.implicitWidth + 14
                            implicitHeight: 20
                            radius: 10
                            color: Theme.accentSoft
                            Text {
                                id: rec
                                anchors.centerIn: parent
                                text: "Recommended"
                                color: Theme.accent
                                font.family: Theme.sans
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                        }
                        Rectangle {
                            implicitWidth: 20
                            implicitHeight: 20
                            radius: 10
                            color: Inst.bootloader === br.modelData ? Theme.accent : "transparent"
                            border.width: Inst.bootloader === br.modelData ? 0 : 1.5
                            border.color: Theme.faint
                            Rectangle {
                                anchors.centerIn: parent
                                width: 8
                                height: 8
                                radius: 4
                                color: "#ffffff"
                                visible: Inst.bootloader === br.modelData
                            }
                        }
                        MouseArea {
                            parent: br
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { Inst.bootloader = br.modelData; Inst.bootTouched = true }
                        }
                    }
                }
            }
        }
    }
}
