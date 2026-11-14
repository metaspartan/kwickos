import QtQuick

Canvas {
    id: c
    property color color: Theme.sub
    property real stroke: 1.8
    property string shape: "right"
    implicitWidth: 10
    implicitHeight: 10
    onColorChanged: requestPaint()
    onShapeChanged: requestPaint()
    onPaint: {
        var g = getContext("2d")
        g.reset()
        g.strokeStyle = c.color
        g.fillStyle = c.color
        g.lineWidth = c.stroke
        g.lineCap = "round"
        g.lineJoin = "round"
        var w = width, h = height, p = stroke
        g.beginPath()
        if (shape === "right") { g.moveTo(w * 0.32, p); g.lineTo(w * 0.72, h / 2); g.lineTo(w * 0.32, h - p) }
        else if (shape === "down") { g.moveTo(p, h * 0.32); g.lineTo(w / 2, h * 0.72); g.lineTo(w - p, h * 0.32) }
        else if (shape === "updown") { g.moveTo(w * 0.22, h * 0.38); g.lineTo(w / 2, h * 0.14); g.lineTo(w * 0.78, h * 0.38); g.moveTo(w * 0.22, h * 0.62); g.lineTo(w / 2, h * 0.86); g.lineTo(w * 0.78, h * 0.62) }
        else if (shape === "check") { g.moveTo(w * 0.12, h * 0.52); g.lineTo(w * 0.4, h * 0.8); g.lineTo(w * 0.9, h * 0.2) }
        else if (shape === "left") { g.moveTo(w * 0.68, p); g.lineTo(w * 0.28, h / 2); g.lineTo(w * 0.68, h - p) }
        g.stroke()
    }
}
