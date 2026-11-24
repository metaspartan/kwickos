import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property alias mainItem: contentsControl.contentItem
    property alias mainText: titleHeading.text
    property alias subtitle: subtitleLabel.text
    property alias iconName: icon.source
    property list<T.Action> actions
    readonly property alias dialogButtonBox: footerButtonBox

    property Window window
    readonly property int flags: Qt.Dialog | Qt.WindowCloseButtonHint | Qt.WindowTitleHint | Qt.WindowSystemMenuHint
    property alias standardButtons: footerButtonBox.standardButtons

    readonly property real minimumHeight: implicitHeight
    readonly property real minimumWidth: Math.min(Math.round(Screen.width / 3), implicitWidth)
    readonly property int textWidth: Kirigami.Units.gridUnit * 20

    function present() {
        plainButtons();
        window.show();
    }

    function plainButtons() {
        const primary = footerButtonBox.standardButton(QQC2.DialogButtonBox.Ok)
            || footerButtonBox.standardButton(QQC2.DialogButtonBox.Yes)
            || footerButtonBox.standardButton(QQC2.DialogButtonBox.Save)
            || footerButtonBox.standardButton(QQC2.DialogButtonBox.Apply);
        for (const button of footerButtonBox.contentChildren) {
            if (button.icon) {
                button.icon.name = "";
                button.icon.source = "";
            }
            button.Accessible.defaultButton = button === primary;
        }
    }

    spacing: 0

    Kirigami.Icon {
        id: icon
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Kirigami.Units.gridUnit
        visible: source
        implicitWidth: Kirigami.Units.iconSizes.huge
        implicitHeight: Kirigami.Units.iconSizes.huge
    }

    Kirigami.Heading {
        id: titleHeading
        Layout.fillWidth: true
        Layout.preferredWidth: Math.min(implicitWidth, root.textWidth)
        Layout.topMargin: icon.visible ? Kirigami.Units.largeSpacing * 2 : Kirigami.Units.gridUnit
        Layout.leftMargin: Kirigami.Units.gridUnit
        Layout.rightMargin: Kirigami.Units.gridUnit
        level: 4
        font.weight: Font.Bold
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        textFormat: Text.RichText
        elide: Text.ElideRight
    }

    QQC2.Label {
        id: subtitleLabel
        Layout.fillWidth: true
        Layout.preferredWidth: Math.min(implicitWidth, root.textWidth)
        Layout.topMargin: Kirigami.Units.largeSpacing
        Layout.leftMargin: Kirigami.Units.gridUnit
        Layout.rightMargin: Kirigami.Units.gridUnit
        horizontalAlignment: Text.AlignHCenter
        font.pointSize: Kirigami.Theme.smallFont.pointSize
        wrapMode: Text.Wrap
        elide: Text.ElideRight
        textFormat: Text.RichText
        visible: text.length > 0
    }

    QQC2.Control {
        id: contentsControl

        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.topMargin: Kirigami.Units.gridUnit
        Layout.leftMargin: Kirigami.Units.gridUnit
        Layout.rightMargin: Kirigami.Units.gridUnit

        visible: contentItem !== null
    }

    QQC2.DialogButtonBox {
        id: footerButtonBox

        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        Layout.bottomMargin: Kirigami.Units.largeSpacing

        buttonLayout: QQC2.DialogButtonBox.MacLayout
        alignment: Qt.AlignRight
        visible: count > 0

        onAccepted: root.window.accept()
        onRejected: root.window.reject()
        onContentChildrenChanged: Qt.callLater(root.plainButtons)

        Repeater {
            model: root.actions

            delegate: QQC2.Button {
                action: modelData
                icon.name: ""
            }
        }
    }

    Item {
        Layout.preferredHeight: Kirigami.Units.largeSpacing
        visible: !footerButtonBox.visible
    }
}
