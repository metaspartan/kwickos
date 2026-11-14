import QtQuick
import QtQuick.Layouts

PageFrame {
    id: p
    icon: "icons/person.svg"
    title: "Create Your Account"
    subtitle: "This account can manage the computer and install software."
    maxWidth: 560
    iconSize: height < 700 ? 52 : 64
    canContinue: Inst.accountValid()
    strictContinue: false
    firstFocus: nameField

    property bool userTouched: false
    property bool pwTouched: false
    property bool hostTouched: false
    readonly property int score: Inst.strength(Inst.password)
    readonly property var words: ["", "Weak", "Fair", "Good", "Strong"]
    readonly property var colors: ["transparent", Theme.bad, Theme.warn, Theme.good, Theme.good]

    function setName(t) {
        Inst.fullname = t
        if (!Inst.userEdited) Inst.user = Inst.deriveUser(t)
        if (!Inst.hostEdited) Inst.hostname = Inst.deriveHost(Inst.user)
    }

    KCard {
        padding: 20
        spacing: 12

        FormRow {
            id: nameRow
            label: "Full name"
            error: p.attempted && Inst.fullname.trim() === ""
            message: error ? "Enter your name." : ""
            KField {
                id: nameField
                Layout.fillWidth: true
                placeholder: "Jane Appleseed"
                text: Inst.fullname
                invalid: nameRow.error
                maximumLength: 120
                onEdited: p.setName(text)
                KeyNavigation.tab: userField
            }
        }

        FormRow {
            id: userRow
            label: "Account name"
            error: (p.userTouched || p.attempted) && Inst.userError() !== ""
            message: error ? Inst.userError() : (Inst.user !== "" ? "Your home folder will be /home/" + Inst.user : "")
            KField {
                id: userField
                Layout.fillWidth: true
                placeholder: "jane"
                text: Inst.user
                invalid: userRow.error
                maximumLength: 32
                onEdited: {
                    Inst.userEdited = text !== ""
                    Inst.user = text
                    p.userTouched = true
                    if (!Inst.hostEdited) Inst.hostname = Inst.deriveHost(text)
                }
                onActiveFocusChanged: if (!activeFocus && text !== "") p.userTouched = true
                KeyNavigation.tab: pwField
            }
        }

        FormRow {
            id: pwRow
            label: "Password"
            error: p.attempted && Inst.password === ""
            message: error ? "Choose a password." : ""
            KField {
                id: pwField
                Layout.fillWidth: true
                password: true
                placeholder: "Required"
                text: Inst.password
                invalid: pwRow.error
                onEdited: Inst.password = text
                KeyNavigation.tab: pw2Field
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                visible: Inst.password !== ""
                spacing: 4
                Repeater {
                    model: 4
                    Rectangle {
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: 4
                        radius: 2
                        color: index < p.score ? p.colors[p.score] : Theme.track
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }
                }
                Text {
                    Layout.leftMargin: 8
                    Layout.preferredWidth: 46
                    text: p.words[p.score]
                    color: p.colors[p.score]
                    font.family: Theme.sans
                    font.pixelSize: Theme.smallSize
                    font.weight: Font.Medium
                }
            }
        }

        FormRow {
            id: pw2Row
            label: "Verify"
            error: (Inst.password2 !== "" || p.attempted) && Inst.password2 !== Inst.password
            message: error ? (Inst.password2 === "" ? "Enter the password again." : "The passwords don’t match.") : ""
            KField {
                id: pw2Field
                Layout.fillWidth: true
                password: true
                placeholder: "Verify"
                text: Inst.password2
                invalid: pw2Row.error
                onEdited: Inst.password2 = text
                KeyNavigation.tab: hostField
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 2
            Layout.bottomMargin: 2
            implicitHeight: 1
            color: Theme.line
        }

        FormRow {
            id: hostRow
            label: "Computer name"
            error: (p.hostTouched || p.attempted) && Inst.hostError() !== ""
            message: error ? Inst.hostError() : "How this computer appears on your network"
            KField {
                id: hostField
                Layout.fillWidth: true
                placeholder: "jane-kwickos"
                text: Inst.hostname
                invalid: hostRow.error
                maximumLength: 63
                onEdited: {
                    Inst.hostEdited = text !== ""
                    Inst.hostname = text
                    p.hostTouched = true
                }
                KeyNavigation.tab: autoToggle
            }
        }

        FormRow {
            label: ""
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Text {
                    Layout.fillWidth: true
                    text: "Log in automatically"
                    color: Theme.text
                    font.family: Theme.sans
                    font.pixelSize: Theme.bodySize
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Inst.autologin = !Inst.autologin }
                }
                KToggle {
                    id: autoToggle
                    checked: Inst.autologin
                    onToggled: (v) => Inst.autologin = v
                }
            }
        }
    }
}