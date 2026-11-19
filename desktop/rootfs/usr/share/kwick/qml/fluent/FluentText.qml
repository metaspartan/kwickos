import QtQuick

Text {
    property bool strong: false
    property int level: 0

    color: level === 0 ? Fluent.text : level === 1 ? Fluent.text2 : Fluent.text3
    font.family: Fluent.family
    font.pixelSize: Fluent.body
    font.weight: strong ? Font.DemiBold : Font.Normal
    textFormat: Text.PlainText
    elide: Text.ElideRight
}
