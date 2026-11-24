import QtQuick
import KwickQuickLook

Rectangle {
    id: root

    readonly property bool dark: ql.dark
    readonly property color accent: ql.accent
    readonly property color ink: dark ? "#ffffff" : "#000000"
    readonly property color label: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.92 : 0.86)
    readonly property color secondary: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.55 : 0.5)
    readonly property color tertiary: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.3 : 0.28)
    readonly property color hairline: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.1 : 0.09)
    readonly property color hover: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.09 : 0.055)
    readonly property color pressed: Qt.rgba(ink.r, ink.g, ink.b, dark ? 0.15 : 0.1)
    readonly property color window: dark ? "#1e1e1e" : "#f5f5f5"
    readonly property color toolbar: dark ? "#2a2a2a" : "#ececec"
    readonly property color card: dark ? "#292929" : "#ffffff"
    readonly property real ratio: Math.max(0.8, Math.min(1.3, ql.radius / 10))
    readonly property real small: Math.round(7 * ratio)
    readonly property int barHeight: 46
    readonly property string sans: "Inter"
    readonly property string mono: "JetBrains Mono"

    function glyph(name, tint) {
        return "image://glyph/" + name + "/" + tint.toString().substring(1)
    }

    function preferred() {
        const k = ql.kind
        if (k === "image" || k === "animation") {
            const w = ql.imageSize.width > 0 ? ql.imageSize.width : 800
            const h = ql.imageSize.height > 0 ? ql.imageSize.height : 600
            const s = Math.max(1, Math.min(w, h) < 240 ? 240 / Math.min(w, h) : 1)
            return Qt.size(Math.max(420, w * s), h * s + barHeight)
        }
        if (k === "pdf" || (k === "office" && ql.pdf !== ""))
            return Qt.size(820, ql.pageSize.width > 0 ? 820 * ql.pageSize.height / ql.pageSize.width + barHeight + 40 : 1100)
        if (k === "text" || k === "markdown")
            return Qt.size(880, 680)
        if (k === "video")
            return Qt.size(1024, 576 + barHeight)
        if (k === "audio")
            return Qt.size(560, 380)
        if (k === "font")
            return Qt.size(780, 560)
        if (k === "archive" || k === "folder")
            return Qt.size(640, 580)
        return Qt.size(560, 380)
    }

    color: window
    focus: true

    Connections {
        target: ql
        function onCurrentChanged() {
            if (ql.index >= 0) {
                const p = root.preferred()
                ql.fit(p.width, p.height, ql.kind === "image" || ql.kind === "animation" || ql.kind === "video")
            }
        }
        function onContentChanged() {
            if (ql.index >= 0 && ql.kind === "office") {
                const p = root.preferred()
                ql.fit(p.width, p.height, ql.kind === "image" || ql.kind === "animation" || ql.kind === "video")
            }
        }
    }

    Shortcut { sequences: ["Escape", "Space", "Ctrl+W"]; onActivated: ql.close() }
    Shortcut { sequence: "Left"; onActivated: ql.step(-1, 4) }
    Shortcut { sequence: "Right"; onActivated: ql.step(1, 5) }
    Shortcut { sequence: "Up"; onActivated: ql.step(-1, 2) }
    Shortcut { sequence: "Down"; onActivated: ql.step(1, 3) }
    Shortcut { sequences: ["Return", "Enter", "Ctrl+O"]; onActivated: ql.open() }
    Shortcut { sequences: ["F", "F11"]; onActivated: ql.toggleFullScreen() }
    Shortcut {
        sequence: "Ctrl+C"
        enabled: ql.kind !== "text" && ql.kind !== "markdown"
        onActivated: {
            ql.copyPath()
            copied.restart()
        }
    }

    Timer {
        id: copied
        interval: 1400
    }

    Rectangle {
        id: bar
        width: parent.width
        height: root.barHeight
        color: root.toolbar

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: root.hairline
        }

        Row {
            id: nav
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            visible: ql.count > 1 || ql.kind !== ""
            ToolGlyph { theme: root; icon: "prev"; tip: "Previous"; onClicked: ql.step(-1, 4) }
            ToolGlyph { theme: root; icon: "next"; tip: "Next"; onClicked: ql.step(1, 5) }
        }

        Column {
            anchors.left: nav.right
            anchors.leftMargin: 10
            anchors.right: actions.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
                width: parent.width
                text: ql.name
                color: root.label
                font.family: root.sans
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideMiddle
                renderType: Text.NativeRendering
            }
            Text {
                width: parent.width
                text: copied.running ? "Copied to Clipboard" : (ql.count > 1 ? (ql.index + 1) + " of " + ql.count + "  ·  " : "") + ql.details
                color: copied.running ? root.accent : root.secondary
                font.family: root.sans
                font.pixelSize: 11
                elide: Text.ElideRight
                renderType: Text.NativeRendering
            }
        }

        Row {
            id: actions
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            ToolGlyph { theme: root; icon: "reveal"; tip: "Show in Files"; onClicked: ql.reveal() }
            ToolGlyph { theme: root; icon: "nearby"; tip: "Send Nearby…"; onClicked: ql.share() }
            ToolGlyph { theme: root; icon: "share"; tip: "Copy"; onClicked: { ql.copyPath(); copied.restart() } }
            ToolGlyph { theme: root; icon: "expand"; tip: "Full Screen"; onClicked: ql.toggleFullScreen() }
            Rectangle {
                id: openButton
                visible: ql.appName !== ""
                anchors.verticalCenter: parent.verticalCenter
                height: 28
                width: openLabel.implicitWidth + 26
                radius: root.small
                color: openArea.pressed ? Qt.darker(root.accent, 1.15) : openArea.containsMouse ? Qt.lighter(root.accent, 1.08) : root.accent
                Text {
                    id: openLabel
                    anchors.centerIn: parent
                    text: bar.width < 760 ? "Open" : "Open with " + ql.appName
                    color: "#ffffff"
                    font.family: root.sans
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    renderType: Text.NativeRendering
                }
                MouseArea {
                    id: openArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ql.open()
                }
            }
        }
    }

    Loader {
        id: body
        anchors.top: bar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        asynchronous: false
        sourceComponent: {
            switch (ql.kind) {
            case "image":
            case "animation":
                return imageView
            case "pdf":
                return pdfView
            case "office":
                return ql.pdf !== "" ? pdfView : infoView
            case "text":
                return textView
            case "markdown":
                return markdownView
            case "video":
            case "audio":
                return mediaView
            case "archive":
            case "folder":
                return listView
            case "font":
                return fontView
            case "":
                return null
            default:
                return infoView
            }
        }
    }

    Component { id: imageView; ImagePreview { theme: root } }
    Component { id: pdfView; PdfPreview { theme: root } }
    Component { id: textView; TextPreview { theme: root; markdown: false } }
    Component { id: markdownView; TextPreview { theme: root; markdown: true } }
    Component { id: mediaView; MediaPreview { theme: root } }
    Component { id: listView; ListPreview { theme: root } }
    Component { id: fontView; FontPreview { theme: root } }
    Component { id: infoView; InfoPreview { theme: root } }
}
