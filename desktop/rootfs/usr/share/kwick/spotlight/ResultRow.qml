import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: row

    required property int index
    required property string title
    required property string subtitle
    required property var icon
    required property string section
    required property bool topHit
    required property Item theme

    readonly property bool selected: ListView.isCurrentItem
    readonly property bool glyph: typeof icon === "string" && icon.indexOf("/kwick/spotlight/icons/") >= 0

    signal activated(bool alternate)

    height: topHit ? theme.topHeight : theme.rowHeight

    Rectangle {
        anchors.fill: parent
        radius: row.theme.rowRadius
        color: row.selected ? row.theme.accent : "transparent"
    }

    Kirigami.Icon {
        id: picture
        readonly property int box: row.topHit ? 34 : 24
        x: (row.topHit ? 9 : 10) + (box - width) / 2
        anchors.verticalCenter: parent.verticalCenter
        width: row.glyph ? Math.round(box * 0.84) : box
        height: width
        source: row.icon
        fallback: "unknown"
        animated: false
        isMask: row.glyph
        color: row.selected ? "white" : row.theme.label
    }

    Text {
        id: name
        x: (row.topHit ? 9 : 10) + picture.box + (row.topHit ? 11 : 10)
        y: row.topHit && row.subtitle !== "" ? 7 : Math.round((parent.height - height) / 2)
        width: Math.min(implicitWidth, parent.width - x - 14)
        text: row.title
        color: row.selected ? "white" : row.theme.label
        font.pixelSize: row.topHit ? 16 : 14
        font.weight: row.topHit ? Font.DemiBold : Font.Normal
        elide: Text.ElideRight
        maximumLineCount: 1
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
    }

    Text {
        x: row.topHit ? name.x : name.x + name.width + 8
        y: row.topHit ? name.y + name.height + 1 : name.y + name.baselineOffset - baselineOffset
        width: parent.width - x - 14
        visible: row.subtitle !== "" && width > 24
        text: row.subtitle
        color: row.selected ? Qt.rgba(1, 1, 1, 0.75) : row.theme.secondary
        font.pixelSize: row.topHit ? 13 : 12.5
        elide: Text.ElideRight
        maximumLineCount: 1
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
    }

    TapHandler {
        id: tap
        onTapped: row.activated((tap.point.modifiers & (Qt.ControlModifier | Qt.MetaModifier)) !== 0)
    }
}
