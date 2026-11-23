import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    property date now: new Date()
    readonly property bool use24h: Plasmoid.configuration.use24h === true || Plasmoid.configuration.use24h === "true"
    readonly property bool showDate: !(Plasmoid.configuration.showDate === false || Plasmoid.configuration.showDate === "false")
    readonly property string text: (showDate ? Qt.formatDate(now, "ddd MMM d") + "  " : "")
                                   + Qt.formatTime(now, use24h ? "H:mm" : "h:mm AP")

    toolTipMainText: Qt.formatDate(now, "dddd, MMMM d, yyyy")
    toolTipSubText: ""

    P5Support.DataSource {
        engine: "time"
        connectedSources: ["Local"]
        interval: 60000
        intervalAlignment: P5Support.Types.AlignToMinute
        onNewData: root.now = new Date()
    }

    compactRepresentation: MouseArea {
        Layout.minimumWidth: label.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        Layout.maximumWidth: Layout.minimumWidth
        Layout.fillHeight: true
        onClicked: root.expanded = !root.expanded

        PlasmaComponents3.Label {
            id: label
            anchors.centerIn: parent
            text: root.text
            font.weight: Font.Medium
            textFormat: Text.PlainText
        }
    }

    fullRepresentation: Item {
        id: cal

        property date month: new Date(root.now.getFullYear(), root.now.getMonth(), 1)
        readonly property date first: new Date(month.getFullYear(), month.getMonth(), 1 - month.getDay())
        readonly property int cell: 32
        readonly property color ink: Kirigami.Theme.textColor
        readonly property color accent: Kirigami.Theme.focusColor

        function shift(n) {
            month = new Date(month.getFullYear(), month.getMonth() + n, 1)
        }

        Layout.minimumWidth: cell * 7 + 24
        Layout.minimumHeight: 44 + 24 + cell * 6 + 12
        Layout.preferredWidth: Layout.minimumWidth
        Layout.preferredHeight: Layout.minimumHeight
        Layout.maximumWidth: Layout.minimumWidth
        Layout.maximumHeight: Layout.minimumHeight

        Connections {
            target: root
            function onExpandedChanged() {
                if (root.expanded)
                    cal.month = new Date(root.now.getFullYear(), root.now.getMonth(), 1)
            }
        }

        WheelHandler {
            onWheel: event => cal.shift(event.angleDelta.y > 0 ? -1 : 1)
        }

        PlasmaComponents3.Label {
            x: 14
            y: 10
            height: 24
            verticalAlignment: Text.AlignVCenter
            text: Qt.formatDate(cal.month, "MMMM") + " <font color=\"" + Qt.rgba(cal.ink.r, cal.ink.g, cal.ink.b, 0.55) + "\">" + Qt.formatDate(cal.month, "yyyy") + "</font>"
            textFormat: Text.StyledText
            font.weight: Font.Bold
            font.pixelSize: 15
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 8
            y: 10
            spacing: 0

            Repeater {
                model: [
                    { glyph: "go-previous-symbolic", step: -1 },
                    { glyph: "", step: 0 },
                    { glyph: "go-next-symbolic", step: 1 }
                ]
                delegate: MouseArea {
                    id: nav
                    required property var modelData
                    width: modelData.step === 0 ? 14 : 24
                    height: 24
                    hoverEnabled: true
                    onClicked: modelData.step === 0 ? cal.month = new Date(root.now.getFullYear(), root.now.getMonth(), 1) : cal.shift(modelData.step)
                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        visible: nav.modelData.step !== 0
                        color: nav.pressed ? Qt.rgba(cal.ink.r, cal.ink.g, cal.ink.b, 0.16) : nav.containsMouse ? Qt.rgba(cal.ink.r, cal.ink.g, cal.ink.b, 0.08) : "transparent"
                    }
                    Kirigami.Icon {
                        visible: nav.modelData.step !== 0
                        anchors.centerIn: parent
                        width: 14
                        height: 14
                        source: nav.modelData.glyph
                        color: cal.ink
                        isMask: true
                    }
                    Rectangle {
                        visible: nav.modelData.step === 0
                        anchors.centerIn: parent
                        width: 6
                        height: 6
                        radius: 3
                        color: Qt.rgba(cal.ink.r, cal.ink.g, cal.ink.b, 0.55)
                    }
                }
            }
        }

        Row {
            x: 12
            y: 44
            Repeater {
                model: 7
                delegate: PlasmaComponents3.Label {
                    required property int index
                    width: cal.cell
                    height: 20
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: Qt.locale().dayName(index, Locale.NarrowFormat)
                    opacity: 0.55
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }
        }

        Grid {
            x: 12
            y: 68
            columns: 7
            Repeater {
                model: 42
                delegate: Item {
                    id: day
                    required property int index
                    readonly property date date: new Date(cal.first.getFullYear(), cal.first.getMonth(), cal.first.getDate() + index)
                    readonly property bool inMonth: date.getMonth() === cal.month.getMonth()
                    readonly property bool isToday: date.toDateString() === root.now.toDateString()
                    width: cal.cell
                    height: cal.cell
                    Rectangle {
                        anchors.centerIn: parent
                        width: 26
                        height: 26
                        radius: 13
                        color: cal.accent
                        visible: day.isToday
                    }
                    PlasmaComponents3.Label {
                        anchors.centerIn: parent
                        text: day.date.getDate()
                        color: day.isToday ? "#ffffff" : cal.ink
                        opacity: day.isToday || day.inMonth ? 1 : 0.3
                        font.pixelSize: 13
                        font.weight: day.isToday ? Font.Bold : Font.Normal
                    }
                }
            }
        }
    }
}
