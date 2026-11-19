import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3

Tile {
    id: tile

    property alias title: label.text
    property alias value: bar.value
    property alias icon: bar.icon
    property alias barActive: bar.active
    property alias trailing: extra.data

    signal moved(real value)
    signal iconClicked()

    PlasmaComponents3.Label {
        id: label
        font.weight: Font.DemiBold
        textFormat: Text.PlainText
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Bar {
            id: bar
            Layout.fillWidth: true
            onMoved: v => tile.moved(v)
            onIconClicked: tile.iconClicked()
        }

        RowLayout {
            id: extra
            spacing: 6
            visible: children.length > 0
        }
    }
}
