import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: page
    spacing: 10

    property var info: ({})

    function value(key) {
        return page.info[key] || "Unknown"
    }

    Component.onCompleted: Sys.run("sh " + Sys.dir + "helpers/about.sh", function (out) {
        var map = {}
        out.split("\n").forEach(function (l) {
            var i = l.indexOf("=")
            if (i > 0)
                map[l.slice(0, i)] = l.slice(i + 1).trim()
        })
        page.info = map
    })

    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: 6
        Layout.bottomMargin: 10
        spacing: 4

        Image {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 96
            Layout.preferredHeight: 96
            Layout.bottomMargin: 10
            source: "icons/app.svg"
            sourceSize.width: 192
            sourceSize.height: 192
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: page.info.name || "KwickOS"
            color: Theme.text
            font.family: Theme.sans
            font.pixelSize: 26
            font.weight: Font.DemiBold
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: "Version " + page.value("version") + (page.info.plasma ? "  ·  Plasma " + page.info.plasma : "")
            color: Theme.sub
            font.family: Theme.sans
            font.pixelSize: 13
        }
    }

    Card {
        Cell {
            title: "Name"
            Text { text: page.value("host"); color: Theme.sub; font.family: Theme.sans; font.pixelSize: 13 }
        }
        Cell {
            title: "Processor"
            Text {
                Layout.maximumWidth: 420
                text: page.value("cpu") + (page.info.cores ? "  (" + page.info.cores + " cores)" : "")
                color: Theme.sub
                font.family: Theme.sans
                font.pixelSize: 13
                elide: Text.ElideRight
            }
        }
        Cell {
            title: "Graphics"
            Text {
                Layout.maximumWidth: 420
                text: page.value("gpu")
                color: Theme.sub
                font.family: Theme.sans
                font.pixelSize: 13
                elide: Text.ElideRight
            }
        }
        Cell {
            title: "Memory"
            Text { text: page.info.memory ? page.info.memory + " GB" : "Unknown"; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 13 }
        }
        Cell {
            title: "Startup Disk"
            Text { text: page.value("disk"); color: Theme.sub; font.family: Theme.sans; font.pixelSize: 13 }
        }
        Cell {
            title: "Display"
            visible: !!page.info.display
            Text { text: page.value("display"); color: Theme.sub; font.family: Theme.sans; font.pixelSize: 13 }
        }
        Cell {
            title: "Kernel"
            last: true
            Text { text: page.value("kernel") + "  " + page.value("arch"); color: Theme.sub; font.family: Theme.mono; font.pixelSize: 12 }
        }
    }
}
