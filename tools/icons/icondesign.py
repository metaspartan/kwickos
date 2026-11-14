import math

XL = 'xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"'
DV = 'x1="0" y1="0" x2="0" y2="1"'
DD = 'x1="0" y1="0" x2="1" y2="1"'


def mix(a, b, t):
    a = a.lstrip("#")
    b = b.lstrip("#")
    ca = [int(a[i:i + 2], 16) for i in (0, 2, 4)]
    cb = [int(b[i:i + 2], 16) for i in (0, 2, 4)]
    return "#" + "".join(f"{round(x + (y - x) * t):02x}" for x, y in zip(ca, cb))


def lg(i, stops, d=DV, extra=""):
    s = "".join(f'<stop offset="{o}" stop-color="{c}"' + (f' stop-opacity="{op[0]}"' if (op := rest) else "") + "/>" for o, c, *rest in stops)
    return f'<linearGradient id="{i}" {d} {extra}>{s}</linearGradient>'


def rg(i, stops, cx=0.5, cy=0.5, r=0.5, extra=""):
    s = "".join(f'<stop offset="{o}" stop-color="{c}"' + (f' stop-opacity="{op[0]}"' if (op := rest) else "") + "/>" for o, c, *rest in stops)
    return f'<radialGradient id="{i}" cx="{cx}" cy="{cy}" r="{r}" {extra}>{s}</radialGradient>'


def gearp(cx, cy, ro, ri, n):
    pts = []
    pitch = 2 * math.pi / n
    for i in range(n):
        a = pitch * i
        for da, r in ((-0.30, ri), (-0.17, ro), (0.17, ro), (0.30, ri)):
            pts.append((cx + r * math.cos(a + da * pitch * 1.6), cy + r * math.sin(a + da * pitch * 1.6)))
    return "M" + " L".join(f"{x:.2f},{y:.2f}" for x, y in pts) + "Z"


def accents(tone, c1, c2):
    if tone == "glass":
        return ("#ffffff", "#cfdcf2", c2)
    return (c1, c2, "#ffffff")


def o_folder(tone, c1, c2, d):
    a1, a2, k = accents(tone, c1, c2)
    if tone == "glass":
        back = ("#9cc3f7", "#6a9ee6")
    else:
        back = (mix(a2, "#000000", 0.12), mix(a2, "#000000", 0.28))
    defs = lg("o1", [(0, back[0]), (1, back[1])], d) + lg("o2", [(0, "#ffffff"), (1, "#d8e3f3")]) + lg("o3", [(0, a1), (1, a2)], d) + lg("o4", [(0, "#fff", 0.55), (0.4, "#fff", 0)])
    body = (
        '<path d="M8 28a6 6 0 0 1 6-6h22a6 6 0 0 1 4.5 2l4 4.5H86a6 6 0 0 1 6 6V74a6 6 0 0 1-6 6H14a6 6 0 0 1-6-6z" fill="url(#o1)"/>'
        + ('<rect x="21" y="23.5" width="58" height="30" rx="3" fill="#cfe0f7"/>' if tone == "color" else "")
        + '<rect x="14" y="29" width="72" height="30" rx="3" fill="url(#o2)"/>'
        '<path d="M8 41a6 6 0 0 1 6-6h72a6 6 0 0 1 6 6v33a6 6 0 0 1-6 6H14a6 6 0 0 1-6-6z" fill="url(#o3)"/>'
        '<path d="M8 41a6 6 0 0 1 6-6h72a6 6 0 0 1 6 6v33a6 6 0 0 1-6 6H14a6 6 0 0 1-6-6z" fill="url(#o4)"/>'
        '<path d="M14.5 35.8h71" stroke="#fff" stroke-opacity="0.85" stroke-width="1.1" stroke-linecap="round"/>'
        '<path d="M14 79.2h72" stroke="#000" stroke-opacity="0.18" stroke-width="1.2" stroke-linecap="round"/>'
    )
    sil = '<path d="M8 28a6 6 0 0 1 6-6h22a6 6 0 0 1 4.5 2l4 4.5H86a6 6 0 0 1 6 6V74a6 6 0 0 1-6 6H14a6 6 0 0 1-6-6z" fill="S"/>'
    return defs, body, sil


def o_terminal(tone, c1, c2, d):
    defs = (
        lg("o1", [(0, "#46464b"), (0.5, "#26262a"), (1, "#141416")], d)
        + lg("o2", [(0, "#fff", 0.2), (1, "#fff", 0.03)])
        + lg("o3", [(0, "#f2f3f6"), (1, "#b9bcc6")], DD)
    )
    body = (
        '<rect x="8" y="16" width="84" height="68" rx="12" fill="url(#o1)"/>'
        '<path d="M8 30v-2a12 12 0 0 1 12-12h60a12 12 0 0 1 12 12v2z" fill="url(#o2)"/>'
        '<circle cx="19" cy="23" r="2.2" fill="#fff" fill-opacity="0.28"/><circle cx="26.5" cy="23" r="2.2" fill="#fff" fill-opacity="0.28"/><circle cx="34" cy="23" r="2.2" fill="#fff" fill-opacity="0.28"/>'
        '<path d="M26 45l13 9.5-13 9.5" fill="none" stroke="url(#o3)" stroke-width="5.4" stroke-linecap="round" stroke-linejoin="round"/>'
        '<path d="M46 66h20" fill="none" stroke="url(#o3)" stroke-width="5.4" stroke-linecap="round"/>'
        '<rect x="8.5" y="16.5" width="83" height="67" rx="11.5" fill="none" stroke="#fff" stroke-opacity="0.32"/>'
    )
    sil = '<rect x="8" y="16" width="84" height="68" rx="12" fill="S"/>'
    return defs, body, sil


def o_gear(tone, c1, c2, d):
    g = gearp(50, 50, 41, 32, 10)
    defs = (
        lg("o1", [(0, "#c9ced8"), (0.35, "#8b93a3"), (0.62, "#5d6472"), (1, "#a4abb8")], d)
        + lg("o2", [(0, "#2b2f3b"), (1, "#6a7283")])
        + lg("o3", [(0, "#fff", 0.9), (1, "#fff", 0.1)])
        + rg("o4", [(0, "#e8ebf1"), (1, "#8a92a2")], 0.4, 0.35, 0.8)
    )
    body = (
        f'<path d="{g}" fill="url(#o1)"/>'
        f'<path d="{g}" fill="none" stroke="url(#o3)" stroke-width="1.2" stroke-linejoin="round"/>'
        '<circle cx="50" cy="50" r="25" fill="url(#o4)"/>'
        '<circle cx="50" cy="50" r="25" fill="none" stroke="#fff" stroke-opacity="0.7" stroke-width="1.2"/>'
        '<circle cx="50" cy="50" r="13.5" fill="url(#o2)"/>'
        '<circle cx="50" cy="50" r="13.5" fill="none" stroke="#000" stroke-opacity="0.35" stroke-width="1.4"/>'
        '<path d="M38 58a13.5 13.5 0 0 0 24 0" fill="none" stroke="#fff" stroke-opacity="0.35" stroke-width="1.2"/>'
    )
    return defs, body, f'<path d="{g}" fill="S"/>'


def o_editor(tone, c1, c2, d):
    defs = (
        lg("o1", [(0, "#ffffff"), (1, "#dfe6f2")])
        + lg("o2", [(0, "#ffd54a"), (0.5, "#f5a81c"), (1, "#d9840a")], "x1=\"0\" y1=\"0\" x2=\"1\" y2=\"0\"")
        + lg("o3", [(0, "#ff9db8"), (1, "#e0507a")])
        + lg("o4", [(0, "#d7dbe3"), (0.5, "#fbfcfe"), (1, "#a4abb8")], "x1=\"0\" y1=\"0\" x2=\"1\" y2=\"0\"")
    )
    lines = "".join(f'<path d="M26 {y}h{w}" stroke="#b6bfd2" stroke-width="3.4" stroke-linecap="round"/>' for y, w in ((30, 40), (42, 34), (54, 40), (66, 22)))
    body = (
        '<rect x="14" y="10" width="58" height="78" rx="7" fill="url(#o1)"/>'
        '<rect x="14.5" y="10.5" width="57" height="77" rx="6.5" fill="none" stroke="#fff" stroke-opacity="0.9"/>'
        + lines
        + '<g transform="rotate(36 66 58)">'
        '<rect x="60" y="22" width="14" height="46" fill="url(#o2)"/>'
        '<path d="M60 68h14l-7 16z" fill="#f0cfa0"/><path d="M64.2 77.4h5.6L67 84z" fill="#2d3040"/>'
        '<rect x="60" y="22" width="14" height="6" fill="url(#o4)"/>'
        '<path d="M60 22v-3a7 7 0 0 1 14 0v3z" fill="url(#o3)"/>'
        '<path d="M62 30v36" stroke="#fff" stroke-opacity="0.45" stroke-width="2"/></g>'
    )
    return defs, body, '<rect x="14" y="10" width="58" height="78" rx="7" fill="S"/>'


def o_bag(tone, c1, c2, d):
    a1, a2, k = accents(tone, c1, c2)
    defs = lg("o1", [(0, a1), (1, a2)], d) + lg("o2", [(0, "#fff", 0.6), (0.5, "#fff", 0)])
    kk = c2 if tone == "glass" else "#ffffff"
    body = (
        f'<path d="M36 40V30a14 14 0 0 1 28 0v10" fill="none" stroke="{kk}" stroke-width="5.2" stroke-linecap="round"/>'
        '<path d="M22 36h56l6 48a5 5 0 0 1-5 5.6H21a5 5 0 0 1-5-5.6z" fill="url(#o1)"/>'
        '<path d="M22 36h56l6 48a5 5 0 0 1-5 5.6H21a5 5 0 0 1-5-5.6z" fill="url(#o2)"/>'
        f'<path d="M50 52l4 8.4 9.2 1.2-6.7 6.4 1.7 9.2-8.2-4.4-8.2 4.4 1.7-9.2-6.7-6.4 9.2-1.2z" fill="{kk}" fill-opacity="0.92"/>'
        '<path d="M23 37h54" stroke="#fff" stroke-opacity="0.8" stroke-width="1.1" stroke-linecap="round"/>'
    )
    return defs, body, '<path d="M22 36h56l6 48a5 5 0 0 1-5 5.6H21a5 5 0 0 1-5-5.6z" fill="S"/>'


def o_photo(tone, c1, c2, d):
    defs = (
        lg("o1", [(0, "#ffffff"), (1, "#dfe6f2")])
        + lg("o2", [(0, "#8fdcff"), (1, "#3b86e6")])
        + lg("o3", [(0, "#ffe27a"), (1, "#ff9a2a")], DD)
        + lg("o4", [(0, "#7ee39a"), (1, "#1c9f55")])
        + lg("o5", [(0, "#3fb87a"), (1, "#0f7a45")])
        + '<clipPath id="c1"><rect x="16" y="22" width="68" height="56" rx="6"/></clipPath>'
    )
    body = (
        '<rect x="10" y="16" width="80" height="68" rx="10" fill="url(#o1)"/>'
        '<rect x="16" y="22" width="68" height="56" rx="6" fill="url(#o2)"/>'
        '<g clip-path="url(#c1)"><circle cx="66" cy="38" r="8" fill="url(#o3)"/>'
        '<path d="M10 82L38 46l14 18 8-9 28 27z" fill="url(#o5)"/><path d="M10 84L30 60l14 14 12-10 34 22z" fill="url(#o4)"/></g>'
        '<rect x="16.5" y="22.5" width="67" height="55" rx="5.5" fill="none" stroke="#000" stroke-opacity="0.18"/>'
    )
    return defs, body, '<rect x="10" y="16" width="80" height="68" rx="10" fill="S"/>'


def o_book(tone, c1, c2, d):
    a1, a2, k = accents(tone, c1, c2)
    cov = (a1, a2) if tone != "glass" else ("#ffffff", "#d3def2")
    defs = lg("o1", [(0, cov[0]), (1, cov[1])], d) + lg("o2", [(0, "#f9f5ea"), (1, "#e2dccb")]) + lg("o3", [(0, "#000", 0.22), (1, "#000", 0)], "x1=\"0\" y1=\"0\" x2=\"1\" y2=\"0\"")
    rib = c2 if tone == "glass" else "#ffffff"
    body = (
        '<rect x="20" y="14" width="66" height="74" rx="7" fill="url(#o2)"/>'
        '<rect x="14" y="10" width="64" height="76" rx="7" fill="url(#o1)"/>'
        '<rect x="14" y="10" width="9" height="76" rx="4" fill="url(#o3)"/>'
        f'<path d="M56 10v28l7-6 7 6V10z" fill="{rib}" fill-opacity="0.95"/>'
        f'<path d="M26 54h38M26 64h30" stroke="{rib}" stroke-opacity="0.8" stroke-width="3.4" stroke-linecap="round"/>'
        '<rect x="14.5" y="10.5" width="63" height="75" rx="6.5" fill="none" stroke="#fff" stroke-opacity="0.55"/>'
    )
    return defs, body, '<rect x="14" y="10" width="72" height="78" rx="7" fill="S"/>'


def o_archive(tone, c1, c2, d):
    a1, a2, k = accents(tone, c1, c2)
    defs = lg("o1", [(0, a1), (1, a2)], d) + lg("o2", [(0, mix(a1, "#000000", 0.1)), (1, mix(a2, "#000000", 0.18))])
    kk = c2 if tone == "glass" else "#ffffff"
    body = (
        '<path d="M15 40h70v40a8 8 0 0 1-8 8H23a8 8 0 0 1-8-8z" fill="url(#o2)"/>'
        '<rect x="8" y="18" width="84" height="26" rx="7" fill="url(#o1)"/>'
        '<path d="M14 21.2h72" stroke="#fff" stroke-opacity="0.85" stroke-width="1.1" stroke-linecap="round"/>'
        f'<rect x="36" y="54" width="28" height="9" rx="4.5" fill="{kk}" fill-opacity="0.88"/>'
        '<path d="M15 44h70" stroke="#000" stroke-opacity="0.18" stroke-width="1.4"/>'
    )
    return defs, body, '<path d="M8 25a7 7 0 0 1 7-7h70a7 7 0 0 1 7 7v19h-7v36a8 8 0 0 1-8 8H23a8 8 0 0 1-8-8V44H8z" fill="S"/>'


def o_camera(tone, c1, c2, d):
    defs = (
        lg("o1", [(0, "#9097a8"), (0.5, "#4a4f60"), (1, "#252833")], d)
        + lg("o2", [(0, "#5b6173"), (1, "#1a1c25")])
        + rg("o3", [(0, "#8fc0ff"), (0.3, "#2f55b8"), (0.7, "#0d1a52"), (1, "#05071a")], 0.38, 0.32, 0.75)
        + lg("o4", [(0, "#fff", 0.7), (1, "#fff", 0.05)])
    )
    body = (
        '<path d="M30 28l5-10h30l5 10z" fill="url(#o1)"/>'
        '<rect x="8" y="26" width="84" height="56" rx="12" fill="url(#o1)"/>'
        '<rect x="8.5" y="26.5" width="83" height="55" rx="11.5" fill="none" stroke="#fff" stroke-opacity="0.4"/>'
        '<circle cx="50" cy="55" r="23" fill="url(#o2)"/><circle cx="50" cy="55" r="18" fill="url(#o3)"/>'
        '<circle cx="50" cy="55" r="18" fill="none" stroke="#fff" stroke-opacity="0.25" stroke-width="1"/>'
        '<ellipse cx="43.5" cy="47.5" rx="6.5" ry="4.4" fill="url(#o4)" transform="rotate(-30 43.5 47.5)"/>'
        '<circle cx="80" cy="36" r="3.2" fill="#ffd54a"/>'
    )
    return defs, body, '<rect x="8" y="18" width="84" height="64" rx="12" fill="S"/>'


def o_calc(tone, c1, c2, d):
    defs = (
        lg("o1", [(0, "#5a5f70"), (1, "#1f222c")], d)
        + lg("o2", [(0, "#d3ecdc"), (1, "#8fbfa3")])
        + lg("o3", [(0, "#8b91a3"), (1, "#5a6074")])
        + lg("o4", [(0, "#ffc25a"), (1, "#f77f1b")])
    )
    keys = ""
    for r, y in enumerate((44, 57, 70)):
        for c, x in enumerate((27, 44, 61)):
            keys += f'<rect x="{x}" y="{y}" width="12" height="10" rx="3.2" fill="url(#o{4 if c == 2 else 3})"/>'
    body = (
        '<rect x="18" y="8" width="64" height="84" rx="11" fill="url(#o1)"/>'
        '<rect x="18.5" y="8.5" width="63" height="83" rx="10.5" fill="none" stroke="#fff" stroke-opacity="0.3"/>'
        '<rect x="26" y="16" width="48" height="20" rx="4.5" fill="url(#o2)"/>'
        '<path d="M64 26h6M60 26l-3 0" stroke="#3d6b52" stroke-width="3" stroke-linecap="round"/>'
        + keys
    )
    return defs, body, '<rect x="18" y="8" width="64" height="84" rx="11" fill="S"/>'


def o_monitor(tone, c1, c2, d, pulse=True):
    defs = (
        lg("o1", [(0, "#eef1f7"), (1, "#a3abbb")], d)
        + lg("o2", [(0, mix(c1, "#ffffff", 0.2)), (1, c2)])
        + lg("o3", [(0, "#fff", 0.5), (0.5, "#fff", 0)], DD)
        + lg("o4", [(0, "#d3d8e2"), (1, "#8a92a3")])
    )
    inner = (
        '<path d="M18 46h12l6-15 10 30 8-21 5 6h13" fill="none" stroke="#fff" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"/>'
        if pulse
        else ""
    )
    body = (
        '<rect x="37" y="66" width="26" height="12" fill="url(#o4)"/>'
        '<rect x="26" y="76" width="48" height="7" rx="3.5" fill="url(#o4)"/>'
        '<rect x="8" y="14" width="84" height="56" rx="8" fill="url(#o1)"/>'
        '<rect x="13" y="19" width="74" height="46" rx="4" fill="url(#o2)"/>'
        '<rect x="13" y="19" width="74" height="46" rx="4" fill="url(#o3)"/>'
        + inner
    )
    return defs, body, '<rect x="8" y="14" width="84" height="56" rx="8" fill="S"/><rect x="37" y="66" width="26" height="12" fill="S"/><rect x="26" y="76" width="48" height="7" rx="3.5" fill="S"/>'


def o_display(tone, c1, c2, d):
    return o_monitor(tone, c1, c2, d, False)


def o_mail(tone, c1, c2, d):
    a1, a2, k = accents(tone, c1, c2)
    defs = lg("o1", [(0, a1), (1, a2)], d) + lg("o2", [(0, "#fff", 0.55), (1, "#fff", 0.05)])
    kk = c2 if tone == "glass" else "#ffffff"
    body = (
        '<rect x="8" y="22" width="84" height="58" rx="10" fill="url(#o1)"/>'
        '<path d="M12 28l38 28 38-28" fill="url(#o2)" stroke="none"/>'
        f'<path d="M10 30l40 28 40-28" fill="none" stroke="{kk}" stroke-opacity="0.9" stroke-width="3.6" stroke-linecap="round" stroke-linejoin="round"/>'
        '<rect x="8.5" y="22.5" width="83" height="57" rx="9.5" fill="none" stroke="#fff" stroke-opacity="0.5"/>'
    )
    return defs, body, '<rect x="8" y="22" width="84" height="58" rx="10" fill="S"/>'


def o_calendar(tone, c1, c2, d):
    defs = lg("o1", [(0, "#ffffff"), (1, "#e1e7f2")]) + lg("o2", [(0, "#ff7a72"), (1, "#e0343c")]) + lg("o3", [(0, "#d3dae8"), (1, "#aeb8cc")])
    dots = "".join(f'<rect x="{x}" y="{y}" width="9" height="8" rx="2.6" fill="url(#o{2 if (x, y) == (47, 58) else 3})"/>' for y in (44, 58, 72) for x in (23, 47, 69) if True)
    body = (
        '<rect x="13" y="12" width="74" height="76" rx="10" fill="url(#o1)"/>'
        '<path d="M13 36V22a10 10 0 0 1 10-10h54a10 10 0 0 1 10 10v14z" fill="url(#o2)"/>'
        '<circle cx="30" cy="12" r="3.6" fill="#8b91a3"/><circle cx="70" cy="12" r="3.6" fill="#8b91a3"/>'
        + dots
        + '<rect x="13.5" y="12.5" width="73" height="75" rx="9.5" fill="none" stroke="#fff" stroke-opacity="0.8"/>'
    )
    return defs, body, '<rect x="13" y="12" width="74" height="76" rx="10" fill="S"/>'


def o_music(tone, c1, c2, d):
    a1, a2, k = accents(tone, c1, c2)
    defs = lg("o1", [(0, a1), (1, a2)], d)
    body = (
        '<path d="M40 70V26l38-9v44" fill="none" stroke="url(#o1)" stroke-width="7" stroke-linejoin="round" stroke-linecap="round"/>'
        '<path d="M40 38l38-9" stroke="url(#o1)" stroke-width="7" stroke-linecap="round"/>'
        '<ellipse cx="32" cy="72" rx="12" ry="9.5" fill="url(#o1)" transform="rotate(-18 32 72)"/>'
        '<ellipse cx="70" cy="64" rx="12" ry="9.5" fill="url(#o1)" transform="rotate(-18 70 64)"/>'
    )
    return defs, body, '<path d="M40 70V26l38-9v44" fill="none" stroke="S" stroke-width="7" stroke-linejoin="round" stroke-linecap="round"/><ellipse cx="32" cy="72" rx="12" ry="9.5" fill="S" transform="rotate(-18 32 72)"/><ellipse cx="70" cy="64" rx="12" ry="9.5" fill="S" transform="rotate(-18 70 64)"/>'


def o_video(tone, c1, c2, d):
    a1, a2, k = accents(tone, c1, c2)
    defs = lg("o1", [(0, a1), (1, a2)], d) + lg("o2", [(0, "#fff", 0.6), (0.5, "#fff", 0)])
    kk = c2 if tone == "glass" else "#ffffff"
    body = (
        '<rect x="8" y="20" width="84" height="60" rx="13" fill="url(#o1)"/>'
        '<rect x="8" y="20" width="84" height="60" rx="13" fill="url(#o2)"/>'
        f'<path d="M42 35v30l24-15z" fill="{kk}" stroke="{kk}" stroke-width="5" stroke-linejoin="round"/>'
    )
    return defs, body, '<rect x="8" y="20" width="84" height="60" rx="13" fill="S"/>'


def o_search(tone, c1, c2, d):
    defs = (
        rg("o1", [(0, "#ffffff", 0.75), (0.7, "#cfe6ff", 0.25), (1, "#7fb4f0", 0.45)], 0.35, 0.3, 0.8)
        + lg("o2", [(0, "#f4f6fa"), (0.5, "#9aa2b2"), (1, "#d8dce4")], "x1=\"0\" y1=\"0\" x2=\"1\" y2=\"0\"")
        + lg("o3", [(0, "#fff"), (1, "#8ab4ee")], DD)
    )
    body = (
        '<path d="M64 64l22 22" stroke="url(#o2)" stroke-width="12" stroke-linecap="round"/>'
        '<circle cx="42" cy="42" r="28" fill="url(#o1)"/>'
        '<circle cx="42" cy="42" r="28" fill="none" stroke="url(#o3)" stroke-width="6"/>'
        '<path d="M26 34a18 18 0 0 1 14-12" fill="none" stroke="#fff" stroke-opacity="0.9" stroke-width="3.4" stroke-linecap="round"/>'
    )
    return defs, body, '<circle cx="42" cy="42" r="31" fill="S"/><path d="M64 64l22 22" stroke="S" stroke-width="12" stroke-linecap="round"/>'


def o_globe(tone, c1, c2, d):
    defs = rg("o1", [(0, "#8fd3ff"), (0.6, "#2f8cf0"), (1, "#1649b5")], 0.35, 0.3, 0.85) + rg("o2", [(0, "#fff", 0.5), (1, "#fff", 0)], 0.3, 0.2, 0.5)
    body = (
        '<circle cx="50" cy="50" r="38" fill="url(#o1)"/>'
        '<path d="M50 12c-18 20-18 56 0 76M50 12c18 20 18 56 0 76M12 50h76M18 30h64M18 70h64" fill="none" stroke="#fff" stroke-opacity="0.65" stroke-width="2.4"/>'
        '<circle cx="50" cy="50" r="38" fill="url(#o2)"/>'
        '<circle cx="50" cy="50" r="37.5" fill="none" stroke="#fff" stroke-opacity="0.5"/>'
    )
    return defs, body, '<circle cx="50" cy="50" r="38" fill="S"/>'


OBJECTS = {
    "folder": o_folder, "folderfill": o_folder, "terminal": o_terminal, "gear": o_gear, "pencilpage": o_editor,
    "bag": o_bag, "image": o_photo, "book": o_book, "archive": o_archive, "screenshot": o_camera, "camera": o_camera,
    "calc": o_calc, "pulse": o_monitor, "display": o_display, "mail": o_mail, "calendar": o_calendar,
    "music": o_music, "video": o_video, "search": o_search, "globe": o_globe,
}


def shadow_stack(sil, offs, scale=1.0):
    out = ""
    for dy, op, e in offs:
        s = sil.replace('fill="S"', f'fill="#000" fill-opacity="{op}"').replace('stroke="S"', f'stroke="#000" stroke-opacity="{op}"')
        out += f'<g transform="translate(0 {dy})">{s}</g>'
    return out


def object_group(glyph, tone, c1, c2, d, shadow=True):
    defs, body, sil = OBJECTS[glyph](tone, c1, c2, d)
    sh = shadow_stack(sil, ((7, 0.06, 0), (5, 0.08, 0), (3, 0.12, 0), (1.5, 0.16, 0))) if shadow else ""
    return defs, sh + body


def mac_tile(glyph, pal, colors, glyph_fn, brand, dark=False):
    c1, c2 = colors[pal]
    mid = mix(c1, c2, 0.5)
    sq = "M" + " L".join(
        f"{512 + 412 * math.copysign(abs(math.cos(2 * math.pi * i / 220)) ** 0.4, math.cos(2 * math.pi * i / 220)):.1f},{512 + 412 * math.copysign(abs(math.sin(2 * math.pi * i / 220)) ** 0.4, math.sin(2 * math.pi * i / 220)):.1f}"
        for i in range(220)
    ) + "Z"
    sq_in = sq
    shadows = "".join(
        f'<use xlink:href="#sq" transform="translate(512 {512 + dy}) scale({s}) translate(-512 -512)" fill="#000" fill-opacity="{o}"/>'
        for s, dy, o in ((1.04, 34, 0.035), (1.026, 27, 0.045), (1.014, 20, 0.06), (1.004, 13, 0.09), (0.994, 7, 0.13))
    )
    if glyph in OBJECTS:
        odefs, obody = object_group(glyph, "glass", c1, c2, DV)
        fx = c2
        inner = f'<g transform="translate(512 512) scale(5.7) translate(-50 -50)">{obody}</g>'
        gdefs = odefs
    else:
        gdefs, inner = glyph_fn(glyph, dark, brand)
    return f'''<svg {XL} width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
<path id="sq" d="{sq}"/>
{lg("b", [(0, mix(c1, "#ffffff", 0.18)), (0.45, c1), (0.78, mix(c1, c2, 0.55)), (1, c2)])}
{lg("d", [(0.55, "#000", 0), (1, "#000", 0.28)])}
{rg("r", [(0, "#fff", 0.5), (0.55, "#fff", 0.07), (1, "#fff", 0)], 0.26, 0.05, 0.95)}
{rg("u", [(0, "#fff", 0.22), (1, "#fff", 0)], 0.5, 1.0, 0.6)}
{lg("h", [(0, "#fff", 0.4), (0.4, "#fff", 0)])}
{lg("e", [(0, "#fff", 0.9), (0.28, "#fff", 0.14), (0.72, "#fff", 0), (1, "#fff", 0.32)])}
{gdefs}
</defs>
{shadows}
<use xlink:href="#sq" fill="url(#b)"/>
<use xlink:href="#sq" fill="url(#d)"/>
<use xlink:href="#sq" fill="url(#r)"/>
<use xlink:href="#sq" fill="url(#u)"/>
<use xlink:href="#sq" fill="url(#h)"/>
<use xlink:href="#sq" fill="none" stroke="url(#e)" stroke-width="7" transform="translate(512 512) scale(0.988) translate(-512 -512)"/>
<use xlink:href="#sq" fill="none" stroke="#000" stroke-opacity="0.3" stroke-width="3"/>
{inner}
</svg>
'''


def glass_glyph(markup):
    def fn(glyph, dk, br):
        g = markup(glyph, "#ffffff")
        gb = markup(glyph, "#000000")
        gd = markup(glyph, "url(#gk)") if dk else None
        ga = 'fill="none" stroke-linecap="round" stroke-linejoin="round"'
        t = "translate(512 512) scale(17.6) translate(-12 -12)"
        defs = lg("gw", [(0, "#ffffff"), (1, "#dce8ff", 0.95)])
        if dk:
            defs += f'<linearGradient id="gk" gradientUnits="userSpaceOnUse" x1="3" y1="3" x2="21" y2="21"><stop offset="0" stop-color="{br[0]}"/><stop offset="1" stop-color="{br[1]}"/></linearGradient>'
        main = gd if dk else g
        body = (
            f'<g transform="{t} translate(0 1.1)" {ga} stroke="#001030" stroke-opacity="0.14" stroke-width="3.8">{gb}</g>'
            f'<g transform="{t} translate(0 0.55)" {ga} stroke="#001030" stroke-opacity="0.2" stroke-width="3.2">{gb}</g>'
            + ('' if dk else f'<g transform="{t}" {ga} stroke="#fff" stroke-opacity="0.3" stroke-width="3.5">{g}</g>')
            + f'<g transform="{t}" {ga} stroke="{"url(#gk)" if dk else "url(#gw)"}" stroke-width="1.8">{main}</g>'
            + ('' if dk else f'<g transform="{t} translate(0 -0.18)" {ga} stroke="#fff" stroke-opacity="0.5" stroke-width="0.5">{g}</g>')
        )
        return defs, body

    return fn


def fluent_app(glyph, pal, colors, markup):
    c1, c2 = colors[pal]
    if pal in ("night", "slate", "graphite"):
        c1, c2 = mix(c2, "#ffffff", 0.75), mix(c2, "#ffffff", 0.4)
    if glyph in OBJECTS:
        defs, body = object_group(glyph, "color", mix(c1, "#ffffff", 0.1), c2, DD)
        inner = f'<g transform="translate(-9.6 -9.6) scale(1.19)">{body}</g>'
    else:
        g = markup(glyph, "url(#gg)")
        gb = markup(glyph, "#000")
        gl = markup(glyph, "#fff")
        defs = f'<linearGradient id="gg" gradientUnits="userSpaceOnUse" x1="3" y1="3" x2="21" y2="21"><stop offset="0" stop-color="{mix(c1, "#ffffff", 0.2)}"/><stop offset="1" stop-color="{c2}"/></linearGradient>'
        ga = 'fill="none" stroke-linecap="round" stroke-linejoin="round"'
        t = "translate(64 64) scale(4.8) translate(-12 -12)"
        inner = (
            f'<g transform="{t} translate(0.3 0.9)" {ga} stroke="#000" stroke-opacity="0.22" stroke-width="3.3">{gb}</g>'
            f'<g transform="{t}" {ga} stroke="url(#gg)" stroke-width="3.1">{g}</g>'
            f'<g transform="{t} translate(-0.25 -0.25)" {ga} stroke="#fff" stroke-opacity="0.5" stroke-width="0.9">{gl}</g>'
        )
    return f'<svg {XL} width="128" height="128" viewBox="0 0 128 128"><defs>{defs}</defs>{inner}</svg>\n'


FLUENT_ACCENT = {"page": "#1f6fd6", "download": "#0d9f8f", "image": "#0e93c9", "music": "#f0543c", "video": "#8452e8", "desktop": "#1f6fd6", "home": "#1f6fd6", "share": "#1f6fd6", "globe": "#1f6fd6", "history": "#0d9f8f", "newpage": "#5b6f94", "cloud": "#1f6fd6", "star": "#f0543c", "lock": "#5b6f94", "terminal": "#4b5470", "gamepad": "#8452e8"}
MAC_FOLDER = dict(b1="#5fb4f6", b2="#2d73cc", f1="#9fdcff", f2="#52b2f8", f3="#2f8ae8", emb="#2b73c8")


def tint_folder(c1, c2):
    return dict(b1=mix(c1, "#000000", 0.1), b2=mix(c2, "#000000", 0.1), f1=mix(c1, "#ffffff", 0.45), f2=c1, f3=mix(c1, c2, 0.5), emb=mix(c2, "#000000", 0.15))


def folder_svg(mode, glyph, markup, cols=None, accent=None):
    if mode == "mac":
        cols = cols or MAC_FOLDER
        defs, body, sil = o_folder("glass", "#8fd8ff", "#2f86e0", DV)
        defs = lg("o1", [(0, cols["b1"]), (1, cols["b2"])]) + lg("o2", [(0, "#ffffff"), (1, "#d8e3f3")]) + lg("o3", [(0, cols["f1"]), (0.55, cols["f2"]), (1, cols["f3"])]) + lg("o4", [(0, "#fff", 0.5), (0.35, "#fff", 0)])
    else:
        defs, body, sil = o_folder("color", "#ffe073", "#f4a51c", DD)
        defs = lg("o1", [(0, "#eeb12f"), (1, "#c98410")]) + lg("o2", [(0, "#ffffff"), (1, "#eef3fb")]) + lg("o3", [(0, "#ffd96a"), (0.55, "#ffd35c"), (1, "#f5b73b")], DD) + lg("o4", [(0, "#fff", 0.55), (0.35, "#fff", 0)])
    sh = shadow_stack(sil, ((7, 0.05, 0), (5, 0.07, 0), (3, 0.1, 0), (1.5, 0.15, 0)))
    gl = ""
    if glyph:
        t = "translate(50 60.8) scale(0.66) translate(-12 -12)"
        ga = 'fill="none" stroke-linecap="round" stroke-linejoin="round"'
        if mode == "mac":
            hi = markup(glyph, "#ffffff")
            lo = markup(glyph, cols["emb"])
            gl = f'<g transform="{t} translate(0 0.9)" {ga} stroke="#fff" stroke-opacity="0.55" stroke-width="2.7">{hi}</g><g transform="{t}" {ga} stroke="{cols["emb"]}" stroke-opacity="0.8" stroke-width="2.7">{lo}</g>'
        else:
            ac = FLUENT_ACCENT.get(glyph, "#2b78e4")
            col = markup(glyph, ac)
            gl = f'<g transform="{t}" {ga} stroke="{ac}" stroke-width="2.9">{col}</g>'
    return f'<svg {XL} width="128" height="128" viewBox="0 0 128 128"><defs>{defs}</defs><g transform="translate(-1 -3.6) scale(1.3)">{sh}{body}{gl}</g></svg>\n'


def page_svg(glyph, c1, c2, markup, tokyo=False):
    g = markup(glyph, "#ffffff")
    body_hi = mix(c1, "#ffffff", 0.15)
    shadows = "".join(
        f'<path d="M26 12a8 8 0 0 1 8-8h40l28 28v84a8 8 0 0 1-8 8H34a8 8 0 0 1-8-8z" transform="translate(0 {dy})" fill="#000" fill-opacity="{o}"/>'
        for dy, o in ((7, 0.05), (5, 0.07), (3, 0.1), (1.5, 0.14))
    )
    return f'''<svg {XL} width="128" height="128" viewBox="0 0 128 128">
<defs>
{lg("p", [(0, "#ffffff"), (0.6, "#f1f4fa"), (1, "#d3dbea")])}
{lg("f", [(0, "#ffffff"), (1, "#aeb9d2")], DD)}
{lg("a", [(0, body_hi), (1, c2)])}
{lg("t", [(0, "#fff", 0.9), (0.3, "#fff", 0)])}
</defs>
{shadows}
<path d="M26 12a8 8 0 0 1 8-8h40l28 28v84a8 8 0 0 1-8 8H34a8 8 0 0 1-8-8z" fill="url(#p)"/>
<path d="M26 12a8 8 0 0 1 8-8h40l28 28v84a8 8 0 0 1-8 8H34a8 8 0 0 1-8-8z" fill="none" stroke="url(#t)" stroke-width="1.4"/>
<path d="M74 4l28 28H82a8 8 0 0 1-8-8z" fill="url(#f)"/>
<path d="M74 4l28 28H82a8 8 0 0 1-8-8z" fill="none" stroke="#7d89a8" stroke-opacity="0.35"/>
<path d="M36 40h34M36 50h26" stroke="#c4cde0" stroke-width="4" stroke-linecap="round"/>
<rect x="36" y="70" width="56" height="34" rx="9" fill="#000" fill-opacity="0.16" transform="translate(0 2)"/>
<rect x="36" y="70" width="56" height="34" rx="9" fill="url(#a)"/>
<rect x="36.5" y="70.5" width="55" height="33" rx="8.5" fill="none" stroke="#fff" stroke-opacity="0.55"/>
<g transform="translate(64 87.7) scale(1.15) translate(-12 -12)" fill="none" stroke="#001030" stroke-opacity="0.25" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round">{markup(glyph, "#001030")}</g>
<g transform="translate(64 87) scale(1.15) translate(-12 -12)" fill="none" stroke="#fff" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">{g}</g>
</svg>
'''
