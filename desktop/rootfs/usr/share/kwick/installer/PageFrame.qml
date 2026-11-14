import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

Item {
    id: pf
    property string icon
    property string title
    property string subtitle
    property real iconSize: height < 640 ? 60 : 72
    property real maxWidth: Theme.contentWidth
    property bool canContinue: true
    property bool canGoBack: true
    property string continueText: "Continue"
    property string continueKind: "primary"
    property bool showNav: true
    property bool strictContinue: true
    property bool attempted: false
    property bool busy: false
    property string backText: "Back"
    property var interceptNext: null
    property var interceptBack: null
    property alias flickable: flick
    property Item firstFocus: null
    default property alias content: body.data
    signal advance()

    function focusFirst() {
        if (firstFocus) firstFocus.forceActiveFocus()
    }

    Rectangle {
        z: 2
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 12
        height: 28
        opacity: flick.contentHeight > flick.height + 2 && !flick.atYEnd ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0) }
            GradientStop { position: 1; color: Theme.bg }
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight + col.y + 32
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        ScrollBar.vertical: ScrollBar { policy: flick.contentHeight > flick.height + 2 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

        ColumnLayout {
            id: col
            width: Math.min(pf.maxWidth, flick.width - 64)
            x: (flick.width - width) / 2
            y: Math.max(28, Math.min(flick.height * 0.075, 64))
            spacing: 0

            Image {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: pf.iconSize
                Layout.preferredHeight: pf.iconSize
                visible: pf.icon !== ""
                source: pf.icon
                sourceSize.width: pf.iconSize * 2
                sourceSize.height: pf.iconSize * 2
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: pf.icon !== "" ? 18 : 0
                visible: pf.title !== ""
                text: pf.title
                color: Theme.text
                font.family: Theme.sans
                font.pixelSize: Theme.titleSize
                font.weight: Font.Bold
                font.letterSpacing: -0.4
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 10
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                visible: pf.subtitle !== ""
                text: pf.subtitle
                color: Theme.sub
                font.family: Theme.sans
                font.pixelSize: Theme.subtitleSize
                lineHeight: 1.18
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
            ColumnLayout {
                id: body
                Layout.bottomMargin: 8
                Layout.fillWidth: true
                Layout.topMargin: pf.title !== "" || pf.icon !== "" ? 30 : 0
                spacing: 14
            }
        }
    }
}
