import QtQuick
import QtQuick.Shapes

Item {
    id: g
    property string name
    property color color: Look.text
    property real size: 18
    property real stroke: 1.7
    property bool filled: false
    implicitWidth: size
    implicitHeight: size

    readonly property var paths: ({
        discover: "M12 3.2l2.6 5.6 6.1.7-4.5 4.2 1.2 6-5.4-3-5.4 3 1.2-6-4.5-4.2 6.1-.7z",
        home: "M3.5 11.2L12 3.8l8.5 7.4 M6 9.4V20h4.5v-6h3v6H18V9.4",
        create: "M19.8 3.6c-3.1 1.5-7.3 5.8-8.9 8.7l1.7 1.7c2.9-1.6 7.2-5.8 8.7-8.9z M9.9 13.6c-1.9 0-3.4 1.5-3.4 3.3 0 1.3-.8 2.2-2.2 2.5 1.1 1.1 2.6 1.6 4.1 1.6 2.6 0 4.6-2 4.6-4.4z",
        work: "M20.5 3.5L3.5 10.6l6.8 2.6 2.6 6.8z M20.5 3.5l-10.2 9.7",
        play: "M8 8.5h8a4.6 4.6 0 0 1 4.4 5.9l-.9 3.1a2.3 2.3 0 0 1-3.9.9L13.8 16.5h-3.6l-1.8 1.9a2.3 2.3 0 0 1-3.9-.9l-.9-3.1A4.6 4.6 0 0 1 8 8.5z M8.2 11.3v3.2 M6.6 12.9h3.2 M15.6 11.8v.1 M17.4 13.6v.1",
        develop: "M8 7l-5 5 5 5 M16 7l5 5-5 5 M13.6 4.5l-3.2 15",
        categories: "M4.5 4.5h6v6h-6z M13.5 4.5h6v6h-6z M4.5 13.5h6v6h-6z M13.5 13.5h6v6h-6z",
        apps: "M4.5 4.5h6v6h-6z M13.5 4.5h6v6h-6z M4.5 13.5h6v6h-6z M13.5 13.5h6v6h-6z",
        agents: "M11 3.5l1.9 5.4 5.4 1.9-5.4 1.9-1.9 5.4-1.9-5.4-5.4-1.9 5.4-1.9z M18.2 14.6l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z",
        arch: "M12 3.2l8 4.4v8.8L12 20.8l-8-4.4V7.6z M4.3 7.8L12 12l7.7-4.2 M12 12v8.6",
        updates: "M12 3.2a8.8 8.8 0 1 0 0 17.6 8.8 8.8 0 0 0 0-17.6z M12 7.6v8.2 M8.6 12.6l3.4 3.4 3.4-3.4",
        library: "M4.5 4.5h4v15h-4z M10.5 4.5h4v15h-4z M16.2 5.6l3.6-.8 3 14.4-3.6.8z",
        installed: "M4.5 4.5h4v15h-4z M10.5 4.5h4v15h-4z M16.2 5.6l3.6-.8 3 14.4-3.6.8z",
        search: "M10.5 4a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13z M15.4 15.4L20.2 20.2",
        back: "M15 4.5L7.5 12l7.5 7.5",
        forward: "M9 4.5l7.5 7.5L9 19.5",
        down: "M5 9l7 7 7-7",
        download: "M12 4v11 M7.5 10.5L12 15l4.5-4.5 M5 19.5h14",
        shield: "M12 3l7.5 3v5.5c0 4.6-3.2 8.2-7.5 9.5-4.3-1.3-7.5-4.9-7.5-9.5V6z",
        shieldok: "M12 3l7.5 3v5.5c0 4.6-3.2 8.2-7.5 9.5-4.3-1.3-7.5-4.9-7.5-9.5V6z M8.6 12.2l2.4 2.4 4.4-4.6",
        check: "M5 12.5l4.5 4.5L19 7.5",
        warning: "M12 4.2L2.9 19.8h18.2z M12 10v4.6 M12 17.2v.1",
        lock: "M6.5 10.5h11v9.5h-11z M8.6 10.5V8a3.4 3.4 0 0 1 6.8 0v2.5",
        network: "M12 3.2a8.8 8.8 0 1 0 0 17.6 8.8 8.8 0 0 0 0-17.6z M3.2 12h17.6 M12 3.2c2.4 2.5 3.6 5.5 3.6 8.8s-1.2 6.3-3.6 8.8c-2.4-2.5-3.6-5.5-3.6-8.8S9.6 5.7 12 3.2z",
        files: "M3.5 6.2h6l2 2h9v10.6h-17z",
        display: "M3.5 5h17v11.5h-17z M9 20h6 M12 16.5V20",
        devices: "M7.5 7.5h9v9h-9z M10 4v3.5 M14 4v3.5 M10 16.5V20 M14 16.5V20 M4 10h3.5 M4 14h3.5 M16.5 10H20 M16.5 14H20",
        audio: "M12 3.5a2.5 2.5 0 0 1 2.5 2.5v5a2.5 2.5 0 0 1-5 0V6A2.5 2.5 0 0 1 12 3.5z M6.5 11a5.5 5.5 0 0 0 11 0 M12 16.5V20",
        bus: "M4 5h16v14H4z M7.5 9.5l3 2.5-3 2.5 M12.5 15h4",
        escape: "M14 4h6v6 M20 4l-9 9 M18 14v6H4V6h6",
        devel: "M8 7l-5 5 5 5 M16 7l5 5-5 5",
        bluetooth: "M7 7.5l10 8.5-5 4V4l5 4-10 8.5",
        info: "M12 3.2a8.8 8.8 0 1 0 0 17.6 8.8 8.8 0 0 0 0-17.6z M12 10.8v5.4 M12 7.6v.1",
        external: "M14 4h6v6 M20 4l-9 9 M18 14v6H4V6h6",
        refresh: "M19.5 5.5v5h-5 M19.2 10.5A7.6 7.6 0 1 0 17.6 17",
        trash: "M5 7h14 M9.5 7V4.5h5V7 M7 7l1 13h8l1-13",
        media: "M9 18a2.5 2.5 0 1 1-5 0 2.5 2.5 0 0 1 5 0z M9 18V5.8l11-2.3v11.9 M20 15.4a2.5 2.5 0 1 1-5 0 2.5 2.5 0 0 1 5 0z",
        social: "M4 5h16v10.5H9.5L5 19.5v-4H4z",
        education: "M2.5 9.2L12 4.6l9.5 4.6L12 13.8z M6.5 11.2v4.9c3 2.4 8 2.4 11 0v-4.9 M21.5 9.2v5",
        utilities: "M14.6 3.8a5 5 0 0 0-4.8 6.5L3.9 16.2l3.9 3.9 5.9-5.9a5 5 0 0 0 6.5-4.8l-3 3-3.6-1-1-3.6 3-3c-.3 0-.6-.1-1-.1z",
        close: "M6 6l12 12 M18 6L6 18",
        more: "M5.5 12h.1 M12 12h.1 M18.5 12h.1",
        code: "M8 7l-5 5 5 5 M16 7l5 5-5 5",
        star: "M12 3.2l2.6 5.6 6.1.7-4.5 4.2 1.2 6-5.4-3-5.4 3 1.2-6-4.5-4.2 6.1-.7z",
        person: "M12 4a3.8 3.8 0 1 0 0 7.6A3.8 3.8 0 0 0 12 4z M4.5 20c.8-3.6 3.8-6 7.5-6s6.7 2.4 7.5 6",
        size: "M5 4.5h14v15H5z M8.5 9h7 M8.5 12.5h7 M8.5 16h4",
        tag: "M3.5 12.2V4h8.2l8.8 8.8-8.2 8.2z M8 8.2h.1",
        globe: "M12 3.2a8.8 8.8 0 1 0 0 17.6 8.8 8.8 0 0 0 0-17.6z M3.2 12h17.6 M12 3.2c2.4 2.5 3.6 5.5 3.6 8.8s-1.2 6.3-3.6 8.8c-2.4-2.5-3.6-5.5-3.6-8.8S9.6 5.7 12 3.2z",
        cpu: "M7.5 7.5h9v9h-9z M10 4v3.5 M14 4v3.5 M10 16.5V20 M14 16.5V20 M4 10h3.5 M4 14h3.5 M16.5 10H20 M16.5 14H20",
        verified: "M12 2.8l2.3 1.7 2.8-.1.9 2.7 2.3 1.6-.8 2.7.8 2.7-2.3 1.6-.9 2.7-2.8-.1L12 20.8l-2.3-1.7-2.8.1-.9-2.7-2.3-1.6.8-2.7-.8-2.7 2.3-1.6.9-2.7 2.8.1z M8.6 11.9l2.3 2.3 4.4-4.5"
    })

    Shape {
        anchors.centerIn: parent
        width: 24
        height: 24
        scale: g.size / 24
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: g.color
            strokeWidth: g.stroke * 24 / g.size
            fillColor: g.filled ? g.color : "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: g.paths[g.name] || "" }
        }
    }
}
