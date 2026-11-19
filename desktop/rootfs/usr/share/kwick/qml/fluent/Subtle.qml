import QtQuick

Rectangle {
    property bool hovered: false
    property bool pressed: false
    property bool active: false

    radius: Fluent.radius
    color: pressed ? Fluent.subtlePressed : (hovered || active) ? Fluent.subtleHover : "transparent"
}
