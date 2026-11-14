#!/usr/bin/env python3
"""Generate the KwickOS icon themes (SVG only): KwickOS (macOS), KwickOS-Linux and KwickOS-Fluent (Windows).
usage: gen-icons.py <repo-root> [macos|linux|windows ...]
Every icon shares one geometry: a 24-unit glyph grid, a continuous-corner squircle for apps and
settings pages, a folder body for places and bare strokes for actions.
"""
import math, os, re, shutil, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import icondesign as ID
import placeicons as PI
import freeicons as FI

ROOT = sys.argv[1]
SQ = None


def squircle(cx=64, cy=64, r=59.5, n=5.0, steps=160, prec=2):
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = cx + r * math.copysign(abs(c) ** (2 / n), c)
        y = cy + r * math.copysign(abs(s) ** (2 / n), s)
        pts.append(f"{x:.{prec}f},{y:.{prec}f}")
    return "M" + " L".join(pts) + "Z"


SQ = squircle()
SQ_IN = squircle(r=59.0)


def gear(cx=12, cy=12, ro=9.6, ri=7.4, n=8):
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        for da, r in ((-0.33, ri), (-0.2, ro), (0.2, ro), (0.33, ri)):
            pts.append((cx + r * math.cos(a + da), cy + r * math.sin(a + da)))
    return "M" + " L".join(f"{x:.2f},{y:.2f}" for x, y in pts) + "Z"


def P(d, extra=""):
    return f'<path d="{d}" {extra}/>'


def C(cx, cy, r, extra=""):
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" {extra}/>'


def R(x, y, w, h, rx, extra=""):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" {extra}/>'


def dot(cx, cy, r=1.15):
    return C(cx, cy, r, 'fill="@" stroke="none"')


def fill(d):
    return P(d, 'fill="@" stroke="none"')


def soft(d):
    return P(d, 'fill="@" fill-opacity="0.28"')


G = {}
G["gear"] = P(gear()) + C(12, 12, 3.1)
G["wifi"] = P("M2.8 9.2a13.2 13.2 0 0 1 18.4 0") + P("M6 12.6a8.6 8.6 0 0 1 12 0") + P("M9.2 15.9a4.1 4.1 0 0 1 5.6 0") + dot(12, 19.2, 1.4)
G["ethernet"] = R(8.5, 3, 7, 5.5, 1.4) + P("M12 8.5V13") + P("M5.5 17v-4h13v4") + R(2.8, 17, 5.4, 4, 1.2) + R(15.8, 17, 5.4, 4, 1.2)
G["bluetooth"] = P("M6.5 7.5l11 9-5.5 4.5V3l5.5 4.5-11 9")
G["mouse"] = R(6, 2.5, 12, 19, 6) + P("M12 2.8v7") + P("M6.2 10h11.6")
G["touchpad"] = R(3, 4.5, 18, 15, 3.2) + P("M3.4 15h17.2") + P("M12 15v4.2")
G["keyboard"] = R(2.5, 5.5, 19, 13, 3) + dot(6.5, 9.8) + dot(10.2, 9.8) + dot(13.8, 9.8) + dot(17.5, 9.8) + P("M7 14.6h10")
G["speaker"] = P("M3.8 9.5h3.6L12 5.5v13l-4.6-4H3.8z", 'stroke-linejoin="round"') + P("M15.6 9.2a4.2 4.2 0 0 1 0 5.6") + P("M18.3 6.6a8 8 0 0 1 0 10.8")
G["display"] = R(2.8, 4, 18.4, 12.5, 2.6) + P("M8.5 20.2h7") + P("M12 16.5v3.7")
G["image"] = R(3, 4.5, 18, 15, 3.2) + C(8.6, 10, 1.7) + P("M3.6 17l5-4.8 4 3.8 3-2.8 4.8 4.4")
G["palette"] = P("M12 3a9 9 0 1 0 0 18c1.3 0 2-.9 2-1.9 0-.6-.3-1-.6-1.4-.3-.4-.5-.8-.5-1.3 0-1.1.9-1.9 2-1.9h2A4.1 4.1 0 0 0 21 8.4C21 5.4 17 3 12 3z") + dot(7.6, 11.2) + dot(9.6, 7.2) + dot(14.4, 7) + dot(17, 10.4)
G["font"] = P("M3.6 19L9.4 5h1.2l5.8 14") + P("M5.8 14.4h8.2") + P("M17.8 19.2v-6.4") + P("M17.8 14.4c0-1 1-1.8 2.2-1.8")
G["apps"] = R(3.5, 3.5, 7, 7, 2.2) + R(13.5, 3.5, 7, 7, 2.2) + R(3.5, 13.5, 7, 7, 2.2) + R(13.5, 13.5, 7, 7, 2.2, 'fill="@" fill-opacity="0.4"')
G["access"] = C(12, 4.6, 1.9) + P("M4.2 8.6L12 10l7.8-1.4") + P("M12 10v4.4") + P("M12 14.4L8.6 20.2") + P("M12 14.4l3.4 5.8")
G["user"] = C(12, 8, 4) + P("M4.6 20.2c0-4 3.3-6.6 7.4-6.6s7.4 2.6 7.4 6.6")
G["users"] = C(9, 8.4, 3.5) + P("M2.8 19.6c0-3.6 2.8-5.8 6.2-5.8s6.2 2.2 6.2 5.8") + P("M15.4 4.9a3.5 3.5 0 0 1 0 6.8") + P("M18 14.2c2 .7 3.3 2.7 3.3 5.4")
G["clock"] = C(12, 12, 9) + P("M12 6.6V12l3.6 2.2")
G["globe"] = C(12, 12, 9) + P("M3 12h18") + P("M12 3c3.2 3 3.2 15 0 18") + P("M12 3c-3.2 3-3.2 15 0 18")
G["lock"] = R(4.8, 10.4, 14.4, 10.2, 2.8) + P("M8 10.4V8a4 4 0 0 1 8 0v2.4") + dot(12, 15.5, 1.4)
G["shield"] = P("M12 2.8l7.4 3v5.6c0 4.6-3.1 8-7.4 9.8-4.3-1.8-7.4-5.2-7.4-9.8V5.8z") + P("M8.6 12l2.5 2.5 4.4-4.8")
G["bell"] = P("M5.8 16.6V11a6.2 6.2 0 0 1 12.4 0v5.6l1.6 2.2H4.2z") + P("M9.8 21.2h4.4")
G["bolt"] = P("M13.4 2.6L5.2 13.6h6l-1 7.8 8.6-11.4h-6.2z")
G["battery"] = R(2.4, 7.4, 17, 9.4, 2.4) + P("M21.8 10.6v3") + R(5, 10, 8.4, 4.2, 1, 'fill="@" fill-opacity="0.9" stroke="none"')
G["windows"] = R(3, 4.5, 18, 15, 3.2) + P("M3.2 9.2h17.6") + dot(6.4, 6.9, 0.8) + dot(9, 6.9, 0.8)
G["sparkle"] = P("M11 3c.9 5.2 2.4 6.7 7.6 7.6-5.2.9-6.7 2.4-7.6 7.6-.9-5.2-2.4-6.7-7.6-7.6C8.6 9.7 10.1 8.2 11 3z") + P("M18.6 14.4c.3 1.8.9 2.4 2.7 2.7-1.8.3-2.4.9-2.7 2.7-.3-1.8-.9-2.4-2.7-2.7 1.8-.3 2.4-.9 2.7-2.7z")
G["desktops"] = R(3.4, 4, 7.4, 6.4, 1.8) + R(13.2, 4, 7.4, 6.4, 1.8, 'fill="@" fill-opacity="0.4"') + R(3.4, 13.6, 7.4, 6.4, 1.8) + R(13.2, 13.6, 7.4, 6.4, 1.8)
G["activities"] = C(8.8, 12, 5.6) + C(15.2, 12, 5.6)
G["tabbox"] = R(7, 3.6, 14, 10.4, 2.2) + R(3, 9.6, 14, 10.8, 2.2, 'fill="@" fill-opacity="0.25"')
G["moon"] = P("M20 14.6A8.6 8.6 0 1 1 9.4 4a7 7 0 0 0 10.6 10.6z")
G["cursor"] = P("M5.5 3.2l13.2 6.6-5.4 1.9-1.9 5.5z")
G["loader"] = P("M12 3a9 9 0 1 1-9 9") + dot(12, 12, 2)
G["play"] = P("M8 5.4v13.2l10.8-6.6z", 'fill="@" stroke-linejoin="round"')
G["autostart"] = C(12, 12, 9) + P("M10 8.4l5.4 3.6-5.4 3.6z", 'fill="@"')
G["logout"] = P("M10 4H6.2A2.2 2.2 0 0 0 4 6.2v11.6A2.2 2.2 0 0 0 6.2 20H10") + P("M15 7.4l4.6 4.6-4.6 4.6") + P("M19.6 12H9")
G["search"] = C(10.4, 10.4, 6.4) + P("M15.2 15.2l5.2 5.2")
G["printer"] = P("M7 8.6V3.6h10v5") + R(3.2, 8.6, 17.6, 8, 2.4) + R(7, 13.6, 10, 6.8, 1.2)
G["phone"] = R(6.8, 2.6, 10.4, 18.8, 2.8) + P("M10.4 18.2h3.2")
G["info"] = C(12, 12, 9) + P("M12 11v5.6") + dot(12, 7.7, 1.2)
G["harddisk"] = R(2.8, 7.4, 18.4, 9.6, 3) + P("M6.6 12.2h6") + dot(17.4, 12.2, 1.2)
G["usb"] = R(6.6, 9.8, 10.8, 11.4, 2.4) + R(9, 2.8, 6, 7, 1.2) + dot(10.9, 6.2, 0.8) + dot(13.1, 6.2, 0.8)
G["update"] = C(12, 12, 9) + P("M12 7.4V15.6") + P("M8.4 12.2l3.6 3.6 3.6-3.6")
G["bag"] = P("M5.2 8h13.6l-1.2 12.2H6.4z") + P("M9 8V6.6a3 3 0 0 1 6 0V8")
G["terminal"] = P("M5.5 7.6l4.6 4.4-4.6 4.4") + P("M12.4 16.6h6.2")
G["folder"] = P("M3 7.6a2.4 2.4 0 0 1 2.4-2.4h3.9l2.1 2.4h7.2A2.4 2.4 0 0 1 21 10v7.4a2.4 2.4 0 0 1-2.4 2.4H5.4A2.4 2.4 0 0 1 3 17.4z")
G["page"] = P("M6.6 2.8h7.2l4.6 4.6v11.8a2 2 0 0 1-2 2H6.6a2 2 0 0 1-2-2V4.8a2 2 0 0 1 2-2z") + P("M13.6 3v4.6h4.6")
G["text"] = G["page"] + P("M8.2 12.4h7.4") + P("M8.2 16h7.4")
G["pencilpage"] = P("M13 3H6.6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10.8a2 2 0 0 0 2-2v-6.6") + P("M10.4 14l.6-3.2 8-8a1.6 1.6 0 0 1 2.3 2.3l-8 8z")
G["book"] = P("M4.4 4.6A2 2 0 0 1 6.4 3H19v15H6.4a2 2 0 0 0-2 2z") + P("M4.4 20a2 2 0 0 0 2 1.6H19V18") + P("M9 7.6h6")
G["archive"] = R(3, 4, 18, 5, 1.6) + P("M5 9v9.2A1.8 1.8 0 0 0 6.8 20h10.4a1.8 1.8 0 0 0 1.8-1.8V9") + P("M10 13h4")
G["screenshot"] = P("M3.4 8.4V6A2.6 2.6 0 0 1 6 3.4h2.4") + P("M15.6 3.4H18A2.6 2.6 0 0 1 20.6 6v2.4") + P("M20.6 15.6V18a2.6 2.6 0 0 1-2.6 2.6h-2.4") + P("M8.4 20.6H6A2.6 2.6 0 0 1 3.4 18v-2.4") + C(12, 12, 3.2)
G["calc"] = R(4.8, 2.6, 14.4, 18.8, 2.8) + R(7.8, 5.6, 8.4, 3.8, 1) + dot(9, 13, 1) + dot(12, 13, 1) + dot(15, 13, 1) + dot(9, 16.4, 1) + dot(12, 16.4, 1) + dot(15, 16.4, 1)
G["pulse"] = P("M2.6 12.4h4.2l2.6-6.4 4.4 12 2.6-5.6h5")
G["gamepad"] = P("M7.8 7.2h8.4a5 5 0 0 1 5 5l.4 3.8a2.5 2.5 0 0 1-4.2 2L15.6 16H8.4l-2.2 2a2.5 2.5 0 0 1-4.2-2l.4-3.8a5 5 0 0 1 5-5z") + P("M8 10v3.4") + P("M6.3 11.7h3.4") + dot(15.6, 10.8, 0.95) + dot(17.8, 12.8, 0.95)
G["chip"] = R(6, 6, 12, 12, 2.4) + R(9.6, 9.6, 4.8, 4.8, 1) + P("M9 3v3M15 3v3M9 18v3M15 18v3M3 9h3M3 15h3M18 9h3M18 15h3")
G["layout"] = R(3, 4, 18, 16, 3.2) + P("M10 4.2v15.6") + P("M10 11.4h10.8")
G["dock"] = R(5, 3.8, 14, 9, 2.2) + R(2.6, 15.4, 18.8, 5, 2.5) + dot(7.4, 17.9, 0.9) + dot(12, 17.9, 0.9) + dot(16.6, 17.9, 0.9)
G["desktop"] = R(2.8, 4, 18.4, 12.5, 2.6) + P("M8 20.2h8")
G["music"] = P("M9 18.2V6l10.4-2.2v12.2") + C(6.6, 18.2, 2.5) + C(17, 16, 2.5)
G["video"] = R(3, 5.6, 18, 12.8, 3) + P("M10.4 9.4v5.2l4.4-2.6z", 'fill="@" stroke-linejoin="round"')
G["mail"] = R(3, 5.4, 18, 13.2, 3) + P("M3.6 7.6l8.4 5.8 8.4-5.8")
G["camera"] = P("M4.8 7.4h2.6l1.4-2.2h6.4l1.4 2.2h2.6a1.8 1.8 0 0 1 1.8 1.8v8a1.8 1.8 0 0 1-1.8 1.8H4.8A1.8 1.8 0 0 1 3 17.2v-8a1.8 1.8 0 0 1 1.8-1.8z") + C(12, 12.6, 3.4)
G["home"] = P("M3.4 11.2L12 3.6l8.6 7.6") + P("M5.6 9.6v9.6a1.6 1.6 0 0 0 1.6 1.6h9.6a1.6 1.6 0 0 0 1.6-1.6V9.6") + P("M10 20.8v-5.2h4v5.2")
G["trash"] = P("M3.8 6.8h16.4") + P("M9 6.8V4.2h6v2.6") + P("M5.8 6.8l1 13.2h10.4l1-13.2") + P("M10 10.6v6.2M14 10.6v6.2")
G["download"] = P("M12 3.8v11.2") + P("M7.4 10.6l4.6 4.6 4.6-4.6") + P("M4.6 20.2h14.8")
G["upload"] = P("M12 15.4V4.2") + P("M7.4 8.8L12 4.2l4.6 4.6") + P("M4.6 20.2h14.8")
G["plus"] = P("M12 4.8v14.4M4.8 12h14.4")
G["minus"] = P("M4.8 12h14.4")
G["close"] = P("M6 6l12 12M18 6L6 18")
G["check"] = P("M4.8 12.6l4.8 4.8 9.6-10")
G["left"] = P("M14.6 5.4L8 12l6.6 6.6")
G["right"] = P("M9.4 5.4L16 12l-6.6 6.6")
G["up"] = P("M5.4 14.6L12 8l6.6 6.6")
G["down"] = P("M5.4 9.4L12 16l6.6-6.6")
G["arrowl"] = P("M19.6 12H5M10.8 6.2L5 12l5.8 5.8")
G["arrowr"] = P("M4.4 12H19M13.2 6.2L19 12l-5.8 5.8")
G["arrowu"] = P("M12 19.6V5M6.2 10.8L12 5l5.8 5.8")
G["arrowd"] = P("M12 4.4V19M6.2 13.2L12 19l5.8-5.8")
G["refresh"] = P("M19.6 12a7.6 7.6 0 1 1-2.4-5.5") + P("M19.8 4.4v4.4h-4.4")
G["undo"] = P("M8.4 5.4L4.2 9.6l4.2 4.2") + P("M4.6 9.6h9.8a5.2 5.2 0 0 1 0 10.4H9")
G["redo"] = P("M15.6 5.4l4.2 4.2-4.2 4.2") + P("M19.4 9.6H9.6a5.2 5.2 0 0 0 0 10.4H15")
G["copy"] = R(8.6, 8.6, 11.6, 11.6, 2.6) + P("M15.4 8.6V6.4a2.6 2.6 0 0 0-2.6-2.6H6.4a2.6 2.6 0 0 0-2.6 2.6v6.4a2.6 2.6 0 0 0 2.6 2.6h2.2")
G["cut"] = C(6.6, 17.4, 2.8) + C(17.4, 17.4, 2.8) + P("M8.4 15.2L18.2 3.6M15.6 15.2L5.8 3.6")
G["paste"] = R(5, 4.6, 14, 16, 2.6) + R(8.8, 2.8, 6.4, 3.6, 1.4) + P("M8.6 11.4h6.8M8.6 15h4.4")
G["save"] = P("M5.6 3.6h10.6l3.6 3.6v11.2a2 2 0 0 1-2 2H5.6a2 2 0 0 1-2-2V5.6a2 2 0 0 1 2-2z") + R(7.2, 3.8, 7, 4.8, 1) + R(7.2, 13.2, 9.6, 7, 1.2)
G["open"] = P("M3.4 18.4V6.2a2 2 0 0 1 2-2h4l2 2.2h6a2 2 0 0 1 2 2v1.6") + P("M3.6 18.8l2.4-7.2a1.6 1.6 0 0 1 1.5-1.1H21l-2.4 7.2a1.6 1.6 0 0 1-1.5 1.1H3.6z")
G["newpage"] = G["page"] + P("M12 11v6M9 14h6")
G["newfolder"] = G["folder"] + P("M12 10.8v5.2M9.4 13.4h5.2")
G["star"] = P("M12 3.4l2.6 5.4 5.9.8-4.3 4.1 1 5.9-5.2-2.8-5.2 2.8 1-5.9-4.3-4.1 5.9-.8z")
G["heart"] = P("M12 20.2S3.4 15 3.4 8.9A4.6 4.6 0 0 1 12 6.6a4.6 4.6 0 0 1 8.6 2.3C20.6 15 12 20.2 12 20.2z")
G["menu"] = P("M4.4 7h15.2M4.4 12h15.2M4.4 17h15.2")
G["dots"] = dot(5.4, 12, 1.6) + dot(12, 12, 1.6) + dot(18.6, 12, 1.6)
G["listview"] = P("M8.4 7h11.2M8.4 12h11.2M8.4 17h11.2") + dot(4.6, 7, 1) + dot(4.6, 12, 1) + dot(4.6, 17, 1)
G["iconview"] = R(4, 4, 6.6, 6.6, 1.8) + R(13.4, 4, 6.6, 6.6, 1.8) + R(4, 13.4, 6.6, 6.6, 1.8) + R(13.4, 13.4, 6.6, 6.6, 1.8)
G["filter"] = P("M3.8 5.6h16.4l-6.2 7.4v6l-4-2v-4z")
G["sort"] = P("M7.4 19.6V4.6M3.6 8.4l3.8-3.8 3.8 3.8") + P("M16.6 4.4v15M12.8 15.6l3.8 3.8 3.8-3.8")
G["zoomin"] = C(10.4, 10.4, 6.4) + P("M15.2 15.2l5.2 5.2M10.4 7.6v5.6M7.6 10.4h5.6")
G["zoomout"] = C(10.4, 10.4, 6.4) + P("M15.2 15.2l5.2 5.2M7.6 10.4h5.6")
G["external"] = P("M13.4 4h6.6v6.6") + P("M20 4l-9 9") + P("M18 14v3.4a2.6 2.6 0 0 1-2.6 2.6H6.6A2.6 2.6 0 0 1 4 17.4V8.6A2.6 2.6 0 0 1 6.6 6H10")
G["edit"] = P("M4.4 19.6l.8-4.2L16.4 4.2a2 2 0 0 1 2.8 0l.6.6a2 2 0 0 1 0 2.8L8.6 18.8z") + P("M14.6 6l3.4 3.4")
G["warning"] = P("M12 3.6l9.2 16H2.8z") + P("M12 10v4.6") + dot(12, 17.4, 1)
G["error"] = C(12, 12, 9) + P("M12 7.4v5.6") + dot(12, 16.6, 1.1)
G["question"] = C(12, 12, 9) + P("M9.4 9.6a2.7 2.7 0 1 1 3.9 2.4c-.9.5-1.3 1-1.3 2") + dot(12, 17, 1.1)
G["power"] = P("M12 3.4v8") + P("M6.8 6.6a8.2 8.2 0 1 0 10.4 0")
G["restart"] = P("M19.4 12a7.4 7.4 0 1 1-2.2-5.2") + P("M19.6 3.8v4.6h-4.6") + P("M12 8.6V12")
G["suspend"] = G["moon"]
G["volumeoff"] = P("M3.8 9.5h3.6L12 5.5v13l-4.6-4H3.8z") + P("M16 9.4l5 5.2M21 9.4l-5 5.2")
G["mic"] = R(8.6, 2.8, 6.8, 11.6, 3.4) + P("M5.6 11.6a6.4 6.4 0 0 0 12.8 0M12 18v3.2")
G["pause"] = P("M8 5.6v12.8M16 5.6v12.8")
G["stop"] = R(6, 6, 12, 12, 2.4, 'fill="@"')
G["next"] = P("M6 5.6v12.8l9-6.4z", 'fill="@" stroke-linejoin="round"') + P("M18.4 5.6v12.8")
G["prev"] = P("M18 5.6v12.8l-9-6.4z", 'fill="@" stroke-linejoin="round"') + P("M5.6 5.6v12.8")
G["record"] = C(12, 12, 6.4, 'fill="@"')
G["eject"] = P("M12 5l7 9H5z", 'fill="@" stroke-linejoin="round"') + P("M5.4 18.6h13.2")
G["share"] = C(18, 5.6, 2.6) + C(6, 12, 2.6) + C(18, 18.4, 2.6) + P("M8.3 10.7l7.4-4M8.3 13.3l7.4 4")
G["link"] = P("M10 14a4.4 4.4 0 0 0 6.2 0l3-3a4.4 4.4 0 0 0-6.2-6.2l-1 1") + P("M14 10a4.4 4.4 0 0 0-6.2 0l-3 3a4.4 4.4 0 0 0 6.2 6.2l1-1")
G["tag"] = P("M3.6 12.4V5.8a2 2 0 0 1 2-2h6.6l8.2 8.2a2 2 0 0 1 0 2.8l-6.6 6.6a2 2 0 0 1-2.8 0z") + dot(8.2, 8.4, 1.2)
G["bookmark"] = P("M6.6 3.8h10.8v16.6L12 16.4l-5.4 4z")
G["calendar"] = R(3.4, 5, 17.2, 15.4, 3) + P("M3.6 10h16.8M8 3v4M16 3v4")
G["cloud"] = P("M7 18.8a4.4 4.4 0 0 1-.6-8.8 6 6 0 0 1 11.6 1.4 3.7 3.7 0 0 1-.4 7.4z")
G["key"] = C(8, 15.4, 4.4) + P("M11.2 12.2L20.4 3M16.6 6.8l2.6 2.6")
G["vpn"] = G["shield"]
G["peripheral"] = R(4, 3.6, 16, 11.4, 2.6) + P("M9 19h6M12 15v4")
G["wrench"] = P("M14.6 3.4a5 5 0 0 0-4.8 6.6L3.6 16.2a2.2 2.2 0 0 0 3.2 3.2L13 13.2a5 5 0 0 0 6.6-4.8l-3 3-2.6-.6-.6-2.6z")
G["accounts"] = C(12, 8.6, 3.8) + P("M5 20c.4-3.6 3.2-5.6 7-5.6s6.6 2 7 5.6") + P("M17.4 4.2l1.1 1.1 2.3-2.5")
G["tablet"] = R(4, 3, 16, 18, 2.8) + P("M10.8 18.2h2.4")
G["touch"] = P("M9.6 20.4l-4.4-6.6a1.5 1.5 0 0 1 2.4-1.8l1.8 2V6.4a1.6 1.6 0 0 1 3.2 0V11l5 1.4a2.4 2.4 0 0 1 1.8 2.4v1.8a3.8 3.8 0 0 1-3.8 3.8z")
G["nightlight"] = P("M12 3v2.2M12 18.8V21M3 12h2.2M18.8 12H21M5.6 5.6l1.6 1.6M16.8 16.8l1.6 1.6M18.4 5.6l-1.6 1.6M7.2 16.8l-1.6 1.6") + C(12, 12, 3.8)
G["sound"] = P("M12 5.4v13.2") + P("M8 8.4v7.2M4.4 10.4v3.2M16 8.4v7.2M19.6 10.4v3.2")
G["file"] = G["page"]
G["bug"] = R(8, 8.4, 8, 11.4, 4) + P("M8.6 4.6l1.6 2M15.4 4.6l-1.6 2M4.2 10.6l3.8 1.4M19.8 10.6L16 12M4.2 18l3.8-1.8M19.8 18L16 16.2M12 9v10.6")
G["spell"] = P("M3.6 17l4.6-12 4.6 12M5.2 12.8h6") + P("M14.6 14.6l2.6 2.6 4.4-5")
G["krunner"] = C(12, 12, 9) + P("M8 10.6l2.6 2.6-2.6 2.6M12.8 16h3.4")
G["notes"] = R(4.4, 3.6, 15.2, 16.8, 2.8) + P("M8.2 9h7.6M8.2 13h7.6M8.2 17h4.2")
G["linux"] = P("M12 3.2c-2.6 0-3.6 2.4-3.6 5 0 1.6-.4 2.4-1.2 3.6-1 1.5-2 3-2 4.8 0 1.8 1.4 2.6 2.4 3l1.4.6c1 .4 2.2.4 3 .4s2 0 3-.4l1.4-.6c1-.4 2.4-1.2 2.4-3 0-1.8-1-3.3-2-4.8-.8-1.2-1.2-2-1.2-3.6 0-2.6-1-5-3.6-5z") + dot(10.4, 8.4, 0.8) + dot(13.6, 8.4, 0.8)
G["wallet"] = P("M4.4 7.2a2.6 2.6 0 0 1 2.6-2.6h10.6v3.2") + R(3.4, 7.2, 17.2, 12.6, 2.8) + P("M20.6 12.4h-4a1.8 1.8 0 0 0 0 3.6h4")
G["emoji"] = C(12, 12, 9) + P("M8.4 14.2a4.2 4.2 0 0 0 7.2 0") + dot(9, 9.8, 1) + dot(15, 9.8, 1)
G["clipboard"] = G["paste"]
G["font2"] = G["font"]
G["recent"] = C(12, 12, 9) + P("M12 7v5l3 2.4")
G["tools"] = G["wrench"]
G["pkg"] = P("M12 3l8.4 4.2v9.6L12 21l-8.4-4.2V7.2z") + P("M3.8 7.4L12 11.6l8.2-4.2M12 11.6V20.6")
G["pencil"] = G["edit"]
G["monitor2"] = R(3.4, 3.4, 11, 8, 2) + R(9.6, 12.6, 11, 8, 2)
G["drive"] = G["harddisk"]
G["trashfull"] = G["trash"] + P("M8.4 4.4l1-1.8h5.2l1 1.8")
FOLDER_TALL = "M3 6.2a2.4 2.4 0 0 1 2.4-2.4h3.9l2.1 2.4h7.2A2.4 2.4 0 0 1 21 8.6v9a2.4 2.4 0 0 1-2.4 2.4H5.4A2.4 2.4 0 0 1 3 17.6z"
G["folderfill"] = P(FOLDER_TALL, 'fill="@" fill-opacity="0.95" stroke-width="1.2"') + P("M3.4 10.2h17.2", 'stroke="#2c8cf0" stroke-opacity="0.45" stroke-width="1.2"')
G["start"] = P("M12 2.8l8.2 4.7v9L12 21.2l-8.2-4.7v-9z") + fill("M13.4 7.2l-4.2 6h3l-.8 4.2 4.2-6h-3z")
G["history"] = P("M4 12a8 8 0 1 0 2.5-5.8") + P("M4.2 3.6v4.2h4.2M12 8v4.4l3 1.8")
G["lockscreen"] = R(4.8, 10.4, 14.4, 10.2, 2.8) + P("M8 10.4V8a4 4 0 0 1 8 0v2.4")
G["gift"] = R(3.6, 8.6, 16.8, 4.2, 1.4) + P("M5 12.8v6.2a1.6 1.6 0 0 0 1.6 1.6h10.8a1.6 1.6 0 0 0 1.6-1.6v-6.2M12 8.6v12M12 8.6C9.8 8.6 8 7.6 8 6a2 2 0 0 1 2-2c1.2 0 2 1.8 2 4.6zM12 8.6c2.2 0 4-1 4-2.6a2 2 0 0 0-2-2c-1.2 0-2 1.8-2 4.6z")

DEEP = {
    "graphite": ("#5a5a60", "#2a2a2e"),
    "gray": ("#6a6a70", "#34343a"),
    "slate": ("#4a4a52", "#232328"),
    "night": ("#3a3a40", "#1c1c1e"),
    "blue": ("#2f7be8", "#0e47a3"),
    "sky": ("#3f8fe6", "#1450a8"),
    "indigo": ("#5b4fc9", "#33288f"),
    "violet": ("#8a4cc2", "#592a86"),
    "teal": ("#1f8f8a", "#0b5c5a"),
    "green": ("#2f9a58", "#1d6a3a"),
    "lime": ("#3f9a45", "#24692a"),
    "red": ("#cc2b43", "#9c1428"),
    "pink": ("#c23468", "#8e1d4a"),
    "orange": ("#e0701f", "#b8400b"),
    "yellow": ("#dc9a22", "#a8640a"),
}

TOKYO_DEEP = {
    "graphite": ("#5d6180", "#2a2d42"),
    "gray": ("#6a6f90", "#343850"),
    "slate": ("#4c5070", "#24263a"),
    "night": ("#3c4060", "#1a1b2a"),
    "blue": ("#6b8ff0", "#34509e"),
    "sky": ("#58a6e0", "#25689a"),
    "indigo": ("#8084ec", "#4048a8"),
    "violet": ("#a47ae6", "#68449e"),
    "teal": ("#45b4a0", "#1e7266"),
    "green": ("#7eb85a", "#427a2a"),
    "lime": ("#8cbc5c", "#4c7a2e"),
    "red": ("#e0647c", "#a03450"),
    "pink": ("#d878b0", "#8e3c72"),
    "orange": ("#ee8a56", "#b8582a"),
    "yellow": ("#d8a458", "#9c6a22"),
}

PAL = {
    "gray": ("#9a9ca6", "#5a5c66"),
    "graphite": ("#6b6f7d", "#363944"),
    "blue": ("#56b0ff", "#1d63ec"),
    "sky": ("#6ad2ff", "#2c8cf0"),
    "teal": ("#33ecd8", "#0ba7b8"),
    "violet": ("#b07bff", "#6c36d8"),
    "green": ("#62e486", "#1ca84c"),
    "lime": ("#b5ec5e", "#5fb82a"),
    "orange": ("#ffb84a", "#fb7d1e"),
    "red": ("#ff7777", "#e1344f"),
    "pink": ("#ff7ab8", "#d62f8c"),
    "indigo": ("#7d86ff", "#4036d6"),
    "yellow": ("#ffd84a", "#f0a512"),
    "night": ("#232049", "#0a0720"),
    "slate": ("#3b3e4f", "#1a1c27"),
}

TOKYO = {
    "gray": ("#8a96c4", "#474d6e"),
    "graphite": ("#5f688f", "#2b2f47"),
    "blue": ("#8db4ff", "#3d59a1"),
    "sky": ("#9ad8ff", "#2e8fc4"),
    "teal": ("#7fe0cf", "#1a9c8c"),
    "violet": ("#c8a8ff", "#7a4fd0"),
    "green": ("#a9d97a", "#4e8c2a"),
    "lime": ("#c9eb97", "#6aa832"),
    "orange": ("#ffaa72", "#e0642a"),
    "red": ("#ff8aa0", "#c73a5a"),
    "pink": ("#ff9bd0", "#c2459a"),
    "indigo": ("#8f9cff", "#3f48c2"),
    "yellow": ("#ecbf78", "#c0801e"),
    "night": ("#2a2f48", "#14151f"),
    "slate": ("#343955", "#1a1b26"),
}

BRAND = ("#2ff0dc", "#8d44d4")
BRAND_TOKYO = ("#7dcfff", "#bb9af7")
SQM = squircle(512, 512, 412, 5.0, 220, 1)
SQM_IN = squircle(512, 512, 407, 5.0, 220, 1)
DEFAULT_TEXT = "#e4e7f0"
MONO_RE = re.compile(r"^(network-|audio-|battery|bluetooth|redshift|night-light|input-|media-|drive-|printer|phone$|smartphone|avatar-|user-identity|system-users|system-log-out|system-run|video-display|help-|software-update|system-software-update|dialog-|wifi$|xorg$|emblem-)")
PLAIN_PLACES = {"user-trash", "user-trash-symbolic", "user-trash-full"}


def glyph_markup(name, color, scale=1):
    return G[name].replace("@", color)


def plain_svg(glyph, sw, default, color=None, cls="ColorScheme-Text"):
    c = color or "currentColor"
    g = glyph_markup(glyph, c)
    st = f'<style id="current-color-scheme" type="text/css">.{cls}{{color:{default}}}</style>' if not color else ""
    ca = f' class="{cls}"' if not color else ""
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">{st}<g{ca} fill="none" stroke="{c}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">{g}</g></svg>
'''


def inner_svg(outer, inner, cy, scale, sw, osw, default, cls="ColorScheme-Text"):
    og = outer.replace("@", "currentColor")
    ig = glyph_markup(inner, "currentColor") if inner else ""
    ib = f'<g transform="translate(12 {cy}) scale({scale}) translate(-12 -12)" stroke-width="{sw}">{ig}</g>' if inner else ""
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><style id="current-color-scheme" type="text/css">.{cls}{{color:{default}}}</style><g class="{cls}" fill="none" stroke="currentColor" stroke-width="{osw}" stroke-linecap="round" stroke-linejoin="round">{og}{ib}</g></svg>
'''


class Style:
    suffix = ""

    def write_sym(self, sub, n, svg):
        write(sub, n, svg)
        if not n.endswith("-symbolic"):
            write(sub, n + "-symbolic", svg)

    def app(self, names, glyph, pal, sub, dark):
        if "kwick-start" in names.split():
            for n in ("kwick-start", "kwick-start-fluent"):
                write("apps", n, kmark())
            return
        svg = self.tile(glyph, pal, dark)
        for n in names.split():
            write(sub, n, svg)

    def folder(self, names, glyph, pal):
        svg = self.folder_svg(glyph, pal)
        for n in names.split():
            write("places", n, svg)

    def page(self, names, glyph, pal):
        svg = self.page_svg(glyph, pal)
        for n in names.split():
            write("mimetypes", n, svg)

    def act(self, names, glyph, color):
        svg = self.plain(glyph, None if color == DEFAULT_TEXT else color)
        for n in names.split():
            self.write_sym("actions", n, svg)

    def stat(self, names, glyph, color):
        svg = self.plain(glyph, None if color == DEFAULT_TEXT else color)
        for n in names.split():
            self.write_sym("status", n, svg)

    def side(self, names, glyph):
        svg = self.side_svg(glyph)
        for n in names.split():
            write("places", n, svg)


class Glass(Style):
    colors = DEEP
    brand = BRAND
    sw = 1.75
    text = "#e8ebf4"
    accent = "#0a84ff"

    def tile(self, glyph, pal, dark):
        return FI.free_icon(glyph, self.colors, pal, glyph_markup, ID.DV)

    def folder_cols(self, pal):
        return None

    def folder_svg(self, glyph, pal):
        return ID.folder_svg("mac", glyph, glyph_markup, self.folder_cols(pal))

    def folder(self, names, glyph, pal):
        for n in names.split():
            if n.startswith("user-trash"):
                write("places", n, self.tile("trash", "red" if n.endswith("full") else "gray", False))
            elif n in PI.PLACE_OBJ:
                key, pl = PI.PLACE_OBJ[n]
                c1, c2 = self.colors[pl]
                write("places", n, PI.place_svg(key, c1, c2, ID.DV))
            else:
                write("places", n, self.folder_svg(None, pal))

    def page_svg(self, glyph, pal):
        c1, c2 = self.colors[pal]
        return ID.page_svg(glyph, c1, c2, glyph_markup)

    def plain(self, glyph, color):
        return plain_svg(glyph, self.sw, self.text, color)

    def side_svg(self, glyph):
        return plain_svg(glyph, 1.8, self.accent, None, "ColorScheme-Highlight")


TRAY_RE = re.compile(r"^(network-|audio-volume|audio-input|audio-card|battery|bluetooth|redshift|night-light|avatar-|user-identity|system-users|system-switch-user|video-display|printer|smartphone|drive-removable|media-removable|kdeconnect|klipper|color-picker|kcolorchooser|notification|preferences-system-notifications|ac-adapter|input-)")


class Mac(Glass):
    text = "#ffffff"
    name = "KwickOS"
    comment = "KwickOS macOS-style icon set: Liquid Glass squircle apps, blue folders, accent-blue sidebar glyphs"
    inherits = "Papirus-Dark,breeze-dark,hicolor"

    def app(self, names, glyph, pal, sub, dark):
        ns = names.split()
        mono = [n for n in ns if TRAY_RE.match(n)]
        for n in mono:
            self.write_sym("status", n, self.plain(glyph, None))
        rest = [n for n in ns if n not in mono]
        if rest:
            Glass.app(self, " ".join(rest), glyph, pal, sub, dark)


class Linux(Glass):
    name = "KwickOS-Linux"
    comment = "KwickOS Linux variant: Tokyo Night glass squircles and folders"
    inherits = "KwickOS,Papirus-Dark,breeze-dark,hicolor"
    colors = TOKYO_DEEP
    brand = BRAND_TOKYO
    text = "#c0caf5"
    accent = "#7aa2f7"

    def folder_cols(self, pal):
        c1, c2 = TOKYO_DEEP[pal]
        return ID.tint_folder(c1, c2)


class Fluent(Style):
    name = "KwickOS-Fluent"
    comment = "KwickOS Windows layout icons: Fluent shapes for apps and folders, white line glyphs for the interface"
    inherits = "KwickOS,breeze-dark,hicolor"
    sw = 1.6

    def tile(self, glyph, pal, dark):
        if glyph == "folder":
            return ID.folder_svg("fluent", None, glyph_markup)
        return FI.free_icon(glyph, DEEP, pal, glyph_markup, ID.DD)

    def plain(self, glyph, color):
        return plain_svg(glyph, self.sw, "#ffffff", color)

    def side_svg(self, glyph):
        return plain_svg(glyph, self.sw, "#ffffff")

    def mono(self, names, glyph, sub):
        svg = self.plain(glyph, None)
        for n in names:
            self.write_sym(sub, n, svg)

    def app(self, names, glyph, pal, sub, dark):
        ns = names.split()
        if sub == "categories":
            self.mono(ns, glyph, sub)
            return
        if "kwick-start" in ns:
            for n in ("kwick-start", "kwick-start-fluent"):
                write("apps", n, kmark())
            return
        if sub == "preferences":
            mono = [n for n in ns if MONO_RE.match(n)]
            self.mono(mono, glyph, "status")
            ns = [n for n in ns if n not in mono]
        svg = self.tile(glyph, pal, dark)
        for n in ns:
            write(sub, n, svg)

    def folder(self, names, glyph, pal):
        for n in names.split():
            if n in PLAIN_PLACES:
                self.write_sym("places", n, self.plain("trashfull" if n == "user-trash-full" else glyph or "folder", None))
            elif n in PI.PLACE_OBJ:
                key, pl = PI.PLACE_OBJ[n]
                c1, c2 = DEEP[pl]
                write("places", n, PI.place_svg(key, c1, c2, ID.DD))
            else:
                write("places", n, ID.folder_svg("fluent", None, glyph_markup))

    def page(self, names, glyph, pal):
        direct = glyph in ("page", "text", "file")
        svg = self.plain(glyph, None) if direct else inner_svg(G["page"], glyph, 14.2, 0.44, 3.4, self.sw, "#ffffff")
        for n in names.split():
            write("mimetypes", n, svg)


STYLES = {"macos": Mac, "linux": Linux, "windows": Fluent}
STYLE = None
OUT = None


def kmark():
    src = open(os.path.join(ROOT, "desktop/rootfs/usr/share/icons/hicolor/scalable/apps/kwickos-symbolic.svg"), encoding="utf-8").read()
    return re.sub(r"<svg[^>]*>", '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="-18.5 0 272 272">', src, count=1)


def write(sub, name, text):
    p = os.path.join(OUT, "scalable", sub, name + ".svg")
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", newline="\n") as f:
        f.write(text)


def app(names, glyph, pal, sub="apps", dark=False):
    STYLE.app(names, glyph, pal, sub, dark)


def pref(names, glyph, pal):
    STYLE.app(names, glyph, pal, "preferences", False)


def folder(names, glyph=None, pal="blue"):
    STYLE.folder(names, glyph, pal)


def side(names, glyph):
    STYLE.side(names, glyph)


def act(names, glyph, color=DEFAULT_TEXT):
    STYLE.act(names, glyph, color)


def stat(names, glyph, color=DEFAULT_TEXT):
    STYLE.stat(names, glyph, color)


def page(names, glyph, pal):
    STYLE.page(names, glyph, pal)


def build():
    if os.path.isdir(OUT):
        for d in os.listdir(os.path.join(OUT, "scalable")) if os.path.isdir(os.path.join(OUT, "scalable")) else []:
            shutil.rmtree(os.path.join(OUT, "scalable", d))

    pref("preferences-system org.kde.systemsettings systemsettings kwick-settings preferences-other preferences-system-settings applications-system-settings", "gear", "gray")
    pref("preferences-desktop org.kde.plasma.settings.open preferences-desktop-plasma preferences-desktop-personal", "desktop", "indigo")
    pref("preferences-desktop-wallpaper preferences-desktop-wallpaper-symbolic", "image", "teal")
    pref("preferences-desktop-theme-global systemsettings-quick-settings preferences-desktop-color preferences-desktop-theme preferences-desktop-plasma-theme preferences-desktop-theme-applications preferences-desktop-plasma preferences-desktop-theme-style preferences-desktop-appearance kcm_colors kcm_style kcm_lookandfeel", "palette", "violet")
    pref("preferences-desktop-font preferences-desktop-font-installer preferences-fonts fonts font", "font", "indigo")
    pref("preferences-desktop-icons", "apps", "orange")
    pref("preferences-desktop-cursors", "cursor", "blue")
    pref("preferences-desktop-theme-windowdecorations preferences-system-windows preferences-system-windows-behavior", "windows", "sky")
    pref("preferences-system-windows-actions preferences-system-windows-rules preferences-system-windows-move preferences-system-windows-effect-flipswitch preferences-system-windows-effect-glide preferences-system-windows-effect-minimize", "windows", "indigo")
    pref("preferences-desktop-effects preferences-desktop-effects-symbolic kwick-effects", "sparkle", "pink")
    pref("preferences-desktop-virtual preferences-desktop-workspaces preferences-system-desktops", "desktops", "teal")
    pref("preferences-desktop-activities preferences-activities", "activities", "violet")
    pref("preferences-system-tabbox preferences-system-windows-switcher", "tabbox", "blue")
    pref("preferences-desktop-notification-bell preferences-desktop-notification preferences-system-notifications", "bell", "red")
    pref("preferences-desktop-screensaver preferences-system-lock-screen preferences-desktop-screenlocker", "moon", "indigo")
    pref("preferences-desktop-launch-feedback preferences-desktop-feedback preferences-system-launch-feedback", "loader", "orange")
    pref("preferences-system-splash preferences-desktop-splash", "sparkle", "violet")
    pref("preferences-system-session-services system-run preferences-system-session preferences-desktop-startup preferences-system-startup preferences-system-autostart", "autostart", "green")
    pref("system-log-out preferences-system-login preferences-system-login-screen", "logout", "slate")
    pref("kwick-search preferences-desktop-baloo preferences-system-search plasma-search krunner preferences-desktop-search", "search", "sky")
    pref("preferences-desktop-keyboard preferences-desktop-input-devices input-keyboard", "keyboard", "gray")
    pref("input-keyboard-virtual preferences-desktop-virtual-keyboard", "keyboard", "slate")
    pref("preferences-desktop-keyboard-shortcut preferences-desktop-keyboard-shortcuts preferences-desktop-shortcuts configure-shortcuts", "keyboard", "orange")
    pref("preferences-desktop-mouse input-mouse preferences-desktop-pointing-devices", "mouse", "gray")
    pref("preferences-desktop-touchpad input-touchpad", "touchpad", "gray")
    pref("preferences-desktop-touchscreen input-touchscreen", "touch", "gray")
    pref("preferences-desktop-tablet input-tablet", "tablet", "gray")
    pref("preferences-desktop-gaming input-gamepad preferences-desktop-gamecontroller kwick-gaming", "gamepad", "violet")
    pref("preferences-desktop-peripherals preferences-system-peripherals", "peripheral", "gray")
    pref("preferences-desktop-sound audio-card audio-volume-high preferences-sound preferences-desktop-sound-output emblem-music-symbolic", "speaker", "red")
    pref("preferences-desktop-display preferences-desktop-display-randr preferences-desktop-display-randr-symbolic video-display preferences-desktop-screen video-display-symbolic", "display", "blue")
    pref("preferences-desktop-display-color redshift-status-on preferences-system-nightlight night-light", "nightlight", "orange")
    pref("preferences-system-network network-wireless preferences-network-wireless network-wireless-connected-100 network-wireless-signal-excellent preferences-system-network-wireless preferences-system-wifi wifi preferences-system-network-wifi", "wifi", "blue")
    pref("network-wired preferences-network-wired preferences-system-network-ethernet network-wired-activated", "ethernet", "teal")
    pref("preferences-system-bluetooth bluetooth preferences-bluetooth", "bluetooth", "blue")
    pref("preferences-system-network-proxy preferences-network-proxy preferences-system-vpn network-vpn", "shield", "indigo")
    pref("preferences-system-time preferences-system-clock preferences-desktop-datetime", "clock", "orange")
    pref("preferences-desktop-locale preferences-desktop-language preferences-desktop-regional preferences-system-language", "globe", "blue")
    pref("preferences-system-power-management preferences-system-power preferences-system-battery battery", "battery", "green")
    pref("preferences-system-users preferences-desktop-user system-users user-identity avatar-default", "users", "gray")
    pref("preferences-desktop-accessibility preferences-desktop-accessibility-symbolic kaccess", "access", "blue")
    pref("preferences-desktop-default-applications preferences-desktop-applications preferences-system-default-applications preferences-desktop-default-applications-symbolic preferences-desktop-filetype-association preferences-system-file-associations", "apps", "indigo")
    pref("preferences-security preferences-system-privacy preferences-desktop-user-password preferences-system-firewall preferences-security-privacy preferences-system-security org.kde.kwalletmanager5 kwalletmanager", "lock", "gray")
    pref("preferences-desktop-online-accounts preferences-system-online-accounts kaccounts org.gnome.OnlineAccounts", "accounts", "blue")
    pref("preferences-system-printing printer preferences-printer", "printer", "gray")
    pref("preferences-system-device-notifier media-removable drive-removable-media preferences-system-removable", "usb", "gray")
    pref("preferences-system-connections preferences-system-network-sharing preferences-system-sharing", "share", "teal")
    pref("kdeconnect preferences-system-kdeconnect smartphone-connect phone", "phone", "green")
    pref("preferences-system-about help-about dialog-information-large org.kde.kinfocenter kinfocenter", "info", "sky")
    pref("preferences-system-software-update system-software-update software-update-available preferences-system-updates", "update", "orange")
    pref("tools-check-spelling preferences-desktop-spell-checker preferences-desktop-text-to-speech", "spell", "pink")
    pref("preferences-desktop-notification-bell-symbolic", "bell", "red")
    pref("xorg preferences-system-xorg preferences-system-xwayland", "display", "slate")
    pref("preferences-desktop-user-account preferences-desktop-online-user", "user", "gray")
    pref("preferences-system-storage preferences-system-disk", "harddisk", "gray")
    pref("preferences-web-browser-cookies preferences-web-browser-shortcuts preferences-desktop-privacy", "shield", "gray")
    pref("preferences-system-gpu kwick-gpu", "chip", "slate")
    pref("preferences-desktop-kwick-layout kwick-layout", "layout", "indigo")
    pref("kwick-dock", "dock", "night")
    pref("kwick-desktop", "desktop", "night")
    pref("kwick-fonts", "font", "night")
    pref("preferences-system-history preferences-desktop-recent preferences-system-recent-files preferences-desktop-recent-files", "history", "teal")
    pref("preferences-desktop-theme-sounds preferences-desktop-notification-sounds", "sound", "pink")
    pref("preferences-system-linux preferences-system-kernel", "linux", "slate")
    pref("preferences-plugin preferences-system-plugins kcm_kwin_scripts preferences-desktop-scripts", "pkg", "violet")
    pref("preferences-system-power-profile", "bolt", "yellow")
    pref("preferences-system-hotcorners", "windows", "teal")
    pref("preferences-system-services preferences-system-background-services preferences-system-kded", "wrench", "gray")

    app("system-file-manager org.kde.dolphin dolphin kwick-files org.gnome.Nautilus nautilus org.gnome.Files folder-manager", "folder", "blue")
    app("utilities-terminal org.kde.konsole konsole kwick-terminal org.gnome.Terminal org.gnome.Console gnome-terminal foot utilities-terminal-symbolic", "terminal", "night", dark=True)
    app("accessories-text-editor kwick-editor org.kde.kate kate org.gnome.TextEditor org.kde.kwrite kwrite gedit text-editor", "pencilpage", "orange")
    app("org.kde.discover kwick-software plasmadiscover system-software-install org.gnome.Software gnome-software discover org.kde.discover.notifier", "bag", "blue")
    app("org.kde.gwenview kwick-image-viewer gwenview org.gnome.Loupe eog image-viewer org.kde.gwenview_importer", "image", "teal")
    app("org.kde.okular kwick-document-viewer okular org.gnome.Evince org.gnome.Papers evince papers document-viewer application-pdf-viewer okularApplication_pdf", "book", "red")
    app("org.kde.ark kwick-archive-manager ark file-roller org.gnome.FileRoller package-x-generic utilities-file-archiver", "archive", "yellow")
    app("org.kde.spectacle kwick-screenshot spectacle org.gnome.Screenshot gnome-screenshot applets-screenshooter accessories-screenshot", "screenshot", "pink")
    app("org.kde.kcalc kwick-calculator kcalc org.gnome.Calculator gnome-calculator accessories-calculator calc", "calc", "graphite")
    app("org.kde.plasma-systemmonitor kwick-system-monitor plasma-systemmonitor org.gnome.SystemMonitor gnome-system-monitor utilities-system-monitor ksysguard org.kde.ksysguard", "pulse", "green")
    app("org.gnome.Settings gnome-control-center org.gnome.tweaks gnome-tweaks", "gear", "gray")
    app("org.kde.kinfocenter", "info", "sky")
    app("org.kde.plasma.emojier accessories-character-map emoji-people org.gnome.Characters", "emoji", "yellow")
    app("org.kde.klipper klipper", "clipboard", "gray")
    app("org.kde.kfontview org.kde.kfontinst", "font", "indigo")
    app("org.kde.kcolorschemeeditor", "palette", "violet")
    app("org.kde.partitionmanager partitionmanager gnome-disks org.gnome.DiskUtility", "harddisk", "gray")
    app("org.kde.kmenuedit kmenuedit alacarte", "menu", "gray")
    app("org.kde.kdeconnect.app org.kde.kdeconnect-settings kdeconnect-app", "phone", "green")
    app("org.kde.kwalletmanager5", "wallet", "orange")
    app("org.kde.drkonqi drkonqi", "bug", "red")
    app("org.kde.kwin.killer xkill process-stop-app", "close", "red")
    app("org.kde.knetattach", "ethernet", "teal")
    app("org.gnome.Calendar accessories-calendar office-calendar korganizer", "calendar", "red")
    app("org.gnome.Contacts", "users", "orange")
    app("org.gnome.Music multimedia-audio-player rhythmbox elisa org.kde.elisa", "music", "red")
    app("org.gnome.Totem totem vlc multimedia-video-player org.kde.haruna haruna", "video", "indigo")
    app("org.gnome.clocks", "clock", "orange")
    app("org.gnome.Characters", "emoji", "yellow")
    app("org.gnome.Tecla", "keyboard", "gray")
    app("org.gnome.Shell.Extensions extensions", "pkg", "violet")
    app("org.kde.plasma.digitalclock", "clock", "slate")
    app("kwick-start", "bolt", "night", dark=True)
    app("preferences-system-help help-browser system-help help-contents org.kde.khelpcenter khelpcenter", "question", "blue")
    app("internet-mail mail-client org.kde.kmail2 evolution thunderbird-mail", "mail", "blue")
    app("camera-photo cheese org.gnome.Cheese", "camera", "gray")
    app("applications-games applications-games-symbolic", "gamepad", "violet", sub="categories")
    app("applications-system applications-system-symbolic", "gear", "gray", sub="categories")
    app("applications-utilities applications-accessories", "wrench", "orange", sub="categories")
    app("applications-internet applications-network", "globe", "blue", sub="categories")
    app("applications-multimedia applications-sound applications-video", "play", "pink", sub="categories")
    app("applications-graphics", "image", "teal", sub="categories")
    app("applications-office", "page", "yellow", sub="categories")
    app("applications-development applications-engineering", "terminal", "slate", sub="categories")
    app("applications-science applications-education applications-mathematics", "calc", "indigo", sub="categories")
    app("applications-other applications-all applications-science-symbolic", "apps", "gray", sub="categories")

    folder("folder inode-directory folder-symbolic folder-default folder-blue folder-black folder-grey")
    folder("folder-documents", "page")
    folder("folder-download folder-downloads", "download", "teal")
    folder("folder-pictures", "image", "pink")
    folder("folder-music", "music", "red")
    folder("folder-video folder-videos", "video", "violet")
    folder("folder-publicshare folder-public folder-remote folder-remote-ftp", "share", "sky")
    folder("folder-templates", "newpage", "gray")
    folder("folder-recent folder-history", "history", "teal")
    folder("folder-favorites folder-bookmark folder-starred", "star", "orange")
    folder("folder-cloud folder-owncloud folder-nextcloud", "cloud", "sky")
    folder("folder-games", "gamepad", "violet")
    folder("folder-open folder-drag-accept folder-visiting")
    folder("user-home folder-home", "home", "blue")
    folder("user-desktop folder-desktop", "desktop", "indigo")
    folder("folder-locked folder-encrypted", "lock", "gray")
    folder("folder-development folder-code", "terminal", "slate")
    folder("folder-network folder-smb folder-remote-network network-workgroup network-server", "globe", "sky")
    folder("user-trash user-trash-symbolic", "trash", "gray")
    folder("user-trash-full", "trash", "red")
    app("drive-harddisk drive-harddisk-system drive-harddisk-solidstate drive-harddisk-usb drive-multidisk media-optical computer-laptop computer", "harddisk", "gray", sub="devices")
    app("drive-removable-media drive-removable-media-usb media-flash media-removable usb-drive", "usb", "gray", sub="devices")
    app("network-wired-device", "ethernet", "teal", sub="devices")
    app("printer-network printer-device", "printer", "gray", sub="devices")
    app("input-gaming input-gamepad-device", "gamepad", "violet", sub="devices")
    app("phone-device smartphone", "phone", "green", sub="devices")
    app("camera-web video-camera", "camera", "gray", sub="devices")
    app("audio-input-microphone audio-input-microphone-device", "mic", "red", sub="devices")
    app("audio-headphones audio-headset", "speaker", "red", sub="devices")
    app("network-server-device", "globe", "sky", sub="devices")
    app("computer-device computer-symbolic-device", "display", "blue", sub="devices")

    page("text-x-generic text-plain text-x-script text-x-log", "text", "gray")
    page("application-pdf application-x-pdf", "book", "red")
    page("image-x-generic image-png image-jpeg image-svg+xml image-gif image-webp", "image", "teal")
    page("audio-x-generic audio-mpeg audio-flac audio-x-wav audio-ogg", "music", "pink")
    page("video-x-generic video-mp4 video-x-matroska video-webm", "video", "violet")
    page("application-x-archive application-zip application-x-tar application-gzip application-x-compressed-tar application-x-7z-compressed application-vnd.rar", "archive", "yellow")
    page("application-x-executable application-x-shellscript application-x-sharedlib application-x-pie-executable", "terminal", "green")
    page("text-x-python text-x-csrc text-x-c++src text-x-java text-x-javascript text-html text-css application-json text-x-go text-x-rust text-x-makefile", "terminal", "blue")
    page("application-x-deb application-x-rpm application-vnd.debian.binary-package application-x-package", "pkg", "orange")
    page("application-vnd.oasis.opendocument.text application-msword application-vnd.openxmlformats-officedocument.wordprocessingml.document text-x-markdown", "text", "blue")
    page("application-vnd.oasis.opendocument.spreadsheet application-vnd.ms-excel text-csv", "listview", "green")
    page("application-x-iso application-x-cd-image application-x-raw-disk-image", "harddisk", "gray")
    page("font-x-generic application-x-font-ttf application-x-font-otf font-ttf font-otf", "font", "indigo")
    page("unknown application-octet-stream application-x-generic", "page", "gray")

    S = "#e4e7f0"
    act("document-open document-open-folder", "open")
    act("document-save", "save")
    act("document-save-as", "save")
    act("document-new", "newpage")
    act("document-edit edit-rename", "edit")
    act("document-print", "printer")
    act("document-export", "upload")
    act("document-import", "download")
    act("document-open-recent", "recent")
    act("edit-copy", "copy")
    act("edit-cut", "cut")
    act("edit-paste", "paste")
    act("edit-delete edit-delete-shred", "trash")
    act("edit-undo", "undo")
    act("edit-redo", "redo")
    act("edit-find system-search edit-find-replace", "search")
    act("edit-clear edit-clear-all edit-clear-locationbar-ltr edit-clear-locationbar-rtl", "close")
    act("edit-select-all", "iconview")
    act("list-add list-add-symbolic add", "plus")
    act("list-remove list-remove-symbolic remove", "minus")
    act("go-next go-next-symbolic", "right")
    act("go-previous go-previous-symbolic", "left")
    act("go-up go-up-symbolic", "up")
    act("go-down go-down-symbolic", "down")
    act("go-home", "home")
    act("go-jump", "arrowr")
    act("go-top", "arrowu")
    act("go-bottom", "arrowd")
    act("pan-down pan-down-symbolic", "down")
    act("pan-up pan-up-symbolic", "up")
    act("pan-start pan-start-symbolic", "left")
    act("pan-end pan-end-symbolic", "right")
    act("view-refresh reload", "refresh")
    act("view-list-details view-list-text view-list-symbolic", "listview")
    act("view-list-icons view-grid view-grid-symbolic view-app-grid", "iconview")
    act("view-sort-ascending view-sort-descending view-sort", "sort")
    act("view-filter", "filter")
    act("view-more view-more-symbolic open-menu open-menu-symbolic overflow-menu", "dots")
    act("application-menu", "menu")
    act("window-close window-close-symbolic dialog-close", "close")
    act("window-new tab-new", "plus")
    act("application-exit", "logout")
    act("zoom-in", "zoomin")
    act("zoom-out", "zoomout")
    act("zoom-fit-best zoom-original", "search")
    act("folder-new", "newfolder")
    act("archive-extract", "download")
    act("archive-insert", "upload")
    act("bookmark-new bookmarks", "bookmark")
    act("bookmark-add", "bookmark")
    act("emblem-favorite starred", "star")
    act("favorite", "heart")
    act("mail-send", "arrowr")
    act("mail-message-new", "edit")
    act("insert-link", "link")
    act("tag", "tag")
    act("system-shutdown", "power")
    act("system-reboot system-restart", "restart")
    act("system-suspend system-suspend-hibernate", "suspend")
    act("system-lock-screen", "lockscreen")
    act("system-switch-user", "users")
    act("preferences-system-symbolic configure", "gear")
    act("configure-toolbars", "gear")
    act("help-contents help-about-symbolic", "question")
    act("help-about", "info")
    act("dialog-information", "info", "#6ab6ff")
    act("dialog-warning", "warning", "#ffc247")
    act("dialog-error", "error", "#ff6b6b")
    act("dialog-question", "question", "#6ab6ff")
    act("dialog-ok dialog-ok-apply emblem-ok emblem-default object-select", "check", "#5be37d")
    act("dialog-cancel", "close")
    act("media-playback-start", "play")
    act("media-playback-pause", "pause")
    act("media-playback-stop", "stop")
    act("media-skip-forward", "next")
    act("media-skip-backward", "prev")
    act("media-record", "record", "#ff6b6b")
    act("media-eject", "eject")
    act("audio-volume-muted", "volumeoff")
    act("audio-volume-low audio-volume-medium audio-volume-high", "speaker")
    act("audio-input-microphone-symbolic", "mic")
    act("window-maximize window-restore", "windows")
    act("document-properties", "info")
    act("object-locked", "lock")
    act("object-unlocked", "lock")
    act("network-connect", "link")
    act("network-wireless-symbolic network-wireless-signal-good network-wireless-signal-ok", "wifi")
    act("network-wired-symbolic", "ethernet")
    act("bluetooth-active bluetooth-symbolic", "bluetooth")
    act("battery-full battery-good battery-low battery-caution battery-full-symbolic", "battery")
    stat("dialog-information-symbolic", "info")
    stat("dialog-warning-symbolic", "warning", "#ffc247")
    stat("dialog-error-symbolic", "error", "#ff6b6b")
    stat("task-complete", "check", "#5be37d")
    stat("view-private security-high", "lock")
    stat("dialog-password", "key")
    stat("software-update-urgent", "update", "#ffc247")
    stat("weather-clear", "nightlight")
    stat("media-playlist-repeat", "refresh")
    stat("appointment-new", "calendar")
    stat("notification-active notification-new", "bell")
    stat("preferences-system-time-symbolic", "clock")
    stat("night-light-symbolic", "nightlight")
    stat("microphone-sensitivity-high", "mic")
    stat("emblem-synchronizing", "refresh")
    stat("emblem-shared", "share")
    stat("starred-symbolic", "star")

    def tray(names, glyph):
        act(names, glyph)
        for n in names.split():
            if n.endswith("-symbolic"):
                continue
            STYLE.write_sym("status", n, STYLE.plain(glyph, None))

    tray("audio-volume-muted audio-volume-muted-blocking audio-volume-zero audio-volume-off", "volumeoff")
    tray("audio-volume-low audio-volume-medium audio-volume-high audio-volume-overamplified audio-card", "speaker")
    tray("audio-input-microphone audio-input-microphone-low audio-input-microphone-medium audio-input-microphone-high microphone-sensitivity-low microphone-sensitivity-medium microphone-sensitivity-muted", "mic")
    tray("audio-input-microphone-muted", "mic")
    tray(" ".join(f"network-wireless-{k}" for k in ("connected", "disconnected", "offline", "acquiring", "disabled", "hotspot", "signal-excellent", "signal-weak", "signal-none", "connected-100", "connected-80", "connected-60", "connected-40", "connected-20", "connected-00", "100", "80", "60", "40", "20", "0", "00", "secure", "secure-connected", "no-route")), "wifi")
    tray("network-wired-activated network-wired-disconnected network-wired-unavailable network-wired-no-route network-idle network-transmit network-receive network-transmit-receive network-offline network-disconnect network-wireless-off network-mobile network-vpn network-vpn-acquiring network-workgroup", "ethernet")
    tray("bluetooth bluetooth-disabled bluetooth-inactive bluetooth-connected bluetooth-paired bluetooth-offline", "bluetooth")
    tray(" ".join(f"battery-{k}" for k in ("000", "010", "020", "030", "040", "050", "060", "070", "080", "090", "100", "empty", "missing", "full-charged", "full-charging", "good-charging", "low-charging", "caution-charging", "000-charging", "010-charging", "020-charging", "030-charging", "040-charging", "050-charging", "060-charging", "070-charging", "080-charging", "090-charging", "100-charging", "level-0-symbolic", "level-10-symbolic", "level-20-symbolic", "level-30-symbolic", "level-40-symbolic", "level-50-symbolic", "level-60-symbolic", "level-70-symbolic", "level-80-symbolic", "level-90-symbolic", "level-100-symbolic", "level-100-charged-symbolic")) + " ac-adapter battery-profile-performance battery-profile-balanced battery-profile-power-saver battery-profile-performance-symbolic battery-profile-balanced-symbolic battery-profile-power-saver-symbolic", "battery")
    tray("preferences-system-notifications notifications notifications-disabled notification-inactive notification-disabled preferences-desktop-notification", "bell")
    tray("klipper edit-paste-symbolic clipboard", "clipboard")
    tray("color-picker kcolorchooser color-management preferences-desktop-color", "palette")
    tray("redshift-status-on redshift-status-off night-light night-light-disabled night-light-symbolic preferences-system-night-light preferences-desktop-nightlight", "nightlight")
    tray("user-identity avatar-default system-users system-switch-user kuser user-available user-offline user-away user-busy preferences-desktop-user preferences-desktop-user-password", "user")
    tray("arrow-down arrow-down-double go-down-skip", "arrowd")
    tray("arrow-up arrow-up-double go-up-skip", "arrowu")
    tray("arrow-left arrow-left-double", "arrowl")
    tray("arrow-right arrow-right-double", "arrowr")
    tray("drive-removable-media media-removable drive-removable-media-usb device-notifier", "usb")
    tray("kdeconnect-tray kdeconnect smartphone phone", "phone")
    tray("printer printer-printing printer-error", "printer")
    tray("video-display video-display-brightness display-brightness screen-brightness", "display")

    side("user-home-symbolic folder-home-symbolic", "home")
    side("user-desktop-symbolic folder-desktop-symbolic", "desktop")
    side("folder-documents-symbolic", "text")
    side("folder-download-symbolic folder-downloads-symbolic", "download")
    side("folder-pictures-symbolic", "image")
    side("folder-music-symbolic", "music")
    side("folder-video-symbolic folder-videos-symbolic", "video")
    side("user-trash-symbolic", "trash")
    side("user-trash-full-symbolic", "trashfull")
    side("folder-network-symbolic network-workgroup-symbolic folder-remote-symbolic", "globe")
    side("folder-recent-symbolic", "recent")
    side("drive-harddisk-symbolic", "harddisk")
    side("folder-symbolic", "folder")
    side("folder-publicshare-symbolic", "share")
    act("kwick-taskview", "tabbox")

    names = {}
    for sub in ("apps", "preferences", "categories", "places", "devices", "actions", "status", "mimetypes"):
        d = os.path.join(OUT, "scalable", sub)
        names[sub] = len(os.listdir(d)) if os.path.isdir(d) else 0
    dirs = ["scalable/%s" % s for s in names if names[s]]
    ctx = {"apps": "Applications", "preferences": "Applications", "categories": "Categories", "places": "Places",
           "devices": "Devices", "actions": "Actions", "status": "Status", "mimetypes": "MimeTypes"}
    idx = ["[Icon Theme]", f"Name={STYLE.name}", f"Comment={STYLE.comment}",
           f"Inherits={STYLE.inherits}", "Example=folder",
           "DesktopDefault=48", "DesktopSizes=16,22,32,48,64,128,256", "ToolbarDefault=22", "ToolbarSizes=16,22,24,32",
           "MainToolbarDefault=22", "MainToolbarSizes=16,22,24,32", "SmallDefault=16", "SmallSizes=16,22",
           "PanelDefault=48", "PanelSizes=16,22,32,48,64", "DialogDefault=32", "DialogSizes=32,48,64,128",
           "Directories=" + ",".join(dirs), ""]
    for dpath in dirs:
        sub = dpath.split("/")[1]
        idx += [f"[{dpath}]", "Size=64", "MinSize=8", "MaxSize=1024", "Type=Scalable", f"Context={ctx[sub]}", ""]
    with open(os.path.join(OUT, "index.theme"), "w", newline="\n") as f:
        f.write("\n".join(idx))
    if isinstance(STYLE, Mac):
        for nm, gl, pl in (("layout", "layout", "blue"), ("dock", "dock", "indigo"), ("effects", "flame", "orange"), ("fonts", "font", "indigo"), ("desktop", "display", "blue"), ("gpu", "chip", "green"), ("gaming", "gamepad", "violet")):
            sp = os.path.join(ROOT, "desktop/rootfs/usr/share/kwick/settings/icons", "obj-" + nm + ".svg")
            with open(sp, "w", newline="\n") as f:
                f.write(FI.free_icon(gl, STYLE.colors, pl, glyph_markup, ID.DV, shadow=False))
    print(STYLE.name, names)


for key in (sys.argv[2:] or list(STYLES)):
    STYLE = STYLES[key]()
    OUT = os.path.join(ROOT, "desktop/rootfs/usr/share/icons", STYLE.name)
    build()
