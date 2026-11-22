import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

ColumnLayout {
    id: page
    readonly property var u: Store.updates || ({})
    readonly property var apps: (u.apps || []).filter(function (a) { return a.src !== "apt" })
    readonly property var debApps: (u.apps || []).filter(function (a) { return a.src === "apt" })
    readonly property var system: u.system || []
    readonly property var arch: u.arch || []
    readonly property int security: system.filter(function (s) { return s.security }).length
    readonly property int total: apps.length + system.length + arch.length
    readonly property bool working: !!Store.ops["__all__"] || !!Store.ops["__arch__"] || Store.checking
    spacing: 16

    function bytes(n) {
        if (!n) return ""
        if (n >= 1e9) return (n / 1e9).toFixed(1) + " GB"
        if (n >= 1e6) return (n / 1e6).toFixed(1) + " MB"
        if (n >= 1e3) return Math.round(n / 1e3) + " KB"
        return n + " bytes"
    }

    function when(t) {
        if (!t) return "never"
        var d = new Date(t * 1000)
        var n = new Date()
        var time = Qt.formatTime(d, "h:mm AP")
        if (d.toDateString() === n.toDateString()) return "today at " + time
        var y = new Date(n.getFullYear(), n.getMonth(), n.getDate() - 1)
        if (d.toDateString() === y.toDateString()) return "yesterday at " + time
        return Qt.formatDate(d, "MMM d") + " at " + time
    }

    Component.onCompleted: Store.loadUpdates()

    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text { Layout.fillWidth: true; text: "Updates"; color: Look.text; font.family: Look.display; font.pixelSize: Look.titleSize; font.weight: Look.win ? Font.DemiBold : Font.Bold }
            Text {
                text: Store.checking ? "Checking for updates…" : page.u.available === false ? "Software Update is not installed" : "Last checked " + page.when(page.u.checked)
                color: Look.sub
                font.family: Look.sans
                font.pixelSize: 13
            }
        }
        BusyIndicator { running: Store.updatesLoading || Store.checking; visible: running; implicitWidth: 24; implicitHeight: 24 }
        Btn { text: "Check for Updates"; glyph: Look.win ? "refresh" : ""; enabled: !page.working; onClicked: Store.checkUpdates() }
        Btn {
            visible: page.total > 0
            primary: true
            enabled: !page.working
            text: Store.ops["__all__"] ? (Store.ops["__all__"].progress >= 0 ? "Updating " + Store.ops["__all__"].progress + "%" : "Updating…") : "Update All"
            onClicked: Store.updateAll()
        }
    }

    Rectangle {
        visible: !!Store.ops["__all__"]
        Layout.fillWidth: true
        implicitHeight: 6
        radius: 3
        color: Look.line
        Rectangle {
            height: parent.height
            radius: 3
            color: Look.accent
            width: parent.width * Math.max(0.03, (Store.ops["__all__"] ? Math.max(0, Store.ops["__all__"].progress) : 0) / 100)
            Behavior on width { NumberAnimation { duration: 300 } }
        }
    }
    Text {
        visible: !!Store.ops["__all__"]
        text: Store.ops["__all__"] ? Store.ops["__all__"].message || "" : ""
        color: Look.sub
        font.family: Look.sans
        font.pixelSize: 12
    }

    Text {
        visible: (page.u.error || "") !== ""
        Layout.fillWidth: true
        text: "Could not reach every update server: " + (page.u.error || "")
        color: Look.warn
        font.family: Look.sans
        font.pixelSize: 12
        wrapMode: Text.WordWrap
    }

    ColumnLayout {
        visible: Store.updatesLoaded && page.total === 0 && !Store.checking
        Layout.fillWidth: true
        Layout.topMargin: 50
        spacing: 10
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 72
            implicitHeight: 72
            radius: 36
            color: Look.goodBg
            Glyph { anchors.centerIn: parent; name: "check"; size: 36; stroke: 2.6; color: Look.good }
        }
        Text { Layout.alignment: Qt.AlignHCenter; text: "Your apps are up to date"; color: Look.text; font.family: Look.display; font.pixelSize: 20; font.weight: Font.DemiBold }
        Text { Layout.alignment: Qt.AlignHCenter; text: "Apps from Flathub, Debian" + (Store.archOn ? ", Arch Linux" : "") + " and KwickOS are checked together."; color: Look.sub; font.family: Look.sans; font.pixelSize: 13 }
    }

    component Section: Text {
        Layout.topMargin: 6
        color: Look.text
        font.family: Look.display
        font.pixelSize: Look.section
        font.weight: Look.win ? Font.DemiBold : Font.Bold
    }

    component Group: Rectangle {
        default property alias rows: col.data
        Layout.fillWidth: true
        implicitHeight: col.implicitHeight + (Look.gnu ? 2 : 0)
        radius: Look.gnu ? 12 : 0
        color: "transparent"
        border.width: Look.gnu ? 1 : 0
        border.color: Look.cardStroke
        clip: Look.gnu
        ColumnLayout {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Look.gnu ? 1 : 0
            spacing: 0
        }
    }

    Section { visible: page.apps.length + page.debApps.length > 0; text: "Apps" }
    Group {
        visible: page.apps.length + page.debApps.length > 0
        Repeater {
            model: page.apps.concat(page.debApps)
            delegate: AppRow {
                required property var modelData
                required property int index
                app: modelData
                updateMode: true
                last: index === page.apps.length + page.debApps.length - 1
                detail: (modelData.from ? modelData.from + "  →  " : "") + (modelData.to || "") + (modelData.size ? "  ·  " + page.bytes(modelData.size) : "")
            }
        }
    }

    Section { visible: page.arch.length > 0; text: "Arch Linux" }
    Group {
        visible: page.arch.length > 0
        Repeater {
            model: page.arch
            delegate: AppRow {
                required property var modelData
                required property int index
                app: modelData
                updateMode: true
                last: index === page.arch.length - 1
                detail: (modelData.from ? modelData.from + "  →  " : "") + (modelData.to || "")
            }
        }
    }

    Section { visible: page.system.length > 0; text: "KwickOS" }
    Rectangle {
        visible: page.system.length > 0 || page.u.release_available
        Layout.fillWidth: true
        implicitHeight: sysRow.implicitHeight + 28
        radius: Look.radius
        color: Look.card
        border.width: Look.mac ? 0 : 1
        border.color: Look.cardStroke
        RowLayout {
            id: sysRow
            anchors.fill: parent
            anchors.margins: 14
            spacing: 14
            Image { Layout.preferredWidth: 48; Layout.preferredHeight: 48; source: "/usr/share/kwick/settings/icons/obj-update.svg"; sourceSize.width: 96; sourceSize.height: 96 }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                RowLayout {
                    spacing: 6
                    Text { text: page.u.release_available ? "KwickOS " + (page.u.release_latest || "") : "System Updates"; color: Look.text; font.family: Look.sans; font.pixelSize: 14; font.weight: Font.DemiBold }
                    Badge { visible: page.security > 0; label: page.security + " security"; tint: Look.warn }
                }
                Text {
                    Layout.fillWidth: true
                    text: page.system.length + " package" + (page.system.length === 1 ? "" : "s") + "  ·  " + page.bytes(page.system.reduce(function (a, s) { return a + (s.size || 0) }, 0)) + ".  Kernels, restarts and automatic updates are in Software Update."
                    color: Look.sub
                    font.family: Look.sans
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }
            Btn { text: "Software Update…"; flat: Look.mac; onClicked: Store.run("setsid kwick-software-update >/dev/null 2>&1 &") }
            Btn {
                visible: page.system.length > 0
                primary: true
                enabled: !page.working && !Store.ops["__sys__"]
                text: Store.ops["__sys__"] ? (Store.ops["__sys__"].progress >= 0 ? Store.ops["__sys__"].progress + "%" : "Updating…") : "Update"
                onClicked: Store.enqueue("updatesys", { key: "__sys__", src: "system", name: "System updates" })
            }
        }
    }

    Item { implicitHeight: 8 }
}
