import QtQuick
import org.kde.plasma.core as PlasmaCore
import org.kde.kwin as KWin
import org.kde.kirigami as Kirigami
import "file:///usr/share/kwick/qml/fluent"

KWin.TabBoxSwitcher {
    id: tabBox

    Instantiator {
        active: tabBox.visible
        delegate: PlasmaCore.Dialog {
            location: PlasmaCore.Types.Floating
            visible: true
            flags: Qt.Popup | Qt.X11BypassWindowManagerHint
            x: tabBox.screenGeometry.x + Math.round((tabBox.screenGeometry.width - width) / 2)
            y: tabBox.screenGeometry.y + Math.round((tabBox.screenGeometry.height - height) / 2)

            mainItem: FocusScope {
                id: panel

                readonly property int cardHeight: 196
                readonly property int thumbHeight: 152
                readonly property real ratio: tabBox.screenGeometry.width / tabBox.screenGeometry.height
                readonly property int cardWidth: Math.round(thumbHeight * ratio) + 16

                focus: true
                width: Math.min(tabBox.screenGeometry.width * 0.9, Math.max(cardWidth, cards.contentWidth) + 32)
                height: cardHeight + 32

                ListView {
                    id: cards
                    anchors.fill: parent
                    anchors.margins: 16
                    orientation: ListView.Horizontal
                    spacing: 8
                    clip: true
                    focus: true
                    model: tabBox.model
                    currentIndex: tabBox.currentIndex
                    highlightMoveDuration: 0
                    highlightFollowsCurrentItem: true
                    keyNavigationWraps: true
                    onCurrentIndexChanged: tabBox.currentIndex = currentIndex

                    delegate: MouseArea {
                        id: card
                        required property int index
                        required property var model
                        readonly property bool current: ListView.isCurrentItem
                        width: panel.cardWidth
                        height: panel.cardHeight
                        hoverEnabled: true
                        onClicked: tabBox.model.activate(index)

                        Rectangle {
                            anchors.fill: parent
                            radius: Fluent.overlayRadius
                            color: card.containsMouse && !card.current ? Fluent.subtleHover : "transparent"
                            border.width: card.current ? 2 : 0
                            border.color: Fluent.text
                        }

                        Row {
                            x: 10
                            y: 10
                            width: parent.width - 20
                            spacing: 8

                            Kirigami.Icon {
                                width: 16
                                height: 16
                                source: card.model.icon
                            }

                            FluentText {
                                width: parent.width - 24
                                text: card.model.caption
                                font.pixelSize: Fluent.caption
                            }
                        }

                        KWin.WindowThumbnail {
                            x: 8
                            y: 36
                            width: parent.width - 16
                            height: panel.thumbHeight
                            wId: card.model.windowId
                        }
                    }
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Left)
                        cards.decrementCurrentIndex()
                    else if (event.key === Qt.Key_Right)
                        cards.incrementCurrentIndex()
                }
            }
        }
    }
}
