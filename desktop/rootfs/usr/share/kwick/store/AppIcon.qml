import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: ai
    property string source
    property string name
    property real size: 64
    readonly property bool themed: source.indexOf("theme:") === 0
    readonly property bool failed: !themed && (source === "" || img.status === Image.Error)
    implicitWidth: size
    implicitHeight: size

    Image {
        id: img
        anchors.fill: parent
        visible: !ai.themed && status === Image.Ready
        source: ai.themed ? "" : ai.source
        sourceSize.width: Math.ceil(ai.size * 2)
        sourceSize.height: Math.ceil(ai.size * 2)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
    }

    Kirigami.Icon {
        id: themedIcon
        anchors.fill: parent
        visible: ai.themed && valid
        source: ai.themed ? ai.source.slice(6) : ""
        fallback: "package-x-generic"
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: ai.size * 0.06
        visible: ai.failed || (ai.themed && !themedIcon.valid)
        radius: Look.win ? ai.size * 0.14 : ai.size * 0.23
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.hsla((ai.name.charCodeAt(0) || 65) % 12 / 12, 0.55, 0.58, 1) }
            GradientStop { position: 1; color: Qt.hsla((ai.name.charCodeAt(0) || 65) % 12 / 12, 0.6, 0.42, 1) }
        }
        Text {
            anchors.centerIn: parent
            text: ai.name.length ? ai.name.charAt(0).toUpperCase() : "?"
            color: "#ffffff"
            font.family: Look.display
            font.pixelSize: ai.size * 0.46
            font.weight: Font.DemiBold
        }
    }
}
