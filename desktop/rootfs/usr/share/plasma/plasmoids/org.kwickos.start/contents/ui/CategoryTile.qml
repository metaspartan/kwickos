import QtQuick
import org.kde.kirigami as Kirigami
import "file:///usr/share/kwick/qml/fluent"

Item {
    id: category

    property string label
    property var apps
    signal open()
    signal launch(int row)

    width: 192
    height: 188

    MouseArea {
        id: box
        width: 152
        height: 152
        anchors.horizontalCenter: parent.horizontalCenter
        hoverEnabled: true
        onClicked: category.open()

        Rectangle {
            anchors.fill: parent
            radius: Fluent.overlayRadius
            color: box.pressed ? Fluent.controlPressed : box.containsMouse ? Fluent.controlHover : Fluent.card
            border.width: 1
            border.color: Fluent.controlStroke
        }

        Grid {
            anchors.centerIn: parent
            columns: 2
            spacing: 8

            Repeater {
                model: category.apps

                delegate: MouseArea {
                    id: cell
                    required property int index
                    required property var model
                    visible: index < 4
                    width: 56
                    height: 56
                    hoverEnabled: true
                    onClicked: category.launch(index)

                    Subtle {
                        anchors.fill: parent
                        hovered: cell.containsMouse
                        pressed: cell.pressed
                    }

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: 32
                        height: 32
                        source: cell.model.decoration
                    }
                }
            }
        }
    }

    FluentText {
        anchors.top: box.bottom
        anchors.topMargin: 8
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Fluent.caption
        text: category.label
    }
}
