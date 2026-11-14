import math

from icondesign import DD, DV, OBJECTS, lg, mix, rg


def disc(c1, c2, r=42):
    defs = rg("d1", [(0, mix(c1, "#ffffff", 0.35)), (0.55, c1), (1, c2)], 0.35, 0.25, 0.9) + lg("d2", [(0, "#fff", 0.5), (0.5, "#fff", 0)])
    body = (
        f'<circle cx="50" cy="50" r="{r}" fill="url(#d1)"/>'
        f'<ellipse cx="50" cy="{50 - r * 0.55:.1f}" rx="{r * 0.72:.1f}" ry="{r * 0.4:.1f}" fill="url(#d2)"/>'
        f'<circle cx="50" cy="50" r="{r - 0.5}" fill="none" stroke="#fff" stroke-opacity="0.35"/>'
        f'<circle cx="50" cy="50" r="{r}" fill="none" stroke="#000" stroke-opacity="0.25"/>'
    )
    return defs, body


def sil_disc():
    return '<circle cx="50" cy="50" r="42" fill="S"/>'


def glyph_disc(markup, glyph, c1, c2):
    defs, body = disc(c1, c2)
    g = markup(glyph, "#ffffff")
    gb = markup(glyph, "#000000")
    t = "translate(50 50) scale(2.7) translate(-12 -12)"
    ga = 'fill="none" stroke-linecap="round" stroke-linejoin="round"'
    body += (
        f'<g transform="{t} translate(0 0.6)" {ga} stroke="#000" stroke-opacity="0.3" stroke-width="2.3">{gb}</g>'
        f'<g transform="{t}" {ga} stroke="#fff" stroke-width="2.1">{g}</g>'
    )
    return defs, body, sil_disc()


def o_palette(tone, c1, c2, d):
    defs = lg("p1", [(0, "#e8c48e"), (1, "#a8783c")], d) + lg("p2", [(0, "#fff", 0.45), (0.5, "#fff", 0)])
    dots = "".join(f'<circle cx="{x}" cy="{y}" r="7" fill="{c}"/><circle cx="{x}" cy="{y - 1.5}" r="7" fill="none" stroke="#fff" stroke-opacity="0.45"/>' for x, y, c in ((28, 40, "#c8283f"), (42, 26, "#e0a020"), (60, 26, "#2f9a58"), (74, 40, "#2f7be8")))
    body = (
        '<path d="M50 10C26 10 8 28 8 50s18 40 40 40c8 0 10-6 8-11-3-6 0-12 8-12h8c10 0 20-6 20-18C92 28 74 10 50 10z" fill="url(#p1)"/>'
        '<path d="M50 10C26 10 8 28 8 50s18 40 40 40c8 0 10-6 8-11-3-6 0-12 8-12h8c10 0 20-6 20-18C92 28 74 10 50 10z" fill="url(#p2)"/>'
        '<ellipse cx="34" cy="68" rx="8" ry="6" fill="#3a2a18" fill-opacity="0.55"/>'
        + dots
    )
    return defs, body, '<path d="M50 10C26 10 8 28 8 50s18 40 40 40c8 0 10-6 8-11-3-6 0-12 8-12h8c10 0 20-6 20-18C92 28 74 10 50 10z" fill="S"/>'


def o_fontblock(tone, c1, c2, d):
    defs = lg("f1", [(0, mix(c1, "#ffffff", 0.35)), (1, c2)], d) + lg("f2", [(0, "#fff", 0.45), (0.5, "#fff", 0)])
    big = "M10 82L36 16h8l26 66"
    bar = "M20 60h40"
    body = (
        f'<path d="{big}{bar}" fill="none" stroke="url(#f1)" stroke-width="12" stroke-linejoin="round" stroke-linecap="round"/>'
        f'<path d="{big}{bar}" fill="none" stroke="url(#f2)" stroke-width="12" stroke-linejoin="round" stroke-linecap="round"/>'
        f'<circle cx="82" cy="66" r="12" fill="none" stroke="url(#f1)" stroke-width="9"/><path d="M94 52v28" stroke="url(#f1)" stroke-width="9" stroke-linecap="round"/>'
    )
    return defs, body, f'<path d="{big}{bar}" fill="none" stroke="S" stroke-width="12" stroke-linejoin="round" stroke-linecap="round"/><circle cx="82" cy="66" r="12" fill="none" stroke="S" stroke-width="9"/>'



def o_bell(tone, c1, c2, d):
    defs = lg("b1", [(0, "#f5d27a"), (0.5, "#d99a2a"), (1, "#a86a10")], "x1=\"0\" y1=\"0\" x2=\"1\" y2=\"0\"") + lg("b2", [(0, "#fff", 0.5), (0.5, "#fff", 0)])
    shape = "M50 10c-4 0-6 3-6 6-14 4-22 16-22 32v14L12 74v6h76v-6l-10-12V48c0-16-8-28-22-32 0-3-2-6-6-6z"
    body = f'<path d="{shape}" fill="url(#b1)"/><path d="{shape}" fill="url(#b2)"/><path d="M36 84a14 8 0 0 0 28 0z" fill="#8f5a0e"/><path d="M30 30c4-8 10-12 18-14" fill="none" stroke="#fff" stroke-opacity="0.7" stroke-width="3" stroke-linecap="round"/>'
    return defs, body, f'<path d="{shape}" fill="S"/><path d="M36 84a14 8 0 0 0 28 0z" fill="S"/>'


def o_moon(tone, c1, c2, d):
    defs = lg("m1", [(0, mix(c1, "#ffffff", 0.3)), (1, c2)], d) + lg("m2", [(0, "#fff", 0.45), (0.5, "#fff", 0)], DD)
    shape = "M66 10A42 42 0 1 0 90 62 34 34 0 0 1 66 10z"
    body = f'<path d="{shape}" fill="url(#m1)"/><path d="{shape}" fill="url(#m2)"/><circle cx="72" cy="28" r="3.5" fill="#fff"/><circle cx="84" cy="44" r="2.2" fill="#fff" fill-opacity="0.8"/>'
    return defs, body, f'<path d="{shape}" fill="S"/>'


def o_wifi(tone, c1, c2, d):
    defs, b = disc(c1, c2)
    arcs = "".join(f'<path d="M{50 - r * 0.866:.1f} {66 - r * 0.5:.1f}A{r} {r} 0 0 1 {50 + r * 0.866:.1f} {66 - r * 0.5:.1f}" fill="none" stroke="#fff" stroke-width="6.5" stroke-linecap="round"/>' for r in (14, 26, 38))
    return defs, b + '<g transform="translate(0 -1)">' + arcs + '<circle cx="50" cy="68" r="4.6" fill="#fff"/></g>', sil_disc()


def o_clock(tone, c1, c2, d):
    ticks = "".join(f'<path d="M50 14v{6 if i % 3 == 0 else 3}" stroke="#2a2d38" stroke-width="{2.4 if i % 3 == 0 else 1.4}" stroke-linecap="round" transform="rotate({i * 30} 50 50)"/>' for i in range(12))
    defs = lg("c1", [(0, "#eceff5"), (0.5, "#9aa2b2"), (1, "#dfe3ea")], DD) + rg("c2", [(0, "#ffffff"), (1, "#e3e8f1")], 0.4, 0.3, 0.8)
    body = (
        '<circle cx="50" cy="50" r="42" fill="url(#c1)"/><circle cx="50" cy="50" r="35" fill="url(#c2)"/><circle cx="50" cy="50" r="35" fill="none" stroke="#000" stroke-opacity="0.2"/>'
        + ticks
        + '<path d="M50 50L50 28" stroke="#23262f" stroke-width="4.4" stroke-linecap="round"/><path d="M50 50L66 58" stroke="#23262f" stroke-width="3.6" stroke-linecap="round"/><path d="M50 50L38 66" stroke="#c8283f" stroke-width="1.6" stroke-linecap="round"/><circle cx="50" cy="50" r="3.4" fill="#23262f"/>'
    )
    return defs, body, sil_disc()


def o_battery(tone, c1, c2, d):
    defs = lg("t1", [(0, "#5b5f6c"), (1, "#26282f")], d) + lg("t2", [(0, "#58c27a"), (1, "#1f8a48")]) + lg("t3", [(0, "#fff", 0.35), (0.5, "#fff", 0)])
    body = (
        '<rect x="8" y="28" width="76" height="44" rx="10" fill="url(#t1)"/><rect x="84" y="40" width="9" height="20" rx="3" fill="#8e93a1"/>'
        '<rect x="14" y="34" width="50" height="32" rx="5" fill="url(#t2)"/><rect x="14" y="34" width="50" height="14" rx="5" fill="url(#t3)"/>'
        '<rect x="8.5" y="28.5" width="75" height="43" rx="9.5" fill="none" stroke="#fff" stroke-opacity="0.3"/>'
    )
    return defs, body, '<rect x="8" y="28" width="85" height="44" rx="10" fill="S"/>'


def o_access(tone, c1, c2, d):
    defs, b = disc(c1, c2)
    fig = (
        '<circle cx="50" cy="27" r="6.5" fill="#fff"/><path d="M26 40c16 4 32 4 48 0" fill="none" stroke="#fff" stroke-width="7" stroke-linecap="round"/>'
        '<path d="M50 40v20M50 58L38 78M50 58L62 78" fill="none" stroke="#fff" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/>'
    )
    return defs, b + fig, sil_disc()


def o_lock(tone, c1, c2, d):
    defs = lg("l1", [(0, "#f3d17a"), (0.5, "#d49a28"), (1, "#9a620e")], d) + lg("l2", [(0, "#e4e8f0"), (0.5, "#8f97a6"), (1, "#c6ccd8")], "x1=\"0\" y1=\"0\" x2=\"1\" y2=\"0\"") + lg("l3", [(0, "#fff", 0.45), (0.5, "#fff", 0)])
    body = (
        '<path d="M30 46V32a20 20 0 0 1 40 0v14" fill="none" stroke="#000" stroke-opacity="0.25" stroke-width="10" transform="translate(0 1.5)"/>'
        '<path d="M30 46V32a20 20 0 0 1 40 0v14" fill="none" stroke="url(#l2)" stroke-width="9" stroke-linecap="round"/>'
        '<rect x="16" y="44" width="68" height="46" rx="10" fill="url(#l1)"/><rect x="16" y="44" width="68" height="46" rx="10" fill="url(#l3)"/>'
        '<circle cx="50" cy="63" r="6" fill="#3a2406"/><path d="M47 66h6l2 12h-10z" fill="#3a2406"/>'
        '<rect x="16.5" y="44.5" width="67" height="45" rx="9.5" fill="none" stroke="#fff" stroke-opacity="0.5"/>'
    )
    return defs, body, '<rect x="16" y="18" width="68" height="72" rx="14" fill="S"/>'


def o_chip(tone, c1, c2, d):
    pins = "".join(f'<rect x="{x}" y="8" width="5" height="12" rx="2" fill="url(#h4)"/><rect x="{x}" y="80" width="5" height="12" rx="2" fill="url(#h4)"/><rect x="8" y="{x}" width="12" height="5" rx="2" fill="url(#h4)"/><rect x="80" y="{x}" width="12" height="5" rx="2" fill="url(#h4)"/>' for x in (28, 38, 48, 58, 68))
    defs = lg("h1", [(0, mix(c1, "#ffffff", 0.3)), (1, c2)], d) + lg("h2", [(0, "#f4f6fa"), (1, "#aab2c2")], d) + lg("h3", [(0, "#fff", 0.45), (0.5, "#fff", 0)]) + lg("h4", [(0, "#f1d98a"), (1, "#c49a3a")], "x1=\"0\" y1=\"0\" x2=\"1\" y2=\"1\"")
    body = (
        pins + '<rect x="18" y="18" width="64" height="64" rx="10" fill="url(#h1)"/><rect x="18" y="18" width="64" height="64" rx="10" fill="url(#h3)"/>'
        '<rect x="32" y="32" width="36" height="36" rx="6" fill="url(#h2)"/><rect x="38" y="38" width="24" height="24" rx="4" fill="none" stroke="#fff" stroke-opacity="0.8" stroke-width="2"/>'
        '<rect x="18.5" y="18.5" width="63" height="63" rx="9.5" fill="none" stroke="#fff" stroke-opacity="0.45"/>'
    )
    return defs, body, '<rect x="18" y="18" width="64" height="64" rx="10" fill="S"/>'



def o_layout(tone, c1, c2, d):
    defs = lg("w2", [(0, mix(c1, "#ffffff", 0.3)), (1, c2)], d) + lg("w3", [(0, "#f1f3f8"), (1, "#a9b1c2")], d) + lg("w4", [(0, "#fff", 0.45), (0.5, "#fff", 0)])
    body = (
        '<rect x="8" y="16" width="40" height="68" rx="8" fill="url(#w2)"/><rect x="8" y="16" width="40" height="68" rx="8" fill="url(#w4)"/>'
        '<rect x="54" y="16" width="38" height="31" rx="8" fill="url(#w3)"/><rect x="54" y="53" width="38" height="31" rx="8" fill="url(#w3)"/>'
        '<rect x="8.5" y="16.5" width="39" height="67" rx="7.5" fill="none" stroke="#fff" stroke-opacity="0.5"/>'
    )
    return defs, body, '<rect x="8" y="16" width="40" height="68" rx="8" fill="S"/><rect x="54" y="16" width="38" height="31" rx="8" fill="S"/><rect x="54" y="53" width="38" height="31" rx="8" fill="S"/>'



def o_dock(tone, c1, c2, d):
    cols = (("#5aa2ff", "#1f5fd0"), ("#ffa24a", "#d6561a"), ("#5fd08a", "#1f8a48"), ("#b97af0", "#7a3cc2"))
    pos = ((10, 12), (54, 12), (10, 56), (54, 56))
    defs = lg("k2", [(0, "#fff", 0.45), (0.5, "#fff", 0)])
    for i, (a, b) in enumerate(cols):
        defs += lg(f"kc{i}", [(0, a), (1, b)], d)
    body = "".join(f'<rect x="{x}" y="{y}" width="36" height="36" rx="11" fill="url(#kc{i})"/><rect x="{x}" y="{y}" width="36" height="36" rx="11" fill="url(#k2)"/><rect x="{x + 0.5}" y="{y + 0.5}" width="35" height="35" rx="10.5" fill="none" stroke="#fff" stroke-opacity="0.45"/>' for i, (x, y) in enumerate(pos))
    return defs, body, "".join(f'<rect x="{x}" y="{y}" width="36" height="36" rx="11" fill="S"/>' for x, y in pos)

def o_keyboard(tone, c1, c2, d):
    keys = "".join(f'<rect x="{14 + c * 13}" y="{32 + r * 13}" width="10" height="9" rx="2.5" fill="url(#y2)"/>' for r in range(3) for c in range(6))
    defs = lg("y1", [(0, "#5a5d68"), (1, "#25272e")], d) + lg("y2", [(0, "#eceff5"), (1, "#aeb5c4")])
    body = '<rect x="6" y="24" width="88" height="54" rx="10" fill="url(#y1)"/>' + keys + '<rect x="26" y="71" width="48" height="5" rx="2.5" fill="url(#y2)"/><rect x="6.5" y="24.5" width="87" height="53" rx="9.5" fill="none" stroke="#fff" stroke-opacity="0.3"/>'
    return defs, body, '<rect x="6" y="24" width="88" height="54" rx="10" fill="S"/>'


def o_mouse(tone, c1, c2, d):
    defs = lg("u1", [(0, "#eceff5"), (1, "#a4acbc")], d) + lg("u2", [(0, "#fff", 0.5), (0.5, "#fff", 0)])
    sh = "M50 8C34 8 26 20 26 36v28c0 16 10 28 24 28s24-12 24-28V36C74 20 66 8 50 8z"
    body = f'<path d="{sh}" fill="url(#u1)"/><path d="{sh}" fill="url(#u2)"/><path d="M50 8v34M26 42h48" stroke="#6a7284" stroke-width="2" fill="none"/><rect x="46" y="18" width="8" height="16" rx="4" fill="#4a4f5e"/>'
    return defs, body, f'<path d="{sh}" fill="S"/>'


def o_speaker(tone, c1, c2, d):
    defs = lg("s1", [(0, "#5a5d68"), (1, "#25272e")], d) + rg("s2", [(0, "#9aa1b2"), (1, "#3a3d48")], 0.4, 0.35, 0.8)
    body = (
        '<rect x="22" y="8" width="56" height="84" rx="12" fill="url(#s1)"/>'
        '<circle cx="50" cy="32" r="8" fill="url(#s2)"/><circle cx="50" cy="64" r="18" fill="url(#s2)"/><circle cx="50" cy="64" r="8" fill="#1d1f25"/>'
        '<rect x="22.5" y="8.5" width="55" height="83" rx="11.5" fill="none" stroke="#fff" stroke-opacity="0.3"/>'
    )
    return defs, body, '<rect x="22" y="8" width="56" height="84" rx="12" fill="S"/>'


def o_printer(tone, c1, c2, d):
    defs = lg("r1", [(0, "#eceff5"), (1, "#aab2c2")], d) + lg("r2", [(0, "#5a5d68"), (1, "#2a2c34")]) + lg("r3", [(0, "#ffffff"), (1, "#dfe5f0")])
    body = (
        '<rect x="26" y="10" width="48" height="30" rx="4" fill="url(#r3)"/>'
        '<rect x="8" y="34" width="84" height="38" rx="10" fill="url(#r1)"/><rect x="8" y="58" width="84" height="14" rx="6" fill="url(#r2)"/>'
        '<rect x="24" y="62" width="52" height="28" rx="3" fill="url(#r3)"/><path d="M30 70h40M30 78h30" stroke="#b9c2d4" stroke-width="3" stroke-linecap="round"/>'
        '<circle cx="80" cy="45" r="3" fill="#2f9a58"/>'
    )
    return defs, body, '<rect x="8" y="10" width="84" height="80" rx="10" fill="S"/>'


def o_phone(tone, c1, c2, d):
    defs = lg("q1", [(0, "#5a5d68"), (1, "#25272e")], d) + lg("q2", [(0, mix(c1, "#ffffff", 0.2)), (1, c2)], d) + lg("q3", [(0, "#fff", 0.4), (0.5, "#fff", 0)], DD)
    body = (
        '<rect x="26" y="6" width="48" height="88" rx="10" fill="url(#q1)"/><rect x="31" y="14" width="38" height="72" rx="4" fill="url(#q2)"/><rect x="31" y="14" width="38" height="72" rx="4" fill="url(#q3)"/>'
        '<rect x="43" y="9" width="14" height="3" rx="1.5" fill="#000" fill-opacity="0.5"/><rect x="26.5" y="6.5" width="47" height="87" rx="9.5" fill="none" stroke="#fff" stroke-opacity="0.3"/>'
    )
    return defs, body, '<rect x="26" y="6" width="48" height="88" rx="10" fill="S"/>'


def o_gamepad(tone, c1, c2, d):
    defs = lg("g1", [(0, mix(c1, "#ffffff", 0.2)), (1, c2)], d) + lg("g2", [(0, "#fff", 0.4), (0.5, "#fff", 0)])
    sh = "M30 22h40c12 0 20 8 22 22l4 22c1 12-12 18-20 8L68 62H32l-8 12c-8 10-21 4-20-8l4-22c2-14 10-22 22-22z"
    body = f'<path d="{sh}" fill="url(#g1)"/><path d="{sh}" fill="url(#g2)"/><path d="M30 36v16M22 44h16" stroke="#1d1f25" stroke-width="6" stroke-linecap="round"/><circle cx="66" cy="38" r="4.5" fill="#1d1f25"/><circle cx="76" cy="48" r="4.5" fill="#1d1f25"/>'
    return defs, body, f'<path d="{sh}" fill="S"/>'


def o_harddisk(tone, c1, c2, d):
    defs = lg("e1", [(0, "#c9ced8"), (1, "#7d8494")], d) + lg("e2", [(0, "#5a5d68"), (1, "#2a2c34")])
    body = '<rect x="8" y="26" width="84" height="48" rx="10" fill="url(#e1)"/><rect x="8" y="58" width="84" height="16" rx="8" fill="url(#e2)"/><circle cx="78" cy="66" r="3" fill="#2f9a58"/><rect x="16" y="64" width="30" height="4" rx="2" fill="#fff" fill-opacity="0.3"/><rect x="8.5" y="26.5" width="83" height="47" rx="9.5" fill="none" stroke="#fff" stroke-opacity="0.45"/>'
    return defs, body, '<rect x="8" y="26" width="84" height="48" rx="10" fill="S"/>'


def o_flame(tone, c1, c2, d):
    defs = lg("fl1", [(0, "#ffd36a"), (0.45, "#f0701f"), (1, "#b8260b")]) + lg("fl2", [(0, "#fff3c4"), (1, "#ffb23a")])
    body = (
        '<path d="M52 8c4 16 26 26 26 50 0 20-12 34-28 34S22 78 22 60c0-10 5-17 10-22 1 8 5 12 9 12-3-16 4-30 11-42z" fill="url(#fl1)"/>'
        '<path d="M50 52c3 8 14 14 14 24 0 9-6 14-14 14s-14-5-14-14c0-6 3-10 7-14 0 5 2 7 5 8-1-6 0-12 2-18z" fill="url(#fl2)"/>'
    )
    return defs, body, '<path d="M52 8c4 16 26 26 26 50 0 20-12 34-28 34S22 78 22 60c0-10 5-17 10-22 1 8 5 12 9 12-3-16 4-30 11-42z" fill="S"/>'


OBJECTS.update({"flame": o_flame, "effects": o_flame, 
    "palette": o_palette, "font": o_fontblock, "bell": o_bell, "moon": o_moon, "nightlight": o_moon, "wifi": o_wifi, "clock": o_clock,
    "battery": o_battery, "access": o_access, "lock": o_lock, "lockscreen": o_lock, "chip": o_chip, "layout": o_layout, "dock": o_dock,
    "keyboard": o_keyboard, "mouse": o_mouse, "speaker": o_speaker, "printer": o_printer, "phone": o_phone, "gamepad": o_gamepad,
    "harddisk": o_harddisk, "users": OBJECTS["people"], "accounts": OBJECTS["people"], "user": OBJECTS["people"],
})

BOX = {
    "flame": (20, 8, 80, 92), "effects": (20, 8, 80, 92),
    "palette": (8, 10, 92, 90), "font": (8, 12, 96, 90), "bell": (12, 10, 88, 92), "moon": (8, 8, 90, 92), "nightlight": (8, 8, 90, 92),
    "wifi": (8, 8, 92, 92), "clock": (8, 8, 92, 92), "battery": (8, 28, 93, 72), "access": (8, 8, 92, 92), "lock": (16, 8, 84, 90),
    "lockscreen": (16, 8, 84, 90), "chip": (8, 8, 92, 92), "layout": (8, 16, 92, 84), "dock": (10, 12, 90, 92), "keyboard": (6, 24, 94, 78),
    "mouse": (26, 8, 74, 92), "speaker": (22, 8, 78, 92), "printer": (8, 10, 92, 90), "phone": (26, 6, 74, 94), "gamepad": (4, 22, 96, 78),
    "harddisk": (8, 26, 92, 74), "users": (8, 18, 92, 88), "accounts": (8, 18, 92, 88), "user": (8, 18, 92, 88),
}
