import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

Popup {
    id: picker
    property real hue: 0
    property real sat: 1
    property real val: 1
    readonly property color value: Qt.hsva(hue, sat, val, 1)
    readonly property string hex: "#" + [value.r, value.g, value.b].map(function (c) { return ("0" + Math.round(c * 255).toString(16)).slice(-2) }).join("")
    signal picked(string hex)
    width: 260
    padding: 14
    modal: false
    margins: 12
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Rectangle { radius: 12; color: Theme.popup; border.width: 1; border.color: Theme.lineStrong }

    function openAt(item, start) {
        setHex(String(start))
        var p = item.mapToItem(parent, 0, item.height + 10)
        x = Math.max(0, Math.min(p.x + item.width - width, parent.width - width))
        y = p.y
        open()
    }

    function setHex(h) {
        var m = /^#?([0-9a-fA-F]{6})$/.exec(h.trim())
        if (!m) return false
        var c = Qt.color("#" + m[1])
        hue = c.hsvHue < 0 ? hue : c.hsvHue
        sat = c.hsvSaturation
        val = c.hsvValue
        return true
    }

    contentItem: ColumnLayout {
        spacing: 12

        Text { text: "Custom Accent Color"; color: Theme.text; font.family: Theme.sans; font.pixelSize: 13; font.weight: Font.DemiBold }

        Rectangle {
            id: field
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            radius: 8
            color: Qt.hsva(picker.hue, 1, 1, 1)
            Rectangle {
                anchors.fill: parent
                radius: 8
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#ffffffff" }
                    GradientStop { position: 1; color: "#00ffffff" }
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: 8
                border.width: 1
                border.color: Theme.line
                gradient: Gradient {
                    GradientStop { position: 0; color: "#00000000" }
                    GradientStop { position: 1; color: "#ff000000" }
                }
            }
            Rectangle {
                x: picker.sat * field.width - width / 2
                y: (1 - picker.val) * field.height - height / 2
                width: 14
                height: 14
                radius: 7
                color: picker.value
                border.width: 2
                border.color: "#ffffff"
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.CrossCursor
                function pick(m) {
                    picker.sat = Math.max(0, Math.min(1, m.x / width))
                    picker.val = Math.max(0, Math.min(1, 1 - m.y / height))
                }
                onPressed: (m) => pick(m)
                onPositionChanged: (m) => pick(m)
            }
        }

        Rectangle {
            id: hueBar
            Layout.fillWidth: true
            Layout.preferredHeight: 12
            radius: 6
            border.width: 1
            border.color: Theme.line
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#ff0000" }
                GradientStop { position: 0.167; color: "#ffff00" }
                GradientStop { position: 0.333; color: "#00ff00" }
                GradientStop { position: 0.5; color: "#00ffff" }
                GradientStop { position: 0.667; color: "#0000ff" }
                GradientStop { position: 0.833; color: "#ff00ff" }
                GradientStop { position: 1; color: "#ff0000" }
            }
            Rectangle {
                x: picker.hue * hueBar.width - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                radius: 8
                color: Qt.hsva(picker.hue, 1, 1, 1)
                border.width: 2
                border.color: "#ffffff"
            }
            MouseArea {
                anchors.fill: parent
                anchors.topMargin: -6
                anchors.bottomMargin: -6
                cursorShape: Qt.PointingHandCursor
                function pick(m) { picker.hue = Math.max(0, Math.min(0.999, m.x / width)) }
                onPressed: (m) => pick(m)
                onPositionChanged: (m) => pick(m)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: 13
                color: picker.value
                border.width: 1
                border.color: Theme.lineStrong
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                radius: 7
                color: Theme.field
                border.width: 1
                border.color: hexInput.activeFocus ? Theme.accent : Theme.line
                TextInput {
                    id: hexInput
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    text: picker.hex.toUpperCase()
                    color: Theme.text
                    font.family: Theme.mono
                    font.pixelSize: 12
                    selectionColor: Theme.textSelection
                    selectedTextColor: Theme.text
                    maximumLength: 7
                    onEditingFinished: {
                        picker.setHex(text)
                        text = Qt.binding(function () { return picker.hex.toUpperCase() })
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Item { Layout.fillWidth: true }
            Btn { text: "Cancel"; onClicked: picker.close() }
            Btn { text: "Use Color"; primary: true; onClicked: { picker.setHex(hexInput.text); picker.picked(picker.hex); picker.close() } }
        }
    }
}
