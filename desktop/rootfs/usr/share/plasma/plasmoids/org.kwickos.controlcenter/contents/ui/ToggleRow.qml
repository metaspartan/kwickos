import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

RowLayout {
    id: row

    property alias on: glyph.on
    property alias icon: glyph.icon
    property alias title: title.text
    property alias subtitle: subtitle.text

    property bool hasDetails: false

    signal clicked()
    signal details()

    Layout.fillWidth: true
    spacing: 9

    Glyph {
        id: glyph
        onClicked: row.clicked()
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0

        TapHandler {
            enabled: row.hasDetails
            onTapped: row.details()
        }
        HoverHandler {
            cursorShape: row.hasDetails ? Qt.PointingHandCursor : Qt.ArrowCursor
        }

        PlasmaComponents3.Label {
            id: title
            Layout.fillWidth: true
            font.weight: Font.DemiBold
            textFormat: Text.PlainText
            elide: Text.ElideRight
        }
        PlasmaComponents3.Label {
            id: subtitle
            Layout.fillWidth: true
            visible: text !== ""
            font: Kirigami.Theme.smallFont
            opacity: 0.6
            textFormat: Text.PlainText
            elide: Text.ElideRight
        }
    }
}
