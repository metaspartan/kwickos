import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: page
    spacing: 10

    property var st: ({})
    property bool loaded: false
    property bool installed: true
    property string note: ""

    function quote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    function load() {
        Sys.run("kwick-nearby --status 2>/dev/null", function (out, code) {
            page.installed = code === 0 && out.trim() !== ""
            if (page.installed) {
                try { page.st = JSON.parse(out.trim()) } catch (e) { page.st = ({}) }
            }
            page.loaded = true
            if (!nameInput.activeFocus)
                nameInput.text = page.st.alias || ""
            if (!pinInput.activeFocus)
                pinInput.text = page.st.pin || ""
        })
    }

    function set(key, value) {
        Sys.run("kwick-nearby --set " + key + " " + page.quote(value) + " 2>&1", function (out, code) {
            page.note = code === 0 ? "" : out.trim().replace(/^kwick-nearby: /, "")
            page.load()
        })
    }

    function homeShort(p) {
        return String(p || "").replace(/^\/home\/[^/]+/, "~")
    }

    Component.onCompleted: load()

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: page.load()
    }

    Card {
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 16
            spacing: 14
            Image {
                source: "file:///usr/share/icons/hicolor/scalable/apps/kwick-nearby.svg"
                sourceSize.width: 112
                sourceSize.height: 112
                Layout.preferredWidth: 56
                Layout.preferredHeight: 56
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                Text {
                    text: "Send to Phones and Computers Nearby"
                    color: Theme.text
                    font.family: Theme.sans
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    text: "Send files and text to phones and computers around you. Works with LocalSend on Android, iPhone, Windows, macOS and Linux, and with other KwickOS computers."
                    color: Theme.sub
                    font.family: Theme.sans
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    lineHeight: 1.12
                }
            }
            Btn {
                text: "Share Files…"
                primary: true
                enabled: page.installed
                onClicked: Sys.run("kwick-nearby --choose")
            }
        }
    }

    Text {
        Layout.fillWidth: true
        visible: page.loaded && !page.installed
        text: "Nearby Share is not installed. It comes with the kwick-desktop package."
        color: Theme.bad
        font.family: Theme.sans
        font.pixelSize: 12
    }

    SectionTitle { text: "RECEIVING" }
    Card {
        Cell {
            title: "Allow me to be discovered by"
            subtitle: page.st.effective === "everyone" ? "Any device nearby can ask to send you files for the next " + (page.st.minutesLeft || 10) + (page.st.minutesLeft === 1 ? " minute" : " minutes") + ". Then it changes to Known Devices Only."
                    : page.st.effective === "contacts" ? ((page.st.known || []).length ? "Only devices you accepted before can find you and ask to send." : "No device is known yet. Choose Everyone for 10 Minutes to receive from a new device.")
                    : "Nobody can find this computer. You can still send to others."
            Seg {
                options: [
                    { id: "off", label: "Off" },
                    { id: "contacts", label: "Known Devices" },
                    { id: "everyone", label: "Everyone for 10 Minutes" }
                ]
                current: page.st.effective || "off"
                onPicked: id => page.set("visibility", id)
            }
        }
        Cell {
            title: "Device name"
            subtitle: "Shown to the people who send you files"
            Rectangle {
                implicitWidth: 230
                implicitHeight: 28
                radius: 7
                color: Theme.field
                border.width: 1
                border.color: nameInput.activeFocus ? Theme.accent : Theme.lineStrong
                TextInput {
                    id: nameInput
                    anchors.fill: parent
                    anchors.leftMargin: 9
                    anchors.rightMargin: 9
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.text
                    font.family: Theme.sans
                    font.pixelSize: 13
                    selectionColor: Theme.accent
                    maximumLength: 64
                    clip: true
                    onEditingFinished: if (text.trim() !== "" && text !== page.st.alias) page.set("alias", text.trim())
                }
            }
        }
        Cell {
            title: "Save received files to"
            subtitle: page.homeShort(page.st.folder)
            Btn {
                text: "Change…"
                onClicked: Sys.run("zenity --file-selection --directory --title='Save Received Files To' 2>/dev/null", function (out, code) {
                    if (code === 0 && out.trim() !== "")
                        page.set("folder", out.trim())
                })
            }
        }
        Cell {
            last: true
            title: "Require a PIN"
            subtitle: page.st.requirePin ? "Senders must type this PIN before you are asked to accept" : "Senders need a PIN of 4 to 12 characters before they can ask"
            Rectangle {
                visible: page.st.requirePin || pinInput.activeFocus
                implicitWidth: 110
                implicitHeight: 28
                radius: 7
                color: Theme.field
                border.width: 1
                border.color: pinInput.activeFocus ? Theme.accent : Theme.lineStrong
                TextInput {
                    id: pinInput
                    anchors.fill: parent
                    anchors.leftMargin: 9
                    anchors.rightMargin: 9
                    verticalAlignment: TextInput.AlignVCenter
                    horizontalAlignment: TextInput.AlignHCenter
                    color: Theme.text
                    font.family: Theme.mono
                    font.pixelSize: 13
                    selectionColor: Theme.accent
                    maximumLength: 12
                    onEditingFinished: if (text.trim().length >= 4 && text.trim() !== page.st.pin) page.set("pin", text.trim())
                }
            }
            Toggle {
                checked: !!page.st.requirePin
                onToggled: value => {
                    if (value) {
                        var pin = String(Math.floor(100000 + Math.random() * 900000))
                        page.set("pin", pin)
                    } else {
                        page.set("pin", "")
                    }
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        visible: page.note !== ""
        text: page.note
        color: Theme.bad
        font.family: Theme.sans
        font.pixelSize: 12
        wrapMode: Text.WordWrap
    }

    SectionTitle { text: "KNOWN DEVICES" }
    Card {
        Cell {
            visible: (page.st.known || []).length === 0
            last: true
            title: "No known devices"
            subtitle: "A device becomes known when you accept something from it"
        }
        Repeater {
            model: page.st.known || []
            delegate: Cell {
                required property var modelData
                required property int index
                last: index === (page.st.known || []).length - 1
                title: modelData.alias || "Unknown Device"
                subtitle: (modelData.model || (modelData.type === "mobile" ? "Phone" : "Computer")) + "  ·  " + String(modelData.fingerprint).substring(0, 8)
                Btn {
                    text: "Forget"
                    onClicked: Sys.run("kwick-nearby --forget " + page.quote(modelData.fingerprint), page.load)
                }
            }
        }
    }

    SectionTitle { text: "NETWORK" }
    Card {
        Cell {
            title: "Ports"
            subtitle: "Nearby Share uses TCP and UDP port " + (page.st.port || 53317) + " (LocalSend protocol 2, encrypted with TLS). Allow both in a firewall to receive; sending only needs outgoing connections."
        }
        Cell {
            last: true
            title: "Security code"
            subtitle: page.st.fingerprint ? String(page.st.fingerprint).match(/.{1,4}/g).slice(0, 8).join(" ") : "Created the first time Nearby Share runs"
        }
    }
}
