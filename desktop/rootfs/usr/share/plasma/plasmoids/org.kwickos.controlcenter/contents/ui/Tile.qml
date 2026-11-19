import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Rectangle {
    id: tile

    default property alias content: column.data
    property int padding: 10

    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + padding * 2
    radius: 14
    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.07)
    border.width: 1
    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06)

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: tile.padding
        spacing: 8
    }
}
