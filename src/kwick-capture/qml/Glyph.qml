import QtQuick
import KwickCapture

Image {
    property string name
    property color tint: "#000000"
    width: 22
    height: 22
    source: name === "" ? "" : "image://capture/icon/" + name + "/" + tint.toString().substring(1)
    sourceSize: Qt.size(width * 2, height * 2)
    smooth: true
    mipmap: true
    cache: true
}
