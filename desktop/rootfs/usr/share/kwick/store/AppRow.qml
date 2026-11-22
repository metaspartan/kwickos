import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

Item {
    id: r
    property var app
    property string detail: ""
    property string trailing: ""
    property bool showButton: true
    property bool updateMode: false
    property bool removable: false
    property bool last: false
    property bool first: false
    property real iconSize: Look.mac ? 52 : Look.win ? 44 : 48
    signal removeClicked()
    Layout.fillWidth: true
    implicitHeight: Look.mac ? 76 : Look.win ? 72 : 72

    Rectangle {
        anchors.fill: parent
        anchors.bottomMargin: Look.win ? 4 : 0
        visible: !Look.mac
        radius: Look.win ? 8 : 0
        color: hover.containsMouse ? Look.cardHover : Look.card
        border.width: Look.win ? 1 : 0
        border.color: Look.cardStroke
    }

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: -8
        anchors.rightMargin: -8
        visible: Look.mac && hover.containsMouse
        radius: 10
        color: Look.hover
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: r.ApplicationWindow.window.openApp(r.app)
    }

    RowLayout {
        anchors.fill: parent
        anchors.bottomMargin: Look.win ? 4 : 0
        anchors.leftMargin: Look.mac ? 0 : 14
        anchors.rightMargin: Look.mac ? 0 : 14
        spacing: Look.mac ? 14 : 14

        AppIcon {
            Layout.preferredWidth: r.iconSize
            Layout.preferredHeight: r.iconSize
            size: r.iconSize
            source: r.app ? r.app.icon || "" : ""
            name: r.app ? r.app.name || "" : ""
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text {
                    Layout.preferredWidth: implicitWidth
                    Layout.minimumWidth: Math.min(implicitWidth, 60)
                    text: r.app ? r.app.name || "" : ""
                    color: Look.text
                    font.family: Look.sans
                    font.pixelSize: Look.win ? 14 : 14
                    font.weight: Look.win ? Font.DemiBold : Font.Medium
                    elide: Text.ElideRight
                }
                Glyph {
                    visible: !!(r.app && r.app.verified)
                    name: "verified"
                    size: 14
                    stroke: 1.5
                    color: Look.accentText
                }
                Repeater {
                    model: r.app ? (r.app.srcs || [r.app.src]) : []
                    delegate: Badge { required property var modelData; src: modelData }
                }
                Badge {
                    visible: !!(r.app && r.app.security)
                    label: "Security"
                    tint: Look.warn
                }
                Badge {
                    visible: !!(r.app && r.app.cve && r.app.cve.length)
                    label: r.app && r.app.cve ? r.app.cve.length + " CVE" : ""
                    tint: Look.bad
                }
                Item { Layout.fillWidth: true }
            }
            Text {
                Layout.fillWidth: true
                text: r.detail !== "" ? r.detail : r.app ? r.app.summary || "" : ""
                color: Look.sub
                font.family: Look.sans
                font.pixelSize: Look.small
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        Text {
            visible: r.trailing !== ""
            text: r.trailing
            color: Look.sub
            font.family: Look.sans
            font.pixelSize: Look.small
        }

        Btn {
            visible: r.removable && !Store.ops[r.app.key]
            flat: Look.mac
            text: "Remove"
            danger: false
            onClicked: r.removeClicked()
        }

        GetButton {
            visible: r.showButton
            app: r.app
            updateMode: r.updateMode
        }
    }

    Rectangle {
        visible: !r.last && !Look.win
        height: 1
        color: Look.line
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.leftMargin: Look.mac ? r.iconSize + 14 : 0
        anchors.right: parent.right
    }
}
