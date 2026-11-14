import QtQuick
import QtQuick.Layouts

PageFrame {
    id: p
    icon: "icons/globe.svg"
    title: "Select Your Time Zone"
    subtitle: "Choose the city closest to you. KwickOS uses it to set the clock."
    canContinue: Inst.timezone !== ""
    firstFocus: list.searchField

    property string clock: ""

    function refreshClock() {
        if (Inst.timezone === "") { clock = ""; return }
        Inst.run("TZ=" + Inst.q(Inst.timezone) + " date '+%H:%M|%A'", function (out) {
            var s = out.trim().split("|")
            p.clock = s.length === 2 ? s[0] + ", " + s[1] : ""
        })
    }

    Component.onCompleted: refreshClock()
    Connections {
        target: Inst
        function onTimezoneChanged() { clockTimer.restart() }
    }
    Timer {
        id: clockTimer
        interval: 150
        onTriggered: p.refreshClock()
    }
    Timer {
        interval: 20000
        repeat: true
        running: true
        onTriggered: p.refreshClock()
    }

    SearchList {
        id: list
        Layout.fillWidth: true
        listHeight: Math.max(160, Math.min(340, p.height - 375))
        placeholder: "Search cities and regions"
        current: Inst.timezone
        items: Inst.timezones.map(function (z) { return { id: z, title: Inst.zoneCity(z), sub: Inst.zoneRegion(z) } })
        onPicked: (id) => Inst.timezone = id
        onActivated: Inst.navNext()
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 2
        spacing: 8
        visible: p.clock !== ""
        Rectangle {
            width: 8
            height: 8
            radius: 4
            color: Theme.good
        }
        Text {
            text: Inst.zoneCity(Inst.timezone) + " · " + p.clock
            color: Theme.sub
            font.family: Theme.sans
            font.pixelSize: 13
        }
    }
}
