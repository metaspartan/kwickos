import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects

ColumnLayout {
    id: page
    property var home: ({})
    property string title: "Discover"
    property var only: null
    property bool catsOnly: false
    readonly property var featured: catsOnly ? [] : home.featured || []
    readonly property var sections: catsOnly ? [] : (home.sections || []).filter(function (s) { return !page.only || page.only.indexOf(s.id) >= 0 })
    readonly property var cats: home.categories || []
    readonly property int cols: Look.mac ? (width > 1060 ? 3 : 2) : Look.win ? Math.max(2, Math.floor((width + 12) / 200)) : (width > 900 ? 3 : 2)
    property int heroIndex: 0
    spacing: Look.mac ? 30 : Look.win ? 28 : 26

    Timer {
        interval: 7000
        repeat: true
        running: page.visible && page.featured.length > 1 && !Look.mac
        onTriggered: page.heroIndex = (page.heroIndex + 1) % page.featured.length
    }

    RowLayout {
        visible: Look.mac && page.title !== ""
        Layout.fillWidth: true
        Layout.bottomMargin: -10
        Text {
            Layout.fillWidth: true
            text: page.title
            color: Look.text
            font.family: Look.display
            font.pixelSize: 28
            font.weight: Font.Bold
        }
        Repeater {
            model: macHero.visible && macHero.contentWidth > macHero.width ? [-1, 1] : []
            delegate: Rectangle {
                required property int modelData
                readonly property bool can: modelData < 0 ? !macHero.atXBeginning : !macHero.atXEnd
                implicitWidth: 28
                implicitHeight: 28
                radius: 14
                color: ha.containsMouse && can ? Look.pressed : Look.hover
                opacity: can ? 1 : 0.4
                Glyph { anchors.centerIn: parent; name: parent.modelData < 0 ? "back" : "forward"; size: 14; stroke: 2.2; color: Look.text }
                MouseArea {
                    id: ha
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var i = macHero.indexAt(macHero.contentX + 4, 10)
                        macHero.positionViewAtIndex(Math.max(0, Math.min(page.featured.length - 1, i + parent.modelData)), ListView.Beginning)
                    }
                }
            }
        }
    }

    ListView {
        id: macHero
        visible: Look.mac && page.featured.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: 300
        orientation: ListView.Horizontal
        spacing: 16
        clip: true
        snapMode: ListView.SnapToItem
        boundsBehavior: Flickable.StopAtBounds
        model: Look.mac ? page.featured : []
        delegate: Item {
            id: hc
            required property var modelData
            width: (macHero.width - 16) / (macHero.width > 1000 ? 2 : 1.35)
            height: macHero.height
            Rectangle {
                id: hcard
                anchors.fill: parent
                radius: 14
                clip: true
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0; color: hc.modelData.tint[0] || "#333" }
                    GradientStop { position: 1; color: hc.modelData.tint[1] || "#111" }
                }
                Image {
                    id: shot
                    visible: status === Image.Ready
                    anchors.right: parent.right
                    anchors.rightMargin: -40
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: -70
                    width: parent.width * 0.68
                    height: width * 0.6
                    source: hc.modelData.hero || ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 900
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: shotMask
                        shadowEnabled: true
                        shadowBlur: 0.8
                        shadowOpacity: 0.5
                    }
                    transform: Rotation { origin.x: 0; origin.y: 0; angle: -4 }
                }
                Rectangle {
                    id: shotMask
                    visible: false
                    layer.enabled: true
                    width: shot.width
                    height: shot.height
                    radius: 10
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.35) }
                        GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.0) }
                    }
                }
                ColumnLayout {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 22
                    width: parent.width * 0.5
                    spacing: 4
                    Text { text: hc.modelData.eyebrow; color: Qt.rgba(1, 1, 1, 0.72); font.family: Look.sans; font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 0.4 }
                    Text { Layout.fillWidth: true; text: hc.modelData.title; color: "#ffffff"; font.family: Look.display; font.pixelSize: 28; font.weight: Font.Bold; wrapMode: Text.WordWrap }
                    Text { Layout.fillWidth: true; text: hc.modelData.tagline; color: Qt.rgba(1, 1, 1, 0.86); font.family: Look.sans; font.pixelSize: 14; wrapMode: Text.WordWrap; lineHeight: 1.15 }
                }
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 76
                    color: Qt.rgba(0, 0, 0, 0.28)
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12
                        AppIcon { Layout.preferredWidth: 46; Layout.preferredHeight: 46; size: 46; source: hc.modelData.icon || ""; name: hc.modelData.name }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text { Layout.fillWidth: true; text: hc.modelData.name; color: "#ffffff"; font.family: Look.sans; font.pixelSize: 14; font.weight: Font.DemiBold; elide: Text.ElideRight }
                            Text { Layout.fillWidth: true; text: hc.modelData.summary || ""; color: Qt.rgba(1, 1, 1, 0.75); font.family: Look.sans; font.pixelSize: 12; elide: Text.ElideRight }
                        }
                        GetButton { app: hc.modelData }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.bottomMargin: 76
                    cursorShape: Qt.PointingHandCursor
                    onClicked: hc.ApplicationWindow.window.openApp(hc.modelData)
                }
            }
        }
    }

    Item {
        id: banner
        visible: !Look.mac && page.featured.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: Look.win ? 360 : 260
        readonly property var cur: page.featured.length ? page.featured[Math.min(page.heroIndex, page.featured.length - 1)] : null
        readonly property color brand: cur && cur.brand ? (Look.light ? (cur.brand.light || cur.brand.dark || "") : (cur.brand.dark || cur.brand.light || "")) : ""

        Rectangle {
            id: bannerCard
            anchors.fill: parent
            radius: Look.win ? 8 : 12
            clip: true
            color: banner.brand !== "" && Look.gnu ? banner.brand : (banner.cur && banner.cur.tint ? banner.cur.tint[1] || "#333" : "#333")
            Behavior on color { ColorAnimation { duration: 300 } }
            layer.enabled: true
            layer.effect: MultiEffect { maskEnabled: true; maskSource: bannerMask }

            Image {
                visible: Look.win && status === Image.Ready
                anchors.fill: parent
                source: Look.win && banner.cur ? banner.cur.hero || "" : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 1600
                opacity: 0.95
            }
            Rectangle {
                visible: Look.win
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.82) }
                    GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.35) }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.05) }
                }
            }
            ColumnLayout {
                visible: Look.win
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin: 40
                anchors.bottomMargin: 44
                width: Math.min(460, parent.width * 0.5)
                spacing: 10
                AppIcon { Layout.preferredWidth: 64; Layout.preferredHeight: 64; size: 64; source: banner.cur ? banner.cur.icon || "" : ""; name: banner.cur ? banner.cur.name : "" }
                Text { Layout.fillWidth: true; text: banner.cur ? banner.cur.title : ""; color: "#ffffff"; font.family: Look.display; font.pixelSize: 34; font.weight: Font.DemiBold; wrapMode: Text.WordWrap }
                Text { Layout.fillWidth: true; text: banner.cur ? banner.cur.tagline : ""; color: Qt.rgba(1, 1, 1, 0.86); font.family: Look.sans; font.pixelSize: 15; wrapMode: Text.WordWrap }
                RowLayout {
                    Layout.topMargin: 6
                    spacing: 8
                    GetButton { app: banner.cur; big: false }
                    Btn { text: "See details"; onClicked: banner.ApplicationWindow.window.openApp(banner.cur) }
                }
            }

            RowLayout {
                visible: Look.gnu
                anchors.fill: parent
                anchors.leftMargin: 80
                anchors.rightMargin: 80
                spacing: 28
                AppIcon { Layout.preferredWidth: 128; Layout.preferredHeight: 128; size: 128; source: banner.cur ? banner.cur.icon || "" : ""; name: banner.cur ? banner.cur.name : "" }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text { Layout.fillWidth: true; text: banner.cur ? banner.cur.name : ""; color: banner.dark ? "#ffffff" : "#1e1e1e"; font.family: Look.sans; font.pixelSize: 26; font.weight: Font.Bold; elide: Text.ElideRight }
                    Text { Layout.fillWidth: true; text: banner.cur ? banner.cur.summary || banner.cur.tagline : ""; color: banner.dark ? Qt.rgba(1, 1, 1, 0.8) : Qt.rgba(0, 0, 0, 0.7); font.family: Look.sans; font.pixelSize: 15; wrapMode: Text.WordWrap }
                }
            }
            MouseArea {
                visible: Look.gnu
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: banner.ApplicationWindow.window.openApp(banner.cur)
            }
        }
        readonly property bool dark: {
            var c = bannerCard.color
            return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) < 0.62
        }
        Rectangle {
            id: bannerMask
            visible: false
            layer.enabled: true
            width: bannerCard.width
            height: bannerCard.height
            radius: bannerCard.radius
        }

        Repeater {
            model: [-1, 1]
            delegate: Rectangle {
                required property int modelData
                visible: page.featured.length > 1
                width: Look.win ? 28 : 34
                height: Look.win ? 40 : 34
                radius: Look.win ? 4 : 17
                anchors.verticalCenter: parent.verticalCenter
                x: modelData < 0 ? 14 : banner.width - width - 14
                color: arr.containsMouse ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(0, 0, 0, 0.32)
                Glyph { anchors.centerIn: parent; name: parent.modelData < 0 ? "back" : "forward"; size: 16; stroke: 2; color: "#ffffff" }
                MouseArea {
                    id: arr
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.heroIndex = (page.heroIndex + parent.modelData + page.featured.length) % page.featured.length
                }
            }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            spacing: 7
            Repeater {
                model: page.featured.length
                delegate: Rectangle {
                    required property int index
                    width: index === page.heroIndex && Look.win ? 18 : 7
                    height: 7
                    radius: 3.5
                    color: index === page.heroIndex ? "#ffffff" : Qt.rgba(1, 1, 1, 0.45)
                    Behavior on width { NumberAnimation { duration: 180 } }
                    MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: page.heroIndex = parent.index }
                }
            }
        }
    }

    Repeater {
        model: page.sections
        delegate: ColumnLayout {
            id: sec
            required property var modelData
            Layout.fillWidth: true
            spacing: Look.mac ? 8 : 12
            readonly property int shown: Look.win ? page.cols : page.cols * (Look.mac ? 3 : 2)

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                ColumnLayout {
                    spacing: 1
                    Layout.fillWidth: true
                    RowLayout {
                        spacing: 4
                        Text { text: sec.modelData.title; color: Look.text; font.family: Look.display; font.pixelSize: Look.section; font.weight: Look.win ? Font.DemiBold : Font.Bold }
                        Glyph {
                            visible: Look.win
                            name: "forward"
                            size: 16
                            stroke: 2
                            color: Look.text
                            MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: sec.ApplicationWindow.window.openList(sec.modelData.title, sec.modelData.items) }
                        }
                    }
                    Text { visible: sec.modelData.subtitle !== "" && !Look.gnu; text: sec.modelData.subtitle; color: Look.sub; font.family: Look.sans; font.pixelSize: 13 }
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: !Look.win && sec.modelData.items.length > sec.shown
                    text: "See All"
                    color: Look.accentText
                    font.family: Look.sans
                    font.pixelSize: 13
                    font.weight: Look.gnu ? Font.Bold : Font.Normal
                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: sec.ApplicationWindow.window.openList(sec.modelData.title, sec.modelData.items) }
                }
            }

            Rectangle {
                visible: Look.mac
                Layout.fillWidth: true
                height: 1
                color: Look.line
            }

            GridLayout {
                Layout.fillWidth: true
                columns: page.cols
                columnSpacing: Look.mac ? 28 : 12
                rowSpacing: Look.mac ? 0 : 12
                Repeater {
                    model: sec.modelData.items.slice(0, sec.shown)
                    delegate: AppTile {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        app: modelData
                        separator: index < sec.shown - page.cols && index < sec.modelData.items.length - page.cols
                    }
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: page.cats.length > 0 && !page.only
        spacing: 12
        Text { visible: !(page.catsOnly && Look.mac); text: Look.gnu && !page.catsOnly ? "Other Categories" : "Categories"; color: Look.text; font.family: Look.display; font.pixelSize: Look.section; font.weight: Look.win ? Font.DemiBold : Font.Bold }
        GridLayout {
            Layout.fillWidth: true
            columns: Look.win ? Math.max(2, Math.floor(page.width / 230)) : 4
            columnSpacing: 12
            rowSpacing: 12
            Repeater {
                model: page.cats.concat(Store.agentsOn ? [{ id: "agents", name: "AI Agents", glyph: "agents", tint: "#bf5af2" }, { id: "local-ai", name: "Local AI", glyph: "agents", tint: "#30d158" }] : [])
                delegate: Rectangle {
                    id: ct
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: Look.gnu ? 64 : 58
                    radius: Look.win ? 8 : Look.gnu ? 12 : 10
                    color: cta.containsMouse ? Look.cardHover : Look.card
                    border.width: Look.mac ? 0 : 1
                    border.color: Look.cardStroke
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12
                        Rectangle {
                            implicitWidth: 32
                            implicitHeight: 32
                            radius: Look.win ? 6 : 8
                            color: ct.modelData.tint
                            Glyph { anchors.centerIn: parent; name: ct.modelData.glyph; size: 19; stroke: 1.8; color: "#ffffff" }
                        }
                        Text { Layout.fillWidth: true; text: ct.modelData.name; color: Look.text; font.family: Look.sans; font.pixelSize: 14; font.weight: Font.Medium; elide: Text.ElideRight }
                    }
                    MouseArea { id: cta; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ct.ApplicationWindow.window.openCategory(ct.modelData.id, ct.modelData.name) }
                }
            }
        }
    }

    Rectangle {
        visible: (Store.archInstalled || Store.archAvailable) && !page.only && !page.catsOnly && page.sections.length > 0
        Layout.fillWidth: true
        implicitHeight: archRow.implicitHeight + 32
        radius: Look.radius
        color: Look.card
        border.width: Look.mac ? 0 : 1
        border.color: Look.cardStroke
        RowLayout {
            id: archRow
            anchors.fill: parent
            anchors.margins: 16
            spacing: 14
            Rectangle {
                implicitWidth: 44
                implicitHeight: 44
                radius: 10
                color: Look.sourceTint("arch")
                Glyph { anchors.centerIn: parent; name: "arch"; size: 24; stroke: 1.8; color: "#ffffff" }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { text: "Arch Linux and the AUR"; color: Look.text; font.family: Look.sans; font.pixelSize: 14; font.weight: Font.DemiBold }
                Text {
                    Layout.fillWidth: true
                    text: Store.archOn ? "Search finds Arch packages and AUR builds too. Every AUR install shows its build script and a risk report first." : "Get packages from the Arch Linux repositories and the AUR alongside Debian and Flathub."
                    color: Look.sub
                    font.family: Look.sans
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }
            Btn {
                id: archBtn
                visible: !Store.archOn
                text: "Turn On"
                primary: Look.win || Look.gnu
                onClicked: {
                    archBtn.text = "Turning On…"
                    var reset = function () { if (!Store.archOn) archBtn.text = "Turn On" }
                    if (Store.archInstalled) Store.archEnable(reset)
                    else Store.archGet(reset)
                }
            }
        }
    }

    Item { implicitHeight: 8 }
}
