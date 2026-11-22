import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

ColumnLayout {
    id: page
    property string key
    property var seed: ({})
    property var d: ({})
    property bool loading: true
    property string error: ""
    property bool moreDesc: false
    readonly property var a: Object.assign({}, seed, d, { key: page.key })
    readonly property bool archLike: a.src === "arch" || a.src === "aur"
    readonly property var perms: d.permissions || []
    readonly property var sec: d.security || null
    readonly property var sandbox: d.sandbox || null
    readonly property string version: d.installedVer && d.remoteVer && d.installedVer !== d.remoteVer ? d.installedVer + " → " + d.remoteVer : (d.remoteVer || d.installedVer || a.ver || "")
    readonly property string sizeText: d.download ? d.download : d.installedSize || ""
    readonly property var catNames: ({ AudioVideo: "Music & Video", Audio: "Music & Audio", Video: "Video", Graphics: "Graphics & Design", Development: "Developer Tools", Game: "Games", Network: "Internet", Office: "Productivity", Utility: "Utilities", System: "System", Education: "Education", Science: "Science", Settings: "Settings", AI: "AI Agents" })
    readonly property string category: {
        var c = (a.cats || []).filter(function (c) { return ["GTK", "Qt", "KDE", "GNOME"].indexOf(c) < 0 })
        for (var i = 0; i < c.length; i++)
            if (catNames[c[i]]) return catNames[c[i]]
        return c[0] || ""
    }
    spacing: Look.mac ? 22 : 20

    function load() {
        page.loading = true
        page.error = ""
        Store.call("app " + Store.q(page.key), function (j) {
            page.loading = false
            if (!j || j.error) {
                page.error = j && j.error ? j.error : "Could not load this app."
                return
            }
            page.d = j
            if (j.installed !== undefined) Store.mark(page.key, !!j.installed)
        })
    }

    Component.onCompleted: load()
    onKeyChanged: { d = ({}); load() }

    Connections {
        target: Store
        function onChanged(k) { if (k === page.key) page.load() }
    }

    function riskTint(r) {
        return r === "high" ? Look.bad : r === "medium" ? Look.warn : Look.good
    }

    component Label: Text {
        color: Look.sub
        font.family: Look.sans
        font.pixelSize: 12
    }

    component Head: Text {
        color: Look.text
        font.family: Look.display
        font.pixelSize: Look.section
        font.weight: Look.win ? Font.DemiBold : Font.Bold
    }

    component Card: Rectangle {
        default property alias content: col.data
        property real pad: 16
        Layout.fillWidth: true
        implicitHeight: col.implicitHeight + pad * 2
        radius: Look.radius
        color: Look.card
        border.width: Look.mac ? 0 : 1
        border.color: Look.cardStroke
        ColumnLayout {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: parent.pad
            spacing: 10
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Look.mac ? 22 : 20

        AppIcon {
            Layout.preferredWidth: Look.win ? 96 : 128
            Layout.preferredHeight: Look.win ? 96 : 128
            Layout.alignment: Qt.AlignTop
            size: Look.win ? 96 : 128
            source: page.a.icon || ""
            name: page.a.name || ""
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Look.mac ? 3 : 4
            RowLayout {
                spacing: 8
                Layout.fillWidth: true
                Text {
                    Layout.preferredWidth: implicitWidth
                    Layout.minimumWidth: Math.min(implicitWidth, 120)
                    text: page.a.name || ""
                    color: Look.text
                    font.family: Look.display
                    font.pixelSize: Look.mac ? 28 : Look.win ? 28 : 26
                    font.weight: Look.win ? Font.DemiBold : Font.Bold
                    elide: Text.ElideRight
                }
                Glyph { visible: !!page.a.verified; name: "verified"; size: 20; stroke: 1.6; color: Look.accentText }
                Item { Layout.fillWidth: true }
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: page.a.summary || ""
                color: Look.sub
                font.family: Look.sans
                font.pixelSize: Look.mac ? 15 : 14
                elide: Text.ElideRight
            }
            Text {
                visible: text !== ""
                text: page.a.dev || ""
                color: Look.mac ? Look.accentText : Look.sub
                font.family: Look.sans
                font.pixelSize: 13
            }
            Text {
                visible: Look.win && text !== ""
                text: [Look.sourceName(page.a.src), page.sizeText, page.version, page.sandbox ? page.sandbox.rating : ""].filter(function (x) { return x }).join("   ·   ")
                color: Look.faint
                font.family: Look.sans
                font.pixelSize: 12
            }
            RowLayout {
                Layout.topMargin: Look.mac ? 10 : 8
                spacing: 10
                GetButton { app: page.a; big: true }
                Btn {
                    visible: Store.isInstalled(page.a) && !Store.ops[page.key] && !page.d.system
                    text: "Remove…"
                    danger: !Look.mac
                    flat: Look.mac
                    onClicked: page.ApplicationWindow.window.confirmRemove(page.a)
                }
                Btn {
                    visible: !!page.d.update && !Store.ops[page.key]
                    text: "Update"
                    primary: true
                    onClicked: Store.update(page.a)
                }
                Text {
                    visible: !!page.d.system
                    text: "Included with KwickOS"
                    color: Look.sub
                    font.family: Look.sans
                    font.pixelSize: 12
                }
                Text {
                    visible: !!Store.ops[page.key]
                    text: Store.ops[page.key] ? Store.ops[page.key].message || "" : ""
                    color: Look.sub
                    font.family: Look.sans
                    font.pixelSize: 12
                    Layout.maximumWidth: 320
                    elide: Text.ElideRight
                }
            }
        }
    }

    Flow {
        Layout.fillWidth: true
        visible: (page.d.alts || []).length > 0 || page.archLike || page.a.src === "flathub" || page.a.src === "apt"
        spacing: 8
        Repeater {
            model: [{ key: page.key, src: page.a.src, ver: page.d.remoteVer || page.a.ver || "", installed: Store.isInstalled(page.a), current: true }].concat(page.d.alts || [])
            delegate: Rectangle {
                id: chip
                required property var modelData
                implicitWidth: chipRow.implicitWidth + 20
                implicitHeight: 30
                radius: Look.win ? 4 : 15
                color: modelData.current ? Qt.rgba(Look.accent.r, Look.accent.g, Look.accent.b, Look.light ? 0.12 : 0.22) : chipArea.containsMouse ? Look.hover : "transparent"
                border.width: 1
                border.color: modelData.current ? Qt.rgba(Look.accent.r, Look.accent.g, Look.accent.b, 0.6) : Look.line
                RowLayout {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 6
                    Rectangle { implicitWidth: 8; implicitHeight: 8; radius: 4; color: Look.sourceTint(chip.modelData.src) }
                    Text { text: Look.sourceName(chip.modelData.src) + (chip.modelData.ver ? "  " + chip.modelData.ver : ""); color: Look.text; font.family: Look.sans; font.pixelSize: 12 }
                    Glyph { visible: chip.modelData.installed; name: "check"; size: 12; stroke: 2; color: Look.good }
                }
                MouseArea {
                    id: chipArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: chip.modelData.current ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: if (!chip.modelData.current) page.ApplicationWindow.window.openApp({ key: chip.modelData.key, src: chip.modelData.src, name: page.a.name, icon: page.a.icon }, true)
                }
            }
        }
    }

    Rectangle { visible: Look.mac; Layout.fillWidth: true; height: 1; color: Look.line }

    RowLayout {
        id: strip
        visible: !Look.win
        Layout.fillWidth: true
        spacing: 0
        readonly property var cells: [
            { label: "SIZE", value: page.sizeText || "—", sub: page.d.download ? "download" : page.d.installedSize ? "installed" : "", glyph: "size" },
            { label: "VERSION", value: page.version || "—", sub: page.d.update ? "update available" : "", glyph: "tag" },
            { label: "SOURCE", value: Look.sourceName(page.a.src), sub: page.a.src === "flathub" ? (page.a.verified ? "verified" : "community") : page.a.src === "apt" ? (page.d.section || "") : page.a.repo || "", glyph: "download" },
            { label: "SANDBOX", value: !page.sandbox ? "—" : page.a.src !== "flathub" ? "None" : page.sandbox.level >= 2 ? "Weak" : page.sandbox.level === 1 ? "Partial" : "Strict", sub: page.sandbox ? page.sandbox.rating : "", glyph: "shield" },
            { label: page.archLike ? "RISK" : "LICENSE", value: page.archLike ? (page.d.risk || page.a.risk || "—") : (page.d.license || page.a.license || "—").split(" ")[0], sub: page.archLike ? (page.d.cve || []).length + " known CVEs" : "", glyph: "lock" }
        ]
        Repeater {
            model: strip.cells
            delegate: Item {
                id: cell
                required property var modelData
                required property int index
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: Look.mac ? 64 : 96
                Rectangle {
                    visible: Look.mac && cell.index > 0
                    width: 1
                    height: 40
                    anchors.verticalCenter: parent.verticalCenter
                    color: Look.line
                }
                Rectangle {
                    visible: Look.gnu
                    anchors.fill: parent
                    anchors.leftMargin: cell.index > 0 ? 5 : 0
                    anchors.rightMargin: cell.index < strip.cells.length - 1 ? 5 : 0
                    radius: 12
                    color: Look.card
                    border.width: 1
                    border.color: Look.cardStroke
                }
                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - 20
                    spacing: Look.mac ? 3 : 4
                    Text { visible: Look.mac; Layout.alignment: Qt.AlignHCenter; text: cell.modelData.label; color: Look.faint; font.family: Look.sans; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 0.5 }
                    Rectangle {
                        visible: Look.gnu
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 32
                        implicitHeight: 32
                        radius: 16
                        color: cell.modelData.label === "SANDBOX" && page.sandbox ? (page.sandbox.level >= 2 ? Look.badBg : page.sandbox.level === 1 ? Look.warnBg : Look.goodBg) : Qt.rgba(Look.accent.r, Look.accent.g, Look.accent.b, 0.15)
                        Glyph { anchors.centerIn: parent; name: cell.modelData.glyph; size: 17; stroke: 1.8; color: cell.modelData.label === "SANDBOX" && page.sandbox ? (page.sandbox.level >= 2 ? Look.bad : page.sandbox.level === 1 ? Look.warn : Look.good) : Look.accentText }
                    }
                    Text { Layout.alignment: Qt.AlignHCenter; Layout.maximumWidth: parent.width; text: cell.modelData.value; color: Look.mac ? Look.sub : Look.text; font.family: Look.sans; font.pixelSize: Look.mac ? 17 : 14; font.weight: Font.Bold; elide: Text.ElideRight; font.capitalization: cell.modelData.label === "RISK" ? Font.Capitalize : Font.MixedCase }
                    Text { Layout.alignment: Qt.AlignHCenter; Layout.maximumWidth: parent.width; text: Look.gnu ? cell.modelData.label.charAt(0) + cell.modelData.label.slice(1).toLowerCase() + (cell.modelData.sub ? " · " + cell.modelData.sub : "") : cell.modelData.sub; visible: text !== ""; color: Look.faint; font.family: Look.sans; font.pixelSize: 11; elide: Text.ElideRight }
                }
            }
        }
    }

    Rectangle { visible: Look.mac; Layout.fillWidth: true; height: 1; color: Look.line }

    Text {
        visible: page.loading && !page.d.name
        text: "Loading…"
        color: Look.sub
        font.family: Look.sans
        font.pixelSize: 13
    }

    Text {
        visible: page.error !== ""
        Layout.fillWidth: true
        text: page.error
        color: Look.bad
        font.family: Look.sans
        font.pixelSize: 13
        wrapMode: Text.WordWrap
    }

    ListView {
        id: shots
        visible: (page.a.shots || []).length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: Look.gnu ? 360 : 300
        orientation: ListView.Horizontal
        spacing: 14
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: page.a.shots || []
        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: Rectangle {
            id: sh
            required property var modelData
            height: shots.height - 14
            width: img.status === Image.Ready && img.implicitHeight > 0 ? Math.min(shots.width * 0.9, height * img.implicitWidth / img.implicitHeight) : height * 16 / 10
            radius: Look.mac ? 10 : 8
            color: Look.card
            border.width: 1
            border.color: Look.line
            clip: true
            Image {
                id: img
                anchors.fill: parent
                anchors.margins: 1
                source: sh.modelData.thumb
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                sourceSize.height: 760
                smooth: true
                mipmap: true
            }
            BusyIndicator { anchors.centerIn: parent; running: img.status === Image.Loading; visible: running; width: 28; height: 28 }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sh.ApplicationWindow.window.showShot(sh.modelData.full, sh.modelData.caption) }
        }
    }

    ColumnLayout {
        visible: (page.a.desc || "") !== ""
        Layout.fillWidth: true
        spacing: 6
        Head { visible: !Look.mac; text: "About" }
        Text {
            id: desc
            Layout.fillWidth: true
            text: page.a.desc || ""
            textFormat: Text.RichText
            color: Look.text
            font.family: Look.sans
            font.pixelSize: Look.mac ? 14 : Look.body
            wrapMode: Text.WordWrap
            lineHeight: 1.25
            maximumLineCount: page.moreDesc ? 400 : 6
            elide: Text.ElideRight
            onLinkActivated: function (l) { Qt.openUrlExternally(l) }
        }
        Text {
            visible: !page.moreDesc && desc.truncated
            text: "more"
            color: Look.accentText
            font.family: Look.sans
            font.pixelSize: 13
            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: page.moreDesc = true }
        }
    }

    ColumnLayout {
        visible: (page.a.notes || "") !== "" || !!(page.d.update && page.d.update.to)
        Layout.fillWidth: true
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            Head { Layout.fillWidth: true; text: "What’s New" }
            Label { text: page.a.ver ? "Version " + page.a.ver : "" }
        }
        Text {
            Layout.fillWidth: true
            text: page.a.notes || ("Version " + (page.d.update ? page.d.update.to : ""))
            textFormat: Text.RichText
            color: Look.text
            font.family: Look.sans
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            lineHeight: 1.2
            maximumLineCount: 8
            elide: Text.ElideRight
        }
    }

    ColumnLayout {
        visible: page.archLike && page.a.src === "aur"
        Layout.fillWidth: true
        spacing: 8
        Head { text: "Build Script" }
        Card {
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Glyph { name: "code"; size: 22; stroke: 1.8; color: page.riskTint(page.d.risk || page.a.risk) }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { text: "PKGBUILD · " + ((page.d.risk || page.a.risk || "unknown") + " risk"); color: Look.text; font.family: Look.sans; font.pixelSize: 14; font.weight: Font.DemiBold; font.capitalization: Font.MixedCase }
                    Label { Layout.fillWidth: true; text: (page.d.findings || []).length + " finding" + ((page.d.findings || []).length === 1 ? "" : "s") + " from the KwickOS risk check. You review the script before anything is built."; wrapMode: Text.WordWrap }
                }
                Btn { text: "Review…"; onClicked: page.ApplicationWindow.window.reviewAur(page.a, page.d) }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Math.min(180, pk.implicitHeight + 20)
                radius: 6
                color: Look.light ? "#f6f6f8" : "#1a1a1c"
                clip: true
                Text {
                    id: pk
                    x: 10
                    y: 10
                    width: parent.width - 20
                    text: (page.d.pkgbuild || "").split("\n").slice(0, 14).join("\n")
                    color: Look.sub
                    font.family: Look.mono
                    font.pixelSize: 11
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: !!page.sandbox || !!page.sec
        spacing: 10
        Head { text: Look.mac ? "App Privacy & Security" : Look.win ? "Permissions and security" : "Safety" }

        GridLayout {
            Layout.fillWidth: true
            columns: page.width > 760 ? 2 : 1
            columnSpacing: 12
            rowSpacing: 12

            Card {
                Layout.alignment: Qt.AlignTop
                RowLayout {
                    spacing: 10
                    Rectangle {
                        implicitWidth: 36
                        implicitHeight: 36
                        radius: 18
                        color: !page.sandbox ? Look.hover : page.sandbox.level >= 2 ? Look.badBg : page.sandbox.level === 1 ? Look.warnBg : Look.goodBg
                        Glyph { anchors.centerIn: parent; name: "shield"; size: 20; stroke: 1.8; color: !page.sandbox ? Look.sub : page.sandbox.level >= 2 ? Look.bad : page.sandbox.level === 1 ? Look.warn : Look.good }
                    }
                    ColumnLayout {
                        spacing: 1
                        Text { text: page.sandbox ? page.sandbox.rating : ""; color: Look.text; font.family: Look.sans; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Label { text: "Sandbox" }
                    }
                }
                Label { Layout.fillWidth: true; text: page.sandbox ? page.sandbox.text : ""; wrapMode: Text.WordWrap }
                Repeater {
                    model: page.perms
                    delegate: RowLayout {
                        id: pr
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 10
                        Glyph { name: pr.modelData.id === "escape" ? "escape" : pr.modelData.id; size: 18; stroke: 1.7; color: pr.modelData.level >= 2 ? Look.bad : pr.modelData.level === 1 ? Look.warn : pr.modelData.level < 0 ? Look.good : Look.sub }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text { text: pr.modelData.title; color: Look.text; font.family: Look.sans; font.pixelSize: 13 }
                            Label { Layout.fillWidth: true; text: pr.modelData.detail; wrapMode: Text.WordWrap }
                        }
                    }
                }
            }

            Card {
                Layout.alignment: Qt.AlignTop
                RowLayout {
                    spacing: 10
                    Rectangle {
                        implicitWidth: 36
                        implicitHeight: 36
                        radius: 18
                        color: !page.sec ? Look.hover : page.sec.level === "bad" ? Look.badBg : page.sec.level === "warn" ? Look.warnBg : page.sec.level === "ok" ? Look.goodBg : Look.hover
                        Glyph { anchors.centerIn: parent; name: !page.sec || page.sec.level === "ok" ? "shieldok" : "warning"; size: 20; stroke: 1.8; color: !page.sec ? Look.sub : page.sec.level === "bad" ? Look.bad : page.sec.level === "warn" ? Look.warn : page.sec.level === "ok" ? Look.good : Look.sub }
                    }
                    ColumnLayout {
                        spacing: 1
                        Text { text: !page.sec ? "Checking…" : page.sec.level === "bad" ? "Known vulnerabilities" : page.sec.level === "warn" ? "Needs attention" : page.sec.level === "ok" ? "No known issues" : "Limited support"; color: Look.text; font.family: Look.sans; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Label { text: "Security" }
                    }
                }
                Label { Layout.fillWidth: true; text: page.sec ? page.sec.text : ""; wrapMode: Text.WordWrap }
                Repeater {
                    model: page.d.cve || []
                    delegate: RowLayout {
                        id: cv
                        required property var modelData
                        readonly property string cid: typeof modelData === "string" ? modelData : (modelData.id || modelData.name || "")
                        spacing: 8
                        Rectangle { implicitWidth: 6; implicitHeight: 6; radius: 3; color: Look.bad }
                        Text {
                            text: cv.cid + (typeof cv.modelData === "object" && cv.modelData.severity ? "  ·  " + cv.modelData.severity : "")
                            color: Look.accentText
                            font.family: Look.mono
                            font.pixelSize: 12
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Qt.openUrlExternally("https://security.archlinux.org/" + cv.cid) }
                        }
                    }
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        Head { text: "Information" }
        GridLayout {
            id: info
            Layout.fillWidth: true
            columns: page.width > 760 ? 3 : 2
            columnSpacing: 24
            rowSpacing: 14
            readonly property var rows: [
                ["Source", Look.sourceName(page.a.src) + (page.a.repo ? " (" + page.a.repo + ")" : page.d.remote && page.d.remote !== "flathub" ? " (" + page.d.remote + ")" : "")],
                ["Developer", page.a.dev || ""],
                ["Size", page.d.installedSize ? page.d.installedSize + " installed" + (page.d.download ? ", " + page.d.download + " download" : "") : page.d.download || ""],
                ["Category", page.category],
                ["Version", page.version],
                ["License", page.d.license || page.a.license || ""],
                ["Package", page.a.src === "flathub" ? page.a.id : page.d.pkg || page.a.pkg || page.a.id || ""],
                ["Runtime", page.d.runtimeName || ""],
                ["Installed", Store.isInstalled(page.a) ? (page.d.installedVer ? "Yes, " + page.d.installedVer : "Yes") + (page.d.scope === "user" ? " (just for you)" : "") : "No"]
            ].filter(function (r) { return !!r[1] })
            Repeater {
                model: info.rows
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 2
                    Label { text: String(parent.modelData[0] || "") }
                    Text { Layout.fillWidth: true; text: String(parent.modelData[1] || ""); color: Look.text; font.family: Look.sans; font.pixelSize: 13; wrapMode: Text.WrapAnywhere; maximumLineCount: 2; elide: Text.ElideRight }
                }
            }
        }
        RowLayout {
            visible: (page.d.home || page.a.home || "") !== ""
            spacing: 6
            Glyph { name: "external"; size: 14; stroke: 1.8; color: Look.accentText }
            Text {
                text: "Website"
                color: Look.accentText
                font.family: Look.sans
                font.pixelSize: 13
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Qt.openUrlExternally(page.d.home || page.a.home) }
            }
        }
    }

    Item { implicitHeight: 12 }
}
