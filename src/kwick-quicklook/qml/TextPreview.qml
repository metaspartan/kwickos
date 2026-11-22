import QtQuick
import QtQuick.Controls.Basic
import QtQml.Models
import org.kde.syntaxhighlighting

Item {
    id: view
    required property var theme
    required property bool markdown

    Rectangle {
        anchors.fill: parent
        color: view.theme.card
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: edit.implicitHeight + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        TextEdit {
            id: edit
            x: view.markdown ? Math.max(28, (flick.width - 760) / 2) : 20
            y: 18
            width: view.markdown ? Math.min(760, flick.width - 56) : flick.width - 40
            readOnly: true
            selectByMouse: true
            persistentSelection: true
            wrapMode: TextEdit.Wrap
            textFormat: view.markdown ? TextEdit.RichText : TextEdit.PlainText
            text: ql.text + (ql.truncated ? "\n\n…" : "")
            color: view.theme.label
            selectionColor: Qt.rgba(view.theme.accent.r, view.theme.accent.g, view.theme.accent.b, 0.35)
            selectedTextColor: view.theme.label
            font.family: view.markdown ? view.theme.sans : view.theme.mono
            font.pixelSize: view.markdown ? 15 : 13
            tabStopDistance: 4 * fm.advanceWidth(" ")
            onLinkActivated: link => Qt.openUrlExternally(link)
            onTextChanged: flick.contentY = 0

            FontMetrics {
                id: fm
                font: edit.font
            }
        }
    }

    Instantiator {
        active: !view.markdown
        model: 1
        delegate: SyntaxHighlighter {
            textEdit: edit
            definition: Repository.definitionForFileName(ql.name).name
            theme: Repository.defaultTheme(view.theme.dark ? Repository.DarkTheme : Repository.LightTheme)
        }
    }

    Text {
        anchors.centerIn: parent
        visible: ql.text === ""
        text: "Empty document"
        color: view.theme.secondary
        font.family: view.theme.sans
        font.pixelSize: 14
    }
}
