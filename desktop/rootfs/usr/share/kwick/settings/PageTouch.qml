import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: page
    spacing: 10

    property var st: ({})
    property var gestures: []
    readonly property string session: st.session || "kde"
    readonly property bool kde: session === "kde"
    readonly property bool tiling: session === "hyprland" || session === "sway"
    readonly property string padName: Sys.layout === "macos" ? "Trackpad" : "Touchpad"

    function load() {
        Sys.run("kwick-touch status", function (out) {
            var s = {}
            var g = []
            out.split("\n").forEach(function (l) {
                var p = l.split("|")
                if (p[0] === "gesture" && p.length === 4)
                    g.push({ device: p[1], motion: p[2], action: p[3] })
                else if (p.length === 2)
                    s[p[0]] = p[1].trim()
            })
            page.st = s
            page.gestures = g
        })
    }

    function set(key, value) {
        var s = Object.assign({}, page.st)
        s[key] = value
        page.st = s
        Sys.run("kwick-touch " + key + " " + value, function () { refresh.restart() })
    }

    function list(device) {
        return page.gestures.filter(function (x) { return x.device === device })
    }

    function found(key) {
        return page.st[key] === "yes"
    }

    Component.onCompleted: load()

    Timer {
        id: refresh
        interval: 700
        onTriggered: page.load()
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: page.load()
    }

    SectionTitle { text: "TABLET MODE" }
    Card {
        Cell {
            title: "Tablet mode"
            subtitle: page.kde
                      ? "Automatic turns it on when the keyboard is folded away or detached and off when it comes back. Controls get larger and the keyboard shows up for touch."
                      : "GNOME and the tiling session follow touch input on their own."
            Seg {
                opacity: page.kde ? 1 : 0.4
                enabled: page.kde
                options: [{ id: "auto", label: "Automatic" }, { id: "on", label: "On" }, { id: "off", label: "Off" }]
                current: page.st.tablet || "auto"
                onPicked: (id) => { if (page.kde) page.set("tablet", id) }
            }
        }
        Cell {
            last: true
            title: "Right now"
            Rectangle {
                readonly property bool on: page.st.tabletactive === "yes"
                implicitWidth: badge.implicitWidth + 20
                implicitHeight: 22
                radius: 11
                color: on ? Qt.rgba(Theme.good.r, Theme.good.g, Theme.good.b, 0.16) : Theme.control
                Text {
                    id: badge
                    anchors.centerIn: parent
                    text: parent.on ? "Tablet" : "Desktop"
                    color: parent.on ? Theme.good : Theme.text
                    font.family: Theme.sans
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
            }
        }
    }

    SectionTitle { text: "KEYBOARD" }
    Card {
        Cell {
            title: "On-screen keyboard"
            subtitle: !page.found("oskhave") ? "No on-screen keyboard is installed for this session."
                      : page.tiling ? "Tap the keyboard button in the bar to show or hide it."
                      : page.session === "gnome" ? "GNOME shows its keyboard when you tap a text field."
                      : "Slides up when you tap a text field and stays away while you type on a real keyboard."
            Toggle {
                enabled: page.found("oskhave") && page.session !== "gnome"
                checked: page.st.osk !== "off"
                onToggled: (v) => page.set("osk", v ? "on" : "off")
            }
        }
        Cell {
            last: true
            title: "Show the keyboard now"
            subtitle: "Also on the lock screen, the login screen and in the installer."
            Btn {
                text: "Show"
                enabled: page.found("oskhave") && page.st.osk !== "off"
                onClicked: Sys.run("kwick-touch keyboard show")
            }
        }
    }

    SectionTitle { text: "ROTATION" }
    Card {
        Cell {
            last: true
            title: "Rotation lock"
            subtitle: !page.found("sensor") ? "This device has no orientation sensor."
                      : page.kde ? "When unlocked the screen turns with the device in tablet mode. Applies from the next login."
                      : "When unlocked the screen turns with the device."
            Toggle {
                enabled: page.found("sensor")
                checked: page.st.rotation === "locked"
                onToggled: (v) => page.set("rotation", v ? "locked" : "auto")
            }
        }
    }

    Repeater {
        model: [
            { device: "touchpad", title: page.padName.toUpperCase() + " GESTURES", have: "touchpad" },
            { device: "touchscreen", title: "TOUCHSCREEN GESTURES", have: "touchscreen" }
        ]
        delegate: ColumnLayout {
            id: grp
            required property var modelData
            readonly property var rows: page.list(modelData.device)
            Layout.fillWidth: true
            visible: rows.length > 0
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                SectionTitle { text: grp.modelData.title }
                Text {
                    Layout.topMargin: 6
                    visible: !page.found(grp.modelData.have)
                    text: "None connected"
                    color: Theme.faint
                    font.family: Theme.sans
                    font.pixelSize: 12
                }
            }
            Card {
                Repeater {
                    model: grp.rows
                    delegate: Cell {
                        required property var modelData
                        required property int index
                        last: index === grp.rows.length - 1
                        title: modelData.motion
                        Text {
                            text: modelData.action
                            color: Theme.sub
                            font.family: Theme.sans
                            font.pixelSize: 13
                        }
                    }
                }
            }
        }
    }

    SectionTitle { text: "DEVICES" }
    Card {
        Repeater {
            model: [
                { key: "touchscreen", name: "Touchscreen" },
                { key: "touchpad", name: page.padName },
                { key: "pen", name: "Pen or stylus" },
                { key: "sensor", name: "Orientation sensor" }
            ]
            delegate: Cell {
                required property var modelData
                required property int index
                last: index === 3
                title: modelData.name
                Text {
                    text: page.found(modelData.key) ? "Connected" : "Not found"
                    color: page.found(modelData.key) ? Theme.good : Theme.faint
                    font.family: Theme.sans
                    font.pixelSize: 13
                }
            }
        }
    }
    Text {
        Layout.leftMargin: 4
        Layout.fillWidth: true
        text: "Touch and hold opens the context menu in KDE and GTK apps. A pen's lower button right-clicks."
        color: Theme.sub
        font.family: Theme.sans
        font.pixelSize: 12
        wrapMode: Text.WordWrap
    }
}
