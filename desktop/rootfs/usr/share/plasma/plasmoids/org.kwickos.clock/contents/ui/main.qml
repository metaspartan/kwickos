import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.workspace.calendar as PlasmaCalendar
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

    fullRepresentation: PlasmaCalendar.MonthView {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 18
        Layout.preferredWidth: Layout.minimumWidth
        Layout.preferredHeight: Layout.minimumHeight
        today: root.now
        showWeekNumbers: false
    }
}
