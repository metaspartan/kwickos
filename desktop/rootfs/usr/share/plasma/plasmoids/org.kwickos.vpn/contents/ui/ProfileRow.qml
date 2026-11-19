import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "file:///usr/share/kwick/qml/menu"

MouseArea {
    id: row

    required property string name
    required property string status
    property string detail
    property string address
    property string error
    readonly property bool on: status === "connected" || status === "connecting"
    readonly property bool busy: status === "connecting" || status === "disconnecting"
    readonly property color dim: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.55)

    signal toggled(bool on)

    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + 12
    hoverEnabled: true
    onClicked: toggled(!on)

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
        visible: row.containsMouse
    }

    RowLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 6
        anchors.rightMargin: 10
        spacing: 9

        Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 26
            Layout.preferredHeight: 26
            radius: 13
            color: row.status === "connected" ? Kirigami.Theme.highlightColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.16)
            Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

            Kirigami.Icon {
                anchors.centerIn: parent
                width: 16
                height: 16
                source: "object-locked-symbolic"
                isMask: true
                color: "#ffffff"
            }

            SequentialAnimation on opacity {
                running: row.busy
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 0.4; duration: 600; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: row.name
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: row.error !== "" ? row.error : row.detail
                color: row.error !== "" ? Kirigami.Theme.negativeTextColor : row.dim
                font: Kirigami.Theme.smallFont
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: row.address !== "" && row.error === ""
                text: "IP Address " + row.address
                color: row.dim
                font: Kirigami.Theme.smallFont
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
        }

        MacSwitch {
            Layout.alignment: Qt.AlignVCenter
            checked: row.on
            onToggled: on => row.toggled(on)
        }
    }
}
