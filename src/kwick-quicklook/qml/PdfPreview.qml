import QtQuick
import QtQuick.Controls.Basic

Item {
    id: view
    required property var theme
    readonly property real pageWidth: Math.min(list.width - 48, 1400)
    readonly property real aspect: ql.pageSize.width > 0 ? ql.pageSize.height / ql.pageSize.width : 1.414

    ListView {
        id: list
        anchors.fill: parent
        model: ql.pages
        spacing: 16
        topMargin: 20
        bottomMargin: 20
        clip: true
        cacheBuffer: 2000
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        delegate: Item {
            required property int index
            width: list.width
            height: Math.round(view.pageWidth * view.aspect)

            Rectangle {
                anchors.fill: page
                anchors.margins: -1
                color: "transparent"
                border.width: 1
                border.color: view.theme.hairline
            }

            Rectangle {
                id: page
                width: view.pageWidth
                height: parent.height
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#ffffff"

                Image {
                    anchors.fill: parent
                    asynchronous: true
                    cache: false
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: Math.round(view.pageWidth * Screen.devicePixelRatio)
                    source: "image://pdf/" + index + "/" + encodeURIComponent(ql.pdf)
                }
            }
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        visible: ql.pages > 1
        width: pageLabel.implicitWidth + 22
        height: 24
        radius: 12
        color: view.theme.dark ? Qt.rgba(0.17, 0.17, 0.18, 0.92) : Qt.rgba(0.98, 0.98, 0.98, 0.94)
        border.width: 1
        border.color: view.theme.hairline
        Text {
            id: pageLabel
            anchors.centerIn: parent
            text: "Page " + (Math.min(ql.pages, list.indexAt(list.width / 2, list.contentY + list.height / 2) + 1) || 1) + " of " + ql.pages
            color: view.theme.secondary
            font.family: view.theme.sans
            font.pixelSize: 11
            renderType: Text.NativeRendering
        }
    }

    Text {
        anchors.centerIn: parent
        visible: ql.busy
        text: "Preparing preview…"
        color: view.theme.secondary
        font.family: view.theme.sans
        font.pixelSize: 14
    }
}
