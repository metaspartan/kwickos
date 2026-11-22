import QtQuick

Image {
    property string name
    property color tint: "#000000"
    width: 20
    height: 20
    source: name === "" ? "" : Nearby.icon(name, tint)
    sourceSize: Qt.size(width * 2, height * 2)
    smooth: true
    mipmap: true
    cache: true
}
