import QtQuick
import QtQuick.Layouts

ColumnLayout {
    spacing: 10

    SectionTitle { text: "GRAPHICS" }
    Card {
        Cell {
            title: "Compositor"
            subtitle: Sys.compositor === "gpu" ? "Hardware OpenGL: window effects can animate"
                    : Sys.compositor === "software" ? "Software OpenGL (llvmpipe): KWin turns animations off"
                    : "No OpenGL compositor running"
            Rectangle {
                implicitWidth: cl.implicitWidth + 20
                implicitHeight: 24
                radius: 12
                color: Sys.compositor === "gpu" ? "#1e3a28" : Sys.compositor === "software" ? "#3d2e12" : "#40201e"
                Text {
                    id: cl
                    anchors.centerIn: parent
                    text: Sys.compositor === "gpu" ? "GPU" : Sys.compositor === "software" ? "Software" : "None"
                    color: Sys.compositor === "gpu" ? Theme.good : Sys.compositor === "software" ? Theme.warn : Theme.bad
                    font.family: Theme.sans
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }
        }
        Cell {
            title: "Rendering backend"
            subtitle: "Reported by KWin"
            last: true
            Text { text: Sys.compositorType !== "" ? Sys.compositorType : "unknown"; color: Theme.sub; font.family: Theme.mono; font.pixelSize: 13 }
        }
    }

    SectionTitle { text: "DETECTED HARDWARE" }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: gtxt.implicitHeight + 28
        radius: 12
        color: Theme.card
        border.width: 1
        border.color: Theme.line
        Text {
            id: gtxt
            anchors.fill: parent
            anchors.margins: 14
            text: Sys.gpuInfo !== "" ? Sys.gpuInfo : "Detecting…"
            color: Theme.text
            font.family: Theme.mono
            font.pixelSize: 12
            wrapMode: Text.WrapAnywhere
            lineHeight: 1.25
        }
    }

    SectionTitle { text: "DRIVERS" }
    Card {
        Cell {
            last: true
            title: "Install graphics drivers"
            subtitle: "Mesa, Vulkan and vendor firmware for the detected GPU (kwick-gpu). Log in again afterwards."
            Btn { text: "Install kwick-gpu"; primary: true; onClicked: Sys.terminal("kwick-gpu install") }
        }
    }
}
