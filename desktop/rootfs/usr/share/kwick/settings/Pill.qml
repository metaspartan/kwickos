import QtQuick

Rectangle {
    id: pill
    property string text
    property string tone: "neutral"
    implicitWidth: label.implicitWidth + 20
    implicitHeight: 24
    radius: 12
    color: tone === "good" ? Theme.goodBg : tone === "warn" ? Theme.warnBg : tone === "bad" ? Theme.badBg : Theme.line

    Text {
        id: label
        anchors.centerIn: parent
        text: pill.text
        color: pill.tone === "good" ? Theme.good : pill.tone === "warn" ? Theme.warn : pill.tone === "bad" ? Theme.bad : Theme.sub
        font.family: Theme.sans
        font.pixelSize: 12
        font.weight: Font.DemiBold
    }
}
