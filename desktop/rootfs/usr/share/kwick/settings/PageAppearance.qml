import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: page
    spacing: 10

    function accentLabel(name) {
        if (name.charAt(0) === "#") return "Custom, " + name.toUpperCase()
        for (var i = 0; i < Sys.accents.length; i++)
            if (Sys.accents[i].name === name) return Sys.accents[i].label
        return "Layout default"
    }

    readonly property var highlightOptions: {
        var out = [
            { id: "accent", label: "Accent Color", swatch: Theme.selection },
            { id: "graphite", label: "Graphite", swatch: Theme.light ? "#8e8e93" : "#98989d" }
        ]
        Sys.accents.forEach(function (a) {
            if (a.name !== "graphite") out.push({ id: a.name, label: a.label, swatch: Theme.light ? a.lhex : a.hex })
        })
        if (Sys.highlightName.charAt(0) === "#") out.push({ id: Sys.highlightName, label: "Custom", swatch: Sys.highlightName })
        return out
    }

    SectionTitle { text: "DESKTOP LAYOUT" }
    RowLayout {
        Layout.fillWidth: true
        spacing: 14
        Repeater {
            model: [
                { id: "macos", name: "macOS", sub: "Menu bar and dock" },
                { id: "windows", name: "Windows 11", sub: "Centered taskbar" },
                { id: "linux", name: "Linux", sub: "Top bar, Tokyo Night" }
            ]
            delegate: Rectangle {
                id: opt
                required property var modelData
                readonly property bool on: Sys.layout === modelData.id
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 250
                radius: 14
                color: Theme.card
                border.width: on ? 2 : 1
                border.color: on ? Theme.accent : Theme.line
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10
                    LayoutPreview {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        kind: opt.modelData.id
                    }
                    ColumnLayout {
                        spacing: 1
                        Text { Layout.fillWidth: true; text: opt.modelData.name; color: Theme.text; font.family: Theme.sans; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Text { Layout.fillWidth: true; text: opt.modelData.sub; color: Theme.sub; font.family: Theme.sans; font.pixelSize: 12 }
                    }
                }
                Rectangle {
                    visible: opt.on
                    width: 22
                    height: 22
                    radius: 11
                    color: Theme.fill
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 18
                    Text { anchors.centerIn: parent; text: "✓"; color: "#ffffff"; font.pixelSize: 13; font.weight: Font.Bold }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Sys.setLayout(opt.modelData.id) }
            }
        }
    }

    SectionTitle { text: "COLOR" }
    Card {
        Cell {
            id: accentCell
            title: "Accent color"
            subtitle: page.accentLabel(Sys.accentName)
            readonly property bool custom: Sys.accentName.charAt(0) === "#"
            ColumnLayout {
                spacing: 9
                Repeater {
                    model: [Sys.accents.slice(0, 8), Sys.accents.slice(8)]
                    delegate: Row {
                        id: swatchRow
                        required property var modelData
                        required property int index
                        Layout.alignment: Qt.AlignRight
                        spacing: 8
                        Repeater {
                            model: swatchRow.modelData
                            delegate: Swatch {
                                required property var modelData
                                color: Theme.light ? modelData.lhex : modelData.hex
                                selected: Sys.accentName === modelData.name
                                tip: modelData.label
                                onClicked: Sys.setAccent(modelData.name)
                            }
                        }
                        Swatch {
                            visible: swatchRow.index === 1
                            rainbow: !accentCell.custom
                            color: accentCell.custom ? Sys.accentName : "transparent"
                            selected: accentCell.custom
                            tip: "Custom color"
                            onClicked: customPicker.openAt(this, accentCell.custom ? Sys.accentName : Theme.accent)
                        }
                    }
                }
            }
        }
        Cell {
            title: "Highlight color"
            subtitle: "List and text selection"
            Pick {
                menuWidth: 220
                current: Sys.highlightName
                options: page.highlightOptions
                onPicked: id => Sys.setHighlight(id)
            }
        }
        Cell {
            title: "Sidebar icon color"
            subtitle: "Icons in Files, Settings and app sidebars"
            Pick {
                menuWidth: 220
                current: Sys.sidebarIcons
                options: [
                    { id: "neutral", label: "Neutral", swatch: Theme.light ? "#404040" : "#ffffff" },
                    { id: "accent", label: "Accent Color", swatch: Theme.accentText }
                ]
                onPicked: id => Sys.setSidebarIcons(id)
            }
        }
        Cell {
            title: "Allow wallpaper tinting in windows"
            subtitle: "Sidebars and window backgrounds take on a blurred tint of the wallpaper"
            last: true
            Toggle {
                checked: Sys.tint
                onToggled: (v) => Sys.setTint(v)
            }
        }
    }

    ColorPicker {
        id: customPicker
        onPicked: hex => Sys.setAccent(hex)
    }

    SectionTitle { text: "WINDOWS" }
    Card {
        Cell {
            title: "Window corner radius"
            subtitle: Sys.radius + " px" + (Sys.radius === Sys.radiusDefault ? " (layout default)" : "")
            last: true
            Row {
                spacing: 14
                Sld {
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 220
                    from: 0
                    to: 24
                    step: 1
                    value: Sys.radius
                    onValueChanged: if (pressed) Sys.radius = value
                    onReleased: (v) => Sys.setRadius(v)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Sys.radius !== Sys.radiusDefault
                    text: "Reset"
                    color: Theme.accentText
                    font.family: Theme.sans
                    font.pixelSize: 13
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Sys.resetRadius() }
                }
            }
        }
    }

    Card {
        Cell {
            title: "Appearance"
            subtitle: "Light or dark for every layout, desktop and app"
            last: true
            Seg {
                options: [{ id: "light", label: "Light" }, { id: "dark", label: "Dark" }]
                current: Theme.light ? "light" : "dark"
                onPicked: id => Sys.setAppearance(id)
            }
        }
    }
}
