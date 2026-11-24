import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

ApplicationWindow {
    id: win
    visible: false
    width: 1200
    height: 800
    minimumWidth: 940
    minimumHeight: 620
    title: Look.win ? "Store" : Look.gnu ? "Software" : "App Store"
    color: Look.window

    property var home: ({})
    property bool homeLoading: true
    property bool catalogUpdating: false
    readonly property bool catalogWait: catalogUpdating && !(Store.sources.flathub && Store.sources.flathub.catalog) && cur.view === "home"
    property var stack: [{ view: "home" }]
    readonly property var cur: stack[stack.length - 1]
    property string root: "home"
    property int searchSeq: 0
    property var review: ({})

    font.family: Look.sans

    function nav(o, replace) {
        if (replace) stack = stack.slice(0, -1).concat([o])
        else stack = stack.concat([o])
    }

    function go(rootView, o) {
        root = rootView
        stack = [o || { view: rootView }]
    }

    function back() {
        if (stack.length > 1) stack = stack.slice(0, -1)
    }

    function openApp(app, replace) {
        if (!app || !app.key) return
        nav({ view: "app", key: app.key, seed: app }, !!replace && cur.view === "app")
    }

    function openList(title, items) {
        nav({ view: "list", title: title, items: items })
    }

    function openCategory(id, name, asRoot) {
        var o = { view: "list", title: name, items: [], loading: true, cat: id }
        if (asRoot) go("cat:" + id, o)
        else nav(o)
        Store.call("browse " + Store.q(id), function (j) {
            for (var i = 0; i < win.stack.length; i++) {
                if (win.stack[i].cat === id) {
                    var s = win.stack.slice()
                    s[i] = Object.assign({}, s[i], { items: j && j.items ? j.items : [], loading: false })
                    win.stack = s
                }
            }
        })
    }

    function search(q) {
        q = String(q || "").trim()
        if (q === "") return
        var seq = ++searchSeq
        var o = { view: "list", title: "Results for “" + q + "”", search: true, query: q, items: [], packages: [], agents: [], arch: [], aur: [], loading: true, archLoading: Store.archOn, seq: seq }
        if (cur.view === "list" && cur.search) nav(o, true)
        else { root = "search"; stack = [o] }
        function patch(p) {
            var s = win.stack.slice()
            for (var i = 0; i < s.length; i++)
                if (s[i].seq === seq) s[i] = Object.assign({}, s[i], p)
            win.stack = s
        }
        Store.call("search " + Store.q(q), function (j) {
            patch({ items: j && j.items ? j.items : [], packages: j && j.packages ? j.packages : [], agents: j && j.agents ? j.agents : [], loading: false })
        })
        if (Store.archOn) {
            var left = 2
            var err = ""
            var got = { arch: [], aur: [] }
            ;["", " --aur"].forEach(function (flag) {
                Store.call("search-arch " + Store.q(q) + flag, function (j) {
                    left--
                    if (j && j.error) err = j.error
                    if (j && j.items) got[flag ? "aur" : "arch"] = j.items
                    patch({ arch: got.arch, aur: got.aur, archLoading: left > 0, archError: err })
                })
            })
        }
    }

    function requestInstall(app) {
        if (!app) return
        if (app.src === "aur") {
            reviewAur(app, { loading: true, risk: app.risk || "", cve: app.cve || [] })
            Store.call("app " + Store.q(app.key), function (j) {
                if (win.review.app && win.review.app.key === app.key)
                    win.review = { app: app, d: j && !j.error ? j : { error: j && j.error ? j.error : "The build script could not be loaded." } }
            })
            return
        }
        if ((app.src === "arch") && app.cve && app.cve.length) {
            reviewAur(app, app)
            return
        }
        Store.install(app)
    }

    function reviewAur(app, d) {
        review = { app: app, d: d || {} }
        reviewDlg.read = false
        reviewDlg.vuln = false
        reviewDlg.open()
    }

    function confirmRemove(app) {
        removeDlg.app = app
        removeDlg.title = "Remove " + app.name + "?"
        removeDlg.body = app.src === "flathub" ? "The app is removed for everyone on this computer. Its settings in your home folder stay." : app.src === "agent" ? "The agent and the files KwickOS installed for it are removed." : app.src === "model" ? "The downloaded model file is deleted from this computer. You can download it again later." : app.src === "arch" || app.src === "aur" ? "The package is removed from the Arch environment." : "The Debian package " + (app.pkg || app.id) + " is removed. Packages that only it needed stay installed."
        removeDlg.open()
    }

    function showShot(url, caption) {
        shotView.url = url
        shotView.caption = caption || ""
        shotView.open()
    }

    function startup(args) {
        var a = String(args || "").trim().split(/\s+/)
        if (a[0] === "updates") go("updates")
        else if (a[0] === "installed") go("installed")
        else if (a[0] === "search" && a.length > 1) search(a.slice(1).join(" "))
        else if (a[0] === "app" && a[1]) openApp({ key: a[1], src: a[1].split(":")[0], name: "" })
    }

    function loadHome() {
        Store.call("home", function (j) {
            win.homeLoading = false
            if (j && !j.error) win.home = j
            else if (j && j.error) Store.say("Could not read the catalog: " + j.error, true)
        })
    }

    Component.onCompleted: {
        Qt.application.domain = "store.kwickos.org"
        win.visible = true
        Store.call("appearance", function (j) {
            if (j) {
                if (["macos", "windows", "linux"].indexOf(j.layout) >= 0) Look.layout = j.layout
                Look.light = j.appearance === "light"
                if (j.accent) Look.systemAccent = j.accent
                if (j.accentText) Look.systemAccentText = j.accentText
                if (j.fill) Look.systemFill = j.fill
                if (j.sidebar) Look.sidebarIcons = j.sidebar
            }
        })
        Store.loadSources(function () {
            Store.run("printenv KWICK_STORE_ARGS", function (out) { win.startup(out) })
        })
        Store.call("home", function (j) {
            win.homeLoading = false
            if (j && !j.error) win.home = j
            else if (j && j.error) Store.say("Could not read the catalog: " + j.error, true)
            Store.loadUpdates()
            Store.call("refresh", function (r) {
                if (r && (r.rebuilt || (r.count && win.home.count !== undefined && r.count !== win.home.count))) win.loadHome()
                win.updateCatalog()
            })
        })
    }

    function updateCatalog() {
        Store.call("appstream --check", function (a) {
            if (!a || !(a.stale || []).length) return
            win.catalogUpdating = true
            Store.call("appstream", function (r) {
                Store.loadSources(function () {
                    win.catalogUpdating = false
                    if (r && r.updated) win.loadHome()
                })
            })
        })
    }

    Shortcut { sequences: [StandardKey.Back, "Alt+Left", "Backspace"]; enabled: win.stack.length > 1 && !(activeFocusItem && activeFocusItem.hasOwnProperty("cursorPosition")); onActivated: win.back() }
    Shortcut { sequences: [StandardKey.Find]; onActivated: { searchBox.input.forceActiveFocus(); if (Look.gnu) gnuSearch.shown = true } }

    readonly property var macNav: [
        { id: "home", label: "Discover", glyph: "discover" },
        { id: "cat:create", label: "Create", glyph: "create" },
        { id: "cat:work", label: "Work", glyph: "work" },
        { id: "cat:play", label: "Play", glyph: "play" },
        { id: "cat:develop", label: "Develop", glyph: "develop" },
        { id: "categories", label: "Categories", glyph: "categories" }
    ].concat(Store.agentsOn ? [{ id: "cat:agents", label: "AI Agents", glyph: "agents" }, { id: "cat:local-ai", label: "Local AI", glyph: "agents" }] : []).concat([
        { id: "updates", label: "Updates", glyph: "updates" },
        { id: "installed", label: "Installed", glyph: "installed" }
    ])

    readonly property var winNav: [
        { id: "home", label: "Home", glyph: "home" },
        { id: "categories", label: "Apps", glyph: "apps" },
        { id: "cat:play", label: "Gaming", glyph: "play" }
    ].concat(Store.agentsOn ? [{ id: "cat:agents", label: "AI Hub", glyph: "agents" }, { id: "cat:local-ai", label: "Local AI", glyph: "agents" }] : [])

    function pick(id) {
        if (id.indexOf("cat:") === 0) {
            var c = id.slice(4)
            var names = { create: "Create", work: "Work", play: Look.win ? "Gaming" : "Play", develop: "Develop", agents: "AI Agents", "local-ai": "Local AI" }
            openCategory(c, names[c] || c, true)
        } else {
            go(id)
        }
    }

    component NavItem: Rectangle {
        id: ni
        property var item
        property bool on: win.root === item.id
        property int badge: 0
        Layout.fillWidth: true
        implicitHeight: 32
        radius: 7
        color: on ? Look.selected : niArea.containsMouse ? Look.hover : "transparent"
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10
            Glyph { name: ni.item.glyph; size: 17; stroke: 1.7; color: Look.sidebarIcon }
            Text { Layout.fillWidth: true; text: ni.item.label; color: Look.text; font.family: Look.sans; font.pixelSize: 13; font.weight: ni.on ? Font.DemiBold : Font.Normal }
            Rectangle {
                visible: ni.badge > 0
                implicitWidth: Math.max(18, bt.implicitWidth + 10)
                implicitHeight: 18
                radius: 9
                color: Look.accent
                Text { id: bt; anchors.centerIn: parent; text: ni.badge; color: "#ffffff"; font.family: Look.sans; font.pixelSize: 11; font.weight: Font.Bold }
            }
        }
        MouseArea { id: niArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.pick(ni.item.id) }
    }

    component RailItem: Rectangle {
        id: ri
        property var item
        property bool on: win.root === item.id
        property int badge: 0
        implicitWidth: 64
        implicitHeight: 58
        radius: 6
        color: riArea.containsMouse ? Look.hover : "transparent"
        Rectangle {
            visible: ri.on
            width: 3
            height: 16
            radius: 1.5
            color: Look.accent
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -8
        }
        Glyph {
            id: rg
            anchors.horizontalCenter: parent.horizontalCenter
            y: 10
            name: ri.item.glyph
            size: 20
            stroke: ri.on ? 2 : 1.6
            color: ri.on ? Look.accent : Look.text
            Rectangle {
                visible: ri.badge > 0
                width: 8
                height: 8
                radius: 4
                color: Look.accent
                x: parent.width - 3
                y: -2
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: rg.bottom
            anchors.topMargin: 4
            visible: !ri.on || true
            text: ri.item.label
            color: ri.on ? Look.text : Look.sub
            font.family: Look.sans
            font.pixelSize: 11
            font.weight: ri.on ? Font.DemiBold : Font.Normal
        }
        MouseArea { id: riArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.pick(ri.item.id) }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            visible: Look.mac
            Layout.fillHeight: true
            Layout.preferredWidth: 230
            color: Look.sidebar
            Rectangle { width: 1; height: parent.height; anchors.right: parent.right; color: Look.line }
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                anchors.topMargin: 14
                spacing: 2
                SearchField {
                    id: macSearch
                    Layout.fillWidth: true
                    Layout.bottomMargin: 12
                    onAccepted: function (t) { win.search(t) }
                    onCleared: if (win.root === "search") win.go("home")
                }
                Repeater {
                    model: win.macNav
                    delegate: NavItem {
                        required property var modelData
                        item: modelData
                        badge: modelData.id === "updates" ? Store.updateCount : 0
                        Layout.topMargin: modelData.id === "updates" ? 14 : 0
                    }
                }
                Item { Layout.fillHeight: true }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    spacing: 8
                    Rectangle {
                        implicitWidth: 28
                        implicitHeight: 28
                        radius: 14
                        color: Look.light ? "#d1d1d6" : "#48484a"
                        Glyph { anchors.centerIn: parent; name: "person"; size: 16; stroke: 1.6; color: Look.sub }
                    }
                    ColumnLayout {
                        spacing: 0
                        Text { text: "Sources"; color: Look.text; font.family: Look.sans; font.pixelSize: 12; font.weight: Font.Medium }
                        Text {
                            text: ["Flathub", "Debian"].concat(Store.archOn ? ["Arch"] : []).concat(Store.agentsOn ? ["Agents"] : []).join(" · ")
                            color: Look.sub
                            font.family: Look.sans
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }

        ColumnLayout {
            visible: Look.win
            Layout.fillHeight: true
            Layout.preferredWidth: 72
            Layout.topMargin: 56
            spacing: 4
            Repeater {
                model: win.winNav
                delegate: RailItem {
                    required property var modelData
                    Layout.alignment: Qt.AlignHCenter
                    item: modelData
                }
            }
            Item { Layout.fillHeight: true }
            RailItem { Layout.alignment: Qt.AlignHCenter; item: { "id": "updates", "label": "Updates", "glyph": "download" }; badge: Store.updateCount }
            RailItem { Layout.alignment: Qt.AlignHCenter; Layout.bottomMargin: 10; item: { "id": "installed", "label": "Library", "glyph": "library" } }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Item {
                visible: Look.win
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                RowLayout {
                    anchors.fill: parent
                    anchors.rightMargin: 16
                    spacing: 10
                    Rectangle {
                        visible: win.stack.length > 1
                        implicitWidth: 36
                        implicitHeight: 32
                        radius: 4
                        color: wb.containsMouse ? Look.hover : "transparent"
                        Glyph { anchors.centerIn: parent; name: "back"; size: 16; stroke: 1.8; color: Look.text }
                        MouseArea { id: wb; anchors.fill: parent; hoverEnabled: true; onClicked: win.back() }
                    }
                    Item { Layout.fillWidth: true }
                    SearchField {
                        id: winSearch
                        Layout.preferredWidth: Math.min(560, win.width * 0.42)
                        placeholder: "Search apps, games, packages and more"
                        onAccepted: function (t) { win.search(t) }
                        onCleared: if (win.root === "search") win.go("home")
                    }
                    Item { Layout.fillWidth: true }
                    Item { implicitWidth: 36 }
                }
            }

            Rectangle {
                visible: Look.gnu
                Layout.fillWidth: true
                Layout.preferredHeight: 47
                color: Look.sidebar
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Look.light ? Qt.rgba(0, 0, 0, 0.12) : Qt.rgba(0, 0, 0, 0.36) }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 6
                    Rectangle {
                        implicitWidth: 34
                        implicitHeight: 34
                        radius: 6
                        color: win.stack.length > 1 ? (gba.containsMouse ? Look.hover : "transparent") : gnuSearch.shown ? Look.selected : gsa.containsMouse ? Look.hover : "transparent"
                        Glyph { anchors.centerIn: parent; name: win.stack.length > 1 ? "back" : "search"; size: 16; stroke: 1.9; color: Look.text }
                        MouseArea { id: gba; anchors.fill: parent; hoverEnabled: true; visible: win.stack.length > 1; onClicked: win.back() }
                        MouseArea { id: gsa; anchors.fill: parent; hoverEnabled: true; visible: win.stack.length <= 1; onClicked: { gnuSearch.shown = !gnuSearch.shown; if (gnuSearch.shown) gnuField.input.forceActiveFocus() } }
                    }
                    Item { Layout.fillWidth: true }
                    Row {
                        visible: win.stack.length <= 1 || win.cur.view !== "app"
                        spacing: 2
                        Repeater {
                            model: [{ id: "home", label: "Explore", glyph: "discover" }, { id: "installed", label: "Installed", glyph: "installed" }, { id: "updates", label: "Updates", glyph: "updates" }]
                            delegate: Rectangle {
                                id: tab
                                required property var modelData
                                readonly property bool on: win.root === modelData.id || (modelData.id === "home" && (win.root === "categories" || win.root.indexOf("cat:") === 0 || win.root === "search"))
                                width: tr.implicitWidth + 28
                                height: 34
                                radius: 6
                                color: on ? Look.selected : ta.containsMouse ? Look.hover : "transparent"
                                RowLayout {
                                    id: tr
                                    anchors.centerIn: parent
                                    spacing: 8
                                    Glyph { name: tab.modelData.glyph; size: 16; stroke: 1.8; color: Look.text }
                                    Text { text: tab.modelData.label; color: Look.text; font.family: Look.sans; font.pixelSize: 14; font.weight: Font.Bold }
                                    Rectangle {
                                        visible: tab.modelData.id === "updates" && Store.updateCount > 0
                                        implicitWidth: Math.max(18, ubt.implicitWidth + 10)
                                        implicitHeight: 18
                                        radius: 9
                                        color: Look.accent
                                        Text { id: ubt; anchors.centerIn: parent; text: Store.updateCount; color: "#ffffff"; font.family: Look.sans; font.pixelSize: 11; font.weight: Font.Bold }
                                    }
                                }
                                MouseArea { id: ta; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.pick(tab.modelData.id) }
                            }
                        }
                    }
                    Text {
                        visible: win.stack.length > 1 && win.cur.view === "app"
                        text: win.cur.seed ? win.cur.seed.name || "" : ""
                        color: Look.text
                        font.family: Look.sans
                        font.pixelSize: 14
                        font.weight: Font.Bold
                    }
                    Item { Layout.fillWidth: true }
                    Item { implicitWidth: 34 }
                }
            }

            Rectangle {
                id: gnuSearch
                property bool shown: false
                visible: Look.gnu && (shown || win.root === "search") && win.stack.length <= 1
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                color: Look.sidebar
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Look.line }
                SearchField {
                    id: gnuField
                    anchors.centerIn: parent
                    width: Math.min(520, parent.width - 40)
                    placeholder: "Search apps and packages"
                    onAccepted: function (t) { win.search(t) }
                    onCleared: { gnuSearch.shown = false; if (win.root === "search") win.go("home") }
                }
            }

            Rectangle {
                id: contentArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Look.content
                radius: Look.win ? 8 : 0
                border.width: Look.win ? 1 : 0
                border.color: Look.contentStroke
                Rectangle { visible: Look.win; anchors.right: parent.right; anchors.top: parent.top; width: 10; height: parent.height; color: parent.color }
                Rectangle { visible: Look.win; anchors.left: parent.left; anchors.bottom: parent.bottom; height: 10; width: parent.width; color: parent.color }

                Rectangle {
                    visible: Look.mac && win.stack.length > 1
                    z: 2
                    x: 20
                    y: 14
                    width: 30
                    height: 26
                    radius: 6
                    color: mb.containsMouse ? Look.hover : "transparent"
                    Glyph { anchors.centerIn: parent; name: "back"; size: 17; stroke: 2; color: Look.sub }
                    MouseArea { id: mb; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.back() }
                }

                Flickable {
                    id: flick
                    visible: !win.catalogWait
                    anchors.fill: parent
                    anchors.topMargin: Look.mac && win.stack.length > 1 ? 40 : 0
                    clip: true
                    contentWidth: width
                    contentHeight: pageLoader.implicitHeight + 64
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { }

                    Loader {
                        id: pageLoader
                        readonly property real side: Look.gnu ? Math.max(24, (flick.width - 1000) / 2) : Look.win ? 32 : 30
                        x: side
                        y: Look.mac ? (win.stack.length > 1 ? 4 : 26) : 24
                        width: flick.width - side * 2
                        sourceComponent: {
                            var v = win.cur.view
                            if (v === "app") return appComp
                            if (v === "list") return listComp
                            if (v === "updates") return updatesComp
                            if (v === "installed") return installedComp
                            if (v === "categories") return catsComp
                            return homeComp
                        }
                        onLoaded: flick.contentY = 0
                    }
                }

                ColumnLayout {
                    visible: (win.homeLoading || win.catalogWait) && win.cur.view === "home"
                    anchors.centerIn: parent
                    spacing: 12
                    BusyIndicator { Layout.alignment: Qt.AlignHCenter; running: parent.visible }
                    Text { Layout.alignment: Qt.AlignHCenter; text: win.catalogWait ? "Updating the app catalog…" : "Loading the catalog…"; color: Look.sub; font.family: Look.sans; font.pixelSize: 13 }
                }
            }
        }
    }

    Item {
        id: searchBox
        readonly property var input: Look.mac ? macSearch.input : Look.win ? winSearch.input : gnuField.input
    }

    Component { id: homeComp; HomePage { home: win.home; title: "Discover" } }
    Component { id: catsComp; HomePage { home: win.home; title: "Categories"; catsOnly: true } }
    Component {
        id: listComp
        ListPage {
            title: win.cur.title || ""
            items: win.cur.items || []
            packages: win.cur.packages || []
            agents: win.cur.agents || []
            arch: win.cur.arch || []
            aur: win.cur.aur || []
            loading: !!win.cur.loading
            archLoading: !!win.cur.archLoading
            archError: win.cur.archError || ""
            search: !!win.cur.search
        }
    }
    Component { id: appComp; AppPage { key: win.cur.key || ""; seed: win.cur.seed || ({}) } }
    Component { id: updatesComp; UpdatesPage { } }
    Component { id: installedComp; InstalledPage { } }

    StoreDialog {
        id: removeDlg
        confirmText: "Remove"
        danger: true
        onConfirmed: Store.remove(app)
    }

    StoreDialog {
        id: reviewDlg
        property bool read: false
        property bool vuln: false
        readonly property var ra: win.review.app || ({})
        readonly property var rd: win.review.d || ({})
        readonly property var cves: rd.cve || ra.cve || []
        readonly property bool isAur: ra.src === "aur"
        readonly property string risk: rd.risk || ra.risk || ""
        width: isAur ? Math.min(win.width - 80, 760) : 480
        app: ra
        title: isAur ? "Review " + (ra.name || "") + " before installing" : "Install " + (ra.name || "") + " with known vulnerabilities?"
        body: isAur ? "AUR packages are built on this computer from a script anyone can submit. Read what it downloads and runs." : "The Arch package has published security issues that are not fixed in this version."
        confirmText: isAur ? "Build and Install" : "Install Anyway"
        danger: !isAur || risk === "high"
        confirmEnabled: (!isAur || (read && !rd.loading && !!rd.pkgbuild)) && (cves.length === 0 || vuln)
        onConfirmed: Store.install(ra, { allowVulnerable: vuln, commit: rd.commit || "" })

        Rectangle {
            visible: reviewDlg.isAur
            Layout.fillWidth: true
            implicitHeight: riskCol.implicitHeight + 20
            radius: 8
            color: reviewDlg.risk === "high" ? Look.badBg : reviewDlg.risk === "medium" ? Look.warnBg : Look.goodBg
            ColumnLayout {
                id: riskCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                spacing: 6
                RowLayout {
                    spacing: 8
                    Glyph { name: reviewDlg.risk === "low" ? "shieldok" : "warning"; size: 18; stroke: 1.8; color: reviewDlg.risk === "high" ? Look.bad : reviewDlg.risk === "medium" ? Look.warn : Look.good }
                    Text { text: "Risk check: " + (reviewDlg.risk || "unknown"); color: Look.text; font.family: Look.sans; font.pixelSize: 13; font.weight: Font.DemiBold }
                }
                Repeater {
                    model: reviewDlg.rd.findings || []
                    delegate: RowLayout {
                        id: fr
                        required property var modelData
                        readonly property string sev: typeof modelData === "object" ? (modelData.severity || modelData.level || "") : ""
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle { Layout.alignment: Qt.AlignTop; Layout.topMargin: 5; implicitWidth: 6; implicitHeight: 6; radius: 3; color: fr.sev === "high" || fr.sev === "critical" ? Look.bad : fr.sev === "medium" ? Look.warn : Look.sub }
                        Text {
                            Layout.fillWidth: true
                            text: typeof fr.modelData === "string" ? fr.modelData : (fr.modelData.message || fr.modelData.text || fr.modelData.description || JSON.stringify(fr.modelData)) + (typeof fr.modelData === "object" && fr.modelData.file ? "  (" + fr.modelData.file + (fr.modelData.line ? ":" + fr.modelData.line : "") + ")" : "")
                            color: Look.text
                            font.family: Look.sans
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }

        Text {
            visible: reviewDlg.isAur && !!reviewDlg.rd.commit
            Layout.fillWidth: true
            text: "Builds AUR commit " + String(reviewDlg.rd.commit || "").slice(0, 12) + (reviewDlg.rd.pkgbase ? " of " + reviewDlg.rd.pkgbase : "") + ", exactly the files shown here."
            color: Look.sub
            font.family: Look.sans
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }

        Rectangle {
            visible: reviewDlg.isAur
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(300, win.height - 420)
            radius: 6
            color: Look.light ? "#f4f4f6" : "#161618"
            border.width: 1
            border.color: Look.line
            Flickable {
                id: pkf
                anchors.fill: parent
                anchors.margins: 1
                clip: true
                contentWidth: Math.max(width, pkText.implicitWidth + 24)
                contentHeight: pkText.implicitHeight + 20
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { }
                ScrollBar.horizontal: ScrollBar { }
                TextEdit {
                    id: pkText
                    x: 12
                    y: 10
                    readOnly: true
                    selectByMouse: true
                    text: reviewDlg.rd.loading ? "Loading the build script…" : reviewDlg.rd.pkgbuild || reviewDlg.rd.error || "The build script could not be loaded."
                    color: Look.text
                    font.family: Look.mono
                    font.pixelSize: 12
                }
            }
        }

        ColumnLayout {
            visible: reviewDlg.cves.length > 0
            Layout.fillWidth: true
            spacing: 4
            Text { text: "Known vulnerabilities"; color: Look.bad; font.family: Look.sans; font.pixelSize: 13; font.weight: Font.DemiBold }
            Text {
                Layout.fillWidth: true
                text: reviewDlg.cves.map(function (c) { return typeof c === "string" ? c : (c.id || c.name || "") }).join(", ")
                color: Look.text
                font.family: Look.mono
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }

        Check { visible: reviewDlg.isAur; Layout.fillWidth: true; Layout.topMargin: 4; text: "I read the build script and trust where it downloads from"; checked: reviewDlg.read; onCheckedChanged: reviewDlg.read = checked }
        Check { visible: reviewDlg.cves.length > 0; Layout.fillWidth: true; text: "Install even though it has known vulnerabilities"; tint: Look.bad; checked: reviewDlg.vuln; onCheckedChanged: reviewDlg.vuln = checked }
    }

    Popup {
        id: shotView
        property string url
        property string caption
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: win.width
        height: win.height
        modal: true
        padding: 0
        background: Rectangle { color: Qt.rgba(0, 0, 0, 0.86) }
        Image {
            id: big
            anchors.fill: parent
            anchors.margins: 50
            anchors.bottomMargin: 70
            source: shotView.opened ? shotView.url : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            mipmap: true
        }
        BusyIndicator { anchors.centerIn: parent; running: big.status === Image.Loading }
        Text { anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 26; width: parent.width - 100; horizontalAlignment: Text.AlignHCenter; text: shotView.caption; color: "#dddddd"; font.family: Look.sans; font.pixelSize: 13; elide: Text.ElideRight }
        MouseArea { anchors.fill: parent; onClicked: shotView.close() }
        Rectangle {
            x: parent.width - 52
            y: 16
            width: 32
            height: 32
            radius: 16
            color: Qt.rgba(1, 1, 1, 0.15)
            Glyph { anchors.centerIn: parent; name: "close"; size: 14; stroke: 2; color: "#ffffff" }
        }
    }

    Rectangle {
        id: toast
        z: 10
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: shown ? 24 : -height
        property bool shown: false
        width: Math.min(win.width - 80, tt.implicitWidth + 40)
        height: 40
        radius: Look.win ? 6 : 20
        color: Look.light ? "#2c2c2e" : "#f2f2f7"
        opacity: shown ? 1 : 0
        Behavior on anchors.bottomMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200 } }
        RowLayout {
            anchors.centerIn: parent
            spacing: 8
            Glyph { name: Store.toastBad ? "warning" : "check"; size: 16; stroke: 2; color: Store.toastBad ? Look.bad : Look.good }
            Text { id: tt; text: Store.toast; color: Look.light ? "#ffffff" : "#1d1d1f"; font.family: Look.sans; font.pixelSize: 13; elide: Text.ElideRight; Layout.maximumWidth: win.width - 140 }
        }
        Timer { id: toastTimer; interval: 4500; onTriggered: toast.shown = false }
        Connections {
            target: Store
            function onToastChanged() { if (Store.toast !== "") { toast.shown = true; toastTimer.restart() } }
        }
    }
}
