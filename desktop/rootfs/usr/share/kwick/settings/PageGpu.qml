import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: page
    spacing: 10

    property var kernels: []
    property var kernelInfo: ({})
    property bool kernelTool: true

    function loadKernels() {
        Sys.run("kwick-kernel list --json 2>/dev/null", function (out) {
            try {
                var j = JSON.parse(out)
                page.kernels = j.installed
                page.kernelInfo = j
                page.kernelTool = true
            } catch (e) {
                page.kernelTool = false
            }
        })
    }

    function kernelAct(verb, id) {
        Sys.terminal(Sys.elevated("kwick-kernel " + verb + " " + id))
        kernelRefresh.restart()
    }

    Component.onCompleted: loadKernels()

    Timer {
        id: kernelRefresh
        interval: 4000
        onTriggered: page.loadKernels()
    }

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

    SectionTitle { text: "KERNEL" }
    Card {
        Cell {
            visible: !page.kernelTool || page.kernels.length === 0
            last: true
            title: page.kernelTool ? "No kernels registered" : "kwick-kernel is not available"
            subtitle: page.kernelTool ? "Install one with: sudo kwick-kernel install latest" : "This system has no kwick-kernel tool."
        }
        Repeater {
            model: page.kernels
            delegate: Cell {
                required property var modelData
                required property int index
                last: index === page.kernels.length - 1
                title: modelData.flavor + " " + modelData.version + (modelData.running ? "  (running)" : "")
                subtitle: modelData.release + "  " + Math.round(modelData.size_kb / 1024) + " MB"
                          + (modelData.default ? "  default" : "") + (modelData.previous ? "  previous" : "")
                          + (modelData.trial ? "  trial pending, reboot to run it" : "")
                Btn { visible: !modelData.default; text: "Set default"; primary: true; onClicked: page.kernelAct("default", modelData.id) }
                Btn { visible: !modelData.default && page.kernelInfo.boot !== "none" && page.kernelInfo.boot !== "apple"; text: "Try once"; onClicked: page.kernelAct("try", modelData.id) }
            }
        }
    }
    Text {
        visible: page.kernelTool
        Layout.fillWidth: true
        text: "Boot path: " + (page.kernelInfo.boot || "unknown") + ".  Try once boots the kernel one time; the default boots again if it does not come up. Reboot to apply."
        color: Theme.sub
        font.family: Theme.sans
        font.pixelSize: 12
        wrapMode: Text.WordWrap
    }
}
