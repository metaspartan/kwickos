#!/usr/bin/env python3
"""Generate the KwickOS desktop theme assets (run once, outputs are committed):
  - three dark Plasma color schemes (Glass = macOS style, Fluent = Windows 11 style, Dark = Linux style)
  - two Aurorae window decorations: KwickGlass (rounded, translucent, traffic lights) and
    KwickFluent (Windows 11 caption buttons)
  - wallpapers: KwickGlass (dark liquid gradient) and KwickFluent (dark blue bloom)
  - Konsole color scheme + profile with translucency/blur
  - start-menu icons
usage: gen-theme.py <repo-root> <BreezeDark.colors>
"""
import json, math, os, random, re, shutil, sys

ROOT = sys.argv[1]
BREEZE = open(sys.argv[2]).read()
R = os.path.join(ROOT, "desktop/rootfs")


def w(path, text, mode="w"):
    p = os.path.join(R, path)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, mode) as f:
        f.write(text)


def scheme(name, win, win_alt, view, view_alt, btn, btn_alt, accent, focus, header, extra=None):
    out, grp = [], None
    for line in BREEZE.splitlines():
        m = re.match(r"\[(.*?)\](\[.*?\])?$", line)
        if m:
            grp = m.group(1) + (m.group(2) or "")
        key = line.split("=")[0] if "=" in line else ""
        rep = None
        if grp == "Colors:Window":
            rep = {"BackgroundNormal": win, "BackgroundAlternate": win_alt}.get(key)
        elif grp == "Colors:View":
            rep = {"BackgroundNormal": view, "BackgroundAlternate": view_alt}.get(key)
        elif grp == "Colors:Button":
            rep = {"BackgroundNormal": btn, "BackgroundAlternate": btn_alt}.get(key)
        elif grp in ("Colors:Tooltip",):
            rep = {"BackgroundNormal": btn, "BackgroundAlternate": win}.get(key)
        elif grp in ("Colors:Header", "Colors:Header[Inactive]"):
            rep = {"BackgroundNormal": header, "BackgroundAlternate": win}.get(key)
        elif grp == "Colors:Selection":
            rep = {"BackgroundNormal": accent, "DecorationFocus": focus, "DecorationHover": focus}.get(key)
        if key in ("DecorationFocus", "DecorationHover") and grp not in ("Colors:Selection",):
            rep = focus
        if key == "Name" and grp == "General":
            line, rep = "Name=" + name, None
        if key in ("activeBackground",) and grp == "WM":
            rep = win
        if key in ("inactiveBackground",) and grp == "WM":
            rep = view
        if extra:
            for g in (grp, "*") if grp and grp.startswith("Colors:") else (grp,):
                if g in extra and key in extra[g]:
                    rep = extra[g][key]
                    break
        out.append(f"{key}={rep}" if rep else line)
    w(f"usr/share/color-schemes/{name}.colors", "\n".join(out) + "\n")


def over(alpha, bg, fg=255):
    return round(alpha * fg + (1 - alpha) * bg)


def grey(v):
    return f"{v},{v},{v}"


MAC = {"window": 50, "under": 40, "control_bg": 30, "alt_row": over(0.047, 30), "button": over(0.247, 50),
       "label": 0.847, "secondary": 0.549, "tertiary": 0.247,
       "blue": "10,132,255", "link": "65,156,255", "purple": "191,90,242", "red": "255,69,58",
       "orange": "255,159,10", "green": "50,215,75"}


def mac_fg(bg):
    return {"ForegroundNormal": grey(over(MAC["label"], bg)), "ForegroundInactive": grey(over(MAC["secondary"], bg)),
            "ForegroundActive": MAC["blue"], "ForegroundLink": MAC["link"], "ForegroundVisited": MAC["purple"],
            "ForegroundNegative": MAC["red"], "ForegroundNeutral": MAC["orange"], "ForegroundPositive": MAC["green"]}


mac_header_inactive = dict(mac_fg(MAC["under"]), BackgroundNormal=grey(MAC["under"]), BackgroundAlternate=grey(MAC["under"]))
scheme("KwickGlass", grey(MAC["window"]), grey(over(0.047, MAC["window"])), grey(MAC["control_bg"]), grey(MAC["alt_row"]),
       grey(MAC["button"]), grey(over(0.098, MAC["button"])), MAC["blue"], MAC["blue"], grey(MAC["window"]), {
           "Colors:Window": mac_fg(MAC["window"]),
           "Colors:View": mac_fg(MAC["control_bg"]),
           "Colors:Button": mac_fg(MAC["button"]),
           "Colors:Header": mac_fg(MAC["window"]),
           "Colors:Header[Inactive]": mac_header_inactive,
           "Colors:Tooltip": dict(mac_fg(MAC["window"]), BackgroundNormal=grey(MAC["window"]), BackgroundAlternate=grey(MAC["under"])),
           "Colors:Complementary": dict(mac_fg(MAC["control_bg"]), BackgroundNormal=grey(MAC["control_bg"]), BackgroundAlternate=grey(MAC["under"])),
           "Colors:Selection": {"BackgroundAlternate": "0,88,208", "ForegroundNormal": "255,255,255", "ForegroundActive": "255,255,255",
                                "ForegroundInactive": grey(over(MAC["label"], 0)), "ForegroundLink": "255,255,255",
                                "ForegroundVisited": "255,255,255", "ForegroundNegative": MAC["red"],
                                "ForegroundNeutral": MAC["orange"], "ForegroundPositive": MAC["green"]},
           "WM": {"activeBackground": grey(MAC["window"]), "activeBlend": grey(over(MAC["label"], MAC["window"])),
                  "activeForeground": grey(over(MAC["label"], MAC["window"])), "inactiveBackground": grey(MAC["under"]),
                  "inactiveBlend": grey(over(MAC["tertiary"], MAC["under"])), "inactiveForeground": grey(over(MAC["tertiary"], MAC["under"]))},
       })

FLU = {"base": 32, "secondary": 28, "card": over(0x0D / 255, 32), "control": over(0x0F / 255, 32),
       "control2": over(0x15 / 255, 32), "flyout": 44, "text2": 0xC5 / 255, "text3": 0x87 / 255,
       "accent": "0,120,212", "accent_light2": "96,205,255", "accent_light3": "153,235,255",
       "success": "108,203,95", "caution": "252,225,0", "critical": "255,153,164"}


def flu_fg(bg):
    return {"ForegroundNormal": "255,255,255", "ForegroundInactive": grey(over(FLU["text2"], bg)),
            "ForegroundActive": FLU["accent_light2"], "ForegroundLink": FLU["accent_light3"],
            "ForegroundNegative": FLU["critical"], "ForegroundNeutral": FLU["caution"], "ForegroundPositive": FLU["success"]}


scheme("KwickFluent", grey(FLU["base"]), grey(FLU["card"]), grey(FLU["secondary"]), grey(over(0x08 / 255, FLU["secondary"])),
       grey(FLU["control"]), grey(FLU["control2"]), FLU["accent"], FLU["accent_light2"], grey(FLU["base"]), {
           "Colors:Window": flu_fg(FLU["base"]),
           "Colors:View": flu_fg(FLU["secondary"]),
           "Colors:Button": flu_fg(FLU["control"]),
           "Colors:Header": flu_fg(FLU["base"]),
           "Colors:Header[Inactive]": flu_fg(FLU["base"]),
           "Colors:Tooltip": dict(flu_fg(FLU["flyout"]), BackgroundNormal=grey(FLU["flyout"]), BackgroundAlternate=grey(FLU["base"])),
           "Colors:Complementary": dict(flu_fg(FLU["secondary"]), BackgroundNormal=grey(FLU["secondary"]), BackgroundAlternate=grey(FLU["base"])),
           "Colors:Selection": {"ForegroundNormal": "255,255,255", "ForegroundActive": "255,255,255", "ForegroundLink": "255,255,255"},
           "WM": {"activeBackground": grey(FLU["base"]), "activeBlend": "255,255,255", "activeForeground": "255,255,255",
                  "inactiveBackground": grey(FLU["base"]), "inactiveBlend": grey(over(FLU["text3"], FLU["base"])),
                  "inactiveForeground": grey(over(FLU["text3"], FLU["base"]))},
       })
scheme("KwickDark", "22,23,31", "29,30,41", "17,18,26", "24,25,34", "35,37,50", "44,46,62",
       "94,129,244", "94,129,244", "26,27,37")


def svg_rect_path(x, y, wd, ht, rtl=0, rtr=0, fill="#000", op=1.0):
    d = f"M{x},{y + rtl} " + (f"A{rtl},{rtl} 0 0 1 {x + rtl},{y} " if rtl else f"L{x},{y} ")
    d += f"L{x + wd - rtr},{y} " + (f"A{rtr},{rtr} 0 0 1 {x + wd},{y + rtr} " if rtr else f"L{x + wd},{y} ")
    d += f"L{x + wd},{y + ht} L{x},{y + ht} Z"
    return f'<path d="{d}" fill="{fill}" fill-opacity="{op}"/>'


def aurorae(name, title_h, border, radius, bar_a, bar_i, edge, buttons, btn_w, btn_h, spacing, margin_top,
            align, text_a, text_i, rc_title_h=None, shadow=(6, 10, 14, 0.15, 0.08), sides=(1.0, 1.0, 1.0)):
    parts = ['<svg xmlns="http://www.w3.org/2000/svg" width="640" height="320" viewBox="0 0 640 320">']
    pt, ps, pb, sa, si = shadow
    ov = 1 if pt > 6 else 0
    ft, fs, fb = sides
    defs = ""
    q = ((0, 0.0), (0.3, 0.12), (0.6, 0.42), (1, 1.0))
    if shadow[0] > 6:
        q = tuple((o, math.exp(-((1 - o) * 2.15) ** 2) if o > 0 else 0.0) for o in (0, 0.15, 0.3, 0.45, 0.6, 0.72, 0.84, 0.93, 1))
    T = title_h
    for pi, (prefix, y, bar) in enumerate((("decoration", 0, bar_a), ("decoration-inactive", 60, bar_i))):
        col, op = bar
        k = f"{pi}"
        a = sa if pi == 0 else si

        def stops(rev=False, f=1.0):
            pts = [(1 - o, v) for o, v in reversed(q)] if rev else list(q)
            return "".join(f'<stop offset="{o}" stop-color="#000" stop-opacity="{a * f * v:.4f}"/>' for o, v in pts)

        def rstops(f=1.0):
            pts = [(1 - o, v) for o, v in reversed(q)]
            return "".join(f'<stop offset="{o}" stop-color="#000" stop-opacity="{a * f * v:.4f}"/>' for o, v in pts)

        defs += (
            f'<linearGradient id="gl{k}" x1="0" y1="0" x2="1" y2="0">{stops(f=fs)}</linearGradient>'
            f'<linearGradient id="gr{k}" x1="0" y1="0" x2="1" y2="0">{stops(True, fs)}</linearGradient>'
            f'<linearGradient id="gt{k}" x1="0" y1="0" x2="0" y2="1">{stops(f=ft)}</linearGradient>'
            f'<linearGradient id="gb{k}" x1="0" y1="0" x2="0" y2="1">{stops(True, fb)}</linearGradient>'
        )
        for nm, cx, cy, sx, sy, f in (("rtl", ps, pt, ps, pt, (ft + fs) / 2), ("rtr", 0, pt, ps, pt, (ft + fs) / 2),
                                      ("rbl", ps, 0, ps, pb, (fb + fs) / 2), ("rbr", 0, 0, ps, pb, (fb + fs) / 2)):
            defs += f'<radialGradient id="{nm}{k}" gradientUnits="userSpaceOnUse" cx="0" cy="0" r="1" gradientTransform="translate({cx} {cy}) scale({sx} {sy})">{rstops(f)}</radialGradient>'
        tl = f'<rect x="0" y="0" width="{ps}" height="{pt}" fill="url(#rtl{k})"/><rect x="0" y="{pt}" width="{ps}" height="{T}" fill="url(#gl{k})"/>'
        tp = f'<rect x="0" y="0" width="8" height="{pt}" fill="url(#gt{k})"/>{svg_rect_path(0, pt, 8, T + 1, fill=col, op=op)}'
        tr = f'<rect x="0" y="0" width="{ps}" height="{pt}" fill="url(#rtr{k})"/><rect x="0" y="{pt}" width="{ps}" height="{T}" fill="url(#gr{k})"/>'
        pieces = {
            "topleft": (0, tl),
            "top": (30, tp),
            "topright": (60, tr),
            "left": (90, f'<rect width="{ps}" height="8" fill="url(#gl{k})"/>'),
            "center": (110, '<rect width="8" height="8" fill="#000" fill-opacity="0"/>'),
            "right": (130, f'<rect width="{ps}" height="8" fill="url(#gr{k})"/>'),
            "bottomleft": (150, f'<rect width="{ps}" height="{pb}" fill="url(#rbl{k})"/>'),
            "bottom": (170, f'<rect width="8" height="{pb}" fill="url(#gb{k})"/>'),
            "bottomright": (190, f'<rect width="{ps}" height="{pb}" fill="url(#rbr{k})"/>'),
        }
        for nm, (x, body) in pieces.items():
            parts.append(f'<g id="{prefix}-{nm}"><g transform="translate({x},{y})">{body}</g></g>')
    parts.insert(1, f"<defs>{defs}</defs>")
    y = 130
    for kind in ("close", "minimize", "maximize", "restore", "alldesktops", "keepabove", "keepbelow", "shade", "help"):
        x = 0
        for st in ("active", "inactive", "hover", "pressed", "deactivated", ""):
            eid = f"{kind}-{st}" if st else kind
            parts.append(f'<g id="{eid}"><g transform="translate({10 + x},{y})">{buttons(kind, st or "active")}<rect width="{btn_w}" height="{btn_h}" fill="#000" fill-opacity="0"/></g></g>')
            x += btn_w + 10
        y += btn_h + 6
    parts.append("</svg>")
    d = f"usr/share/aurorae/themes/{name}"
    for kind in ("close", "minimize", "maximize", "restore", "alldesktops", "keepabove", "keepbelow", "shade", "help"):
        bp = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{btn_w * 6}" height="{btn_h}" viewBox="0 0 {btn_w * 6} {btn_h}">']
        for i, st in enumerate(("active", "inactive", "hover", "pressed", "deactivated")):
            bp.append(f'<g id="{st}-center"><g transform="translate({i * btn_w},0)">{buttons(kind, st)}<rect width="{btn_w}" height="{btn_h}" fill="#000" fill-opacity="0"/></g></g>')
        bp.append("</svg>")
        w(f"{d}/{kind}.svg", "\n".join(bp) + "\n")
    w(f"{d}/decoration.svg", "\n".join(parts) + "\n")
    w(f"{d}/{name}rc", f"""[General]
ActiveTextColor={text_a}
InactiveTextColor={text_i}
Animation=140
TitleAlignment={align}
TitleVerticalAlignment=Center
UseTextShadow=false

[Layout]
BorderLeft=0
BorderRight=0
BorderBottom=0
TitleEdgeTop=0
TitleEdgeBottom=0
TitleEdgeLeft=12
TitleEdgeRight=12
TitleBorderLeft=0
TitleBorderRight=0
TitleHeight={rc_title_h or title_h}
ButtonWidth={btn_w}
ButtonHeight={btn_h}
ButtonSpacing={spacing}
ButtonMarginTop={margin_top}
ExplicitButtonSpacer=6
PaddingTop={pt}
PaddingLeft={ps - ov}
PaddingRight={ps - ov}
PaddingBottom={pb - ov}
""")
    w(f"{d}/metadata.json", json.dumps({"KPlugin": {"Id": name, "Name": name, "Description": "KwickOS window decoration",
                                                      "Authors": [{"Name": "KwickOS"}], "License": "MIT"}}, indent=2) + "\n")
    w(f"{d}/metadata.desktop", f"[Desktop Entry]\nName={name}\nComment=KwickOS window decoration\nX-KDE-PluginInfo-Name={name}\nX-KDE-PluginInfo-Author=KwickOS\nX-KDE-PluginInfo-License=MIT\n")


def mac_buttons(kind, st):
    col = {"close": "#ff5f57", "minimize": "#febc2e", "maximize": "#28c840", "restore": "#28c840"}.get(kind, "#98989d")
    if st in ("inactive", "deactivated"):
        col = "#4d4d4d"
    glyph = ""
    if st in ("hover", "pressed"):
        g = {"close": "M4.2,4.2 L9.8,9.8 M9.8,4.2 L4.2,9.8", "minimize": "M3.5,7 L10.5,7",
             "maximize": "M7,3.5 L7,10.5 M3.5,7 L10.5,7", "restore": "M7,3.5 L7,10.5 M3.5,7 L10.5,7"}.get(kind, "")
        glyph = f'<path d="{g}" stroke="#2b1a18" stroke-width="1.5" stroke-linecap="round" fill="none"/>'
    shade = ' opacity="0.8"' if st == "pressed" else ""
    return f'<circle cx="7" cy="7" r="5.8" fill="{col}"{shade}/><circle cx="7" cy="7" r="5.8" fill="none" stroke="#000" stroke-opacity="0.25" stroke-width="0.6"/>{glyph}'


def win_buttons(kind, st):
    inactive = st in ("inactive", "deactivated")
    fg = "#717171" if inactive else "#ffffff"
    bg = ""
    if st == "hover":
        bg = '<rect width="46" height="32" fill="%s"/>' % ("#c42b1c" if kind == "close" else "#ffffff")
        bg = bg.replace("/>", ' fill-opacity="%s"/>' % ("1" if kind == "close" else "0.0588"))
    if st == "pressed":
        bg = '<rect width="46" height="32" fill="%s" fill-opacity="%s"/>' % ("#c42b1c" if kind == "close" else "#ffffff", "0.9" if kind == "close" else "0.0392")
    g = {"close": "M18.5,11.5 L27.5,20.5 M27.5,11.5 L18.5,20.5", "minimize": "M18,16.5 L28,16.5",
         "maximize": "M18.5,11.5 H27.5 V20.5 H18.5 Z", "restore": "M20.5,13.5 H27.5 V20.5 H20.5 Z M22.5,11.5 H29.5 V18.5"}.get(kind, "")
    return f'{bg}<path d="{g}" stroke="{fg}" stroke-width="1" fill="none" stroke-linecap="square"/>'


aurorae("KwickGlass", 34, 1, 10, ("#323232", 1), ("#282828", 1), ("#323232", 1),
        mac_buttons, 14, 14, 5, 7, "Center", grey(over(MAC["label"], MAC["window"])),
        grey(over(MAC["tertiary"], MAC["under"])), 28, shadow=(24, 36, 54, 0.40, 0.20))
aurorae("KwickFluent", 32, 1, 8, ("#202020", 1), ("#202020", 1), ("#202020", 1),
        win_buttons, 46, 32, 0, 0, "Left", "255,255,255", grey(over(FLU["text3"], FLU["base"])))


def frame_svg(r, fill, op, stroke=None, stroke_op=0.0, prefix="", margins=(4, 4, 4, 4), bottom_extra="", ox=0, oy=0, edge=None):
    e = edge or r or 4
    pieces = []

    def piece(name, x, y, wd, ht, body):
        pieces.append(f'<g id="{prefix}{name}"><rect x="{x}" y="{y}" width="{wd}" height="{ht}" fill="#000" fill-opacity="0"/>{body}</g>')

    f = f'fill="{fill}" fill-opacity="{op}"'
    s = f'stroke="{stroke}" stroke-opacity="{stroke_op}" stroke-width="1" fill="none"' if stroke else ""
    x0, y0 = ox, oy
    if r:
        x, y, X, Y, q = x0, y0, x0 + 40, y0 + 40, r - 0.5
        piece("topleft", x, y, e, e, f'<path d="M{x},{y + e} L{x},{y + r} A{r},{r} 0 0 1 {x + r},{y} L{x + e},{y} L{x + e},{y + e} Z" {f}/>' +
              (f'<path d="M{x + 0.5},{y + e} L{x + 0.5},{y + r} A{q},{q} 0 0 1 {x + r},{y + 0.5} L{x + e},{y + 0.5}" {s}/>' if s else ""))
        piece("topright", X, y, e, e, f'<path d="M{X},{y} L{X + e - r},{y} A{r},{r} 0 0 1 {X + e},{y + r} L{X + e},{y + e} L{X},{y + e} Z" {f}/>' +
              (f'<path d="M{X},{y + 0.5} L{X + e - r},{y + 0.5} A{q},{q} 0 0 1 {X + e - 0.5},{y + r} L{X + e - 0.5},{y + e}" {s}/>' if s else ""))
        piece("bottomleft", x, Y, e, e, f'<path d="M{x},{Y} L{x + e},{Y} L{x + e},{Y + e} L{x + r},{Y + e} A{r},{r} 0 0 1 {x},{Y + e - r} Z" {f}/>' +
              (f'<path d="M{x + 0.5},{Y} L{x + 0.5},{Y + e - r} A{q},{q} 0 0 0 {x + r},{Y + e - 0.5} L{x + e},{Y + e - 0.5}" {s}/>' if s else ""))
        piece("bottomright", X, Y, e, e, f'<path d="M{X},{Y} L{X + e},{Y} L{X + e},{Y + e - r} A{r},{r} 0 0 1 {X + e - r},{Y + e} L{X},{Y + e} Z" {f}/>' +
              (f'<path d="M{X + e - 0.5},{Y} L{X + e - 0.5},{Y + e - r} A{q},{q} 0 0 1 {X + e - r},{Y + e - 0.5} L{X},{Y + e - 0.5}" {s}/>' if s else ""))
    else:
        for nm, x, y in (("topleft", x0, y0), ("topright", x0 + 40, y0), ("bottomleft", x0, y0 + 40), ("bottomright", x0 + 40, y0 + 40)):
            piece(nm, x, y, e, e, f'<rect x="{x}" y="{y}" width="{e}" height="{e}" {f}/>' if op else "")
    line = lambda x1, y1, x2, y2: (f'<rect x="{min(x1, x2) - (0.5 if x1 == x2 else 0)}" y="{min(y1, y2) - (0.5 if y1 == y2 else 0)}" width="{abs(x2 - x1) or 1}" height="{abs(y2 - y1) or 1}" fill="{stroke}" fill-opacity="{stroke_op}"/>' if s and r else "")
    piece("top", x0 + 20, y0, 10, e, f'<rect x="{x0 + 20}" y="{y0}" width="10" height="{e}" {f}/>' + line(x0 + 20, y0 + 0.5, x0 + 30, y0 + 0.5))
    piece("bottom", x0 + 20, y0 + 40, 10 if not bottom_extra else 64, e, f'<rect x="{x0 + 20}" y="{y0 + 40}" width="{10 if not bottom_extra else 64}" height="{e}" {f}/>' +
          line(x0 + 20, y0 + 40 + e - 0.5, x0 + 30, y0 + 40 + e - 0.5) + bottom_extra.format(x=x0 + 20, y=y0 + 40))
    piece("left", x0, y0 + 20, e, 10, f'<rect x="{x0}" y="{y0 + 20}" width="{e}" height="10" {f}/>' + line(x0 + 0.5, y0 + 20, x0 + 0.5, y0 + 30))
    piece("right", x0 + 40, y0 + 20, e, 10, f'<rect x="{x0 + 40}" y="{y0 + 20}" width="{e}" height="10" {f}/>' + line(x0 + 40 + e - 0.5, y0 + 20, x0 + 40 + e - 0.5, y0 + 30))
    piece("center", x0 + 20, y0 + 20, 10, 10, f'<rect x="{x0 + 20}" y="{y0 + 20}" width="10" height="10" {f}/>')
    for side, m in zip(("top", "bottom", "left", "right"), margins):
        pieces.append(f'<rect id="{prefix}hint-{side}-margin" x="{x0 + 100}" y="{y0}" width="{m}" height="{m}" fill="#000" fill-opacity="0"/>')
    return "".join(pieces)


def plasma_theme(name, title, panel, tasks, menubar=None):
    d = f"usr/share/plasma/desktoptheme/{name}"
    w(f"{d}/metadata.json", json.dumps({"KPlugin": {"Authors": [{"Name": "KwickOS"}], "Description": f"{title} panels for KwickOS",
                                                     "Id": name, "License": "MIT", "Name": title, "Version": "1.0"},
                                         "X-Plasma-API": "5.0"}, indent=4) + "\n")
    w(f"{d}/plasmarc", "[ContrastEffect]\nenabled=false\n\n[BlurBehindEffect]\nenabled=true\n\n[AdaptiveTransparency]\nenabled=true\n")
    head = '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400" viewBox="0 0 400 400">'
    for sub, op in (("widgets", 1.0), ("translucent/widgets", panel["op"]), ("opaque/widgets", 1.0), ("solid/widgets", 1.0)):
        body = frame_svg(panel["r"], panel["fill"], op, panel.get("stroke"), panel.get("stroke_op", 0), margins=panel["margins"])
        body += frame_svg(panel["r"], panel["fill"], panel.get("edge_op", op), prefix="north-", ox=200, margins=panel["margins"])
        body += frame_svg(panel["r"], "#000", 1.0, prefix="mask-", oy=200, margins=panel["margins"])
        w(f"{d}/{sub}/panel-background.svg", head + body + "</svg>\n")
    body = '<rect id="hint-stretch-borders" x="380" y="380" width="4" height="4" fill="#000" fill-opacity="0"/>'
    for i, (state, spec) in enumerate(tasks.items()):
        body += frame_svg(spec.get("r", 0), spec.get("fill", "#ffffff"), spec.get("op", 0.0), prefix=f"{state}-",
                          margins=(4, 4, 4, 4), bottom_extra=spec.get("mark", ""), ox=0, oy=i * 80, edge=spec.get("edge", 6))
    w(f"{d}/widgets/tasks.svg", head.replace('height="400"', 'height="420"').replace("0 0 400 400", "0 0 400 420") + body + "</svg>\n")
    if menubar:
        body = ""
        for i, (state, spec) in enumerate(menubar.items()):
            body += frame_svg(spec.get("r", 0), spec.get("fill", "#ffffff"), spec.get("op", 0.0), prefix=f"{state}-",
                              margins=spec.get("margins", (4, 4, 8, 8)), ox=0, oy=i * 80, edge=spec.get("edge", 6))
        w(f"{d}/widgets/menubaritem.svg", head + body + "</svg>\n")


def dot(col, op, size=4, h=6):
    return (f'<circle cx="{{x}}" cy="{{y}}" r="{size / 2}" fill="{col}" fill-opacity="{op}" '
            f'transform="translate(32 {h - size / 2 - 1})"/>')


def pill(col, wd, ht, h=6):
    return f'<rect x="{{x}}" y="{{y}}" width="{wd}" height="{ht}" rx="{ht / 2}" fill="{col}" transform="translate({32 - wd / 2} {h - ht - 1})"/>'


mac_dot = dot("#ffffff", 0.55)
plasma_theme("kwick-glass", "KwickGlass",
             {"r": 18, "fill": "#323232", "op": 0.55, "stroke": "#ffffff", "stroke_op": 0.15, "margins": (2, 2, 6, 6)},
             {"normal": {"mark": mac_dot}, "focus": {"mark": mac_dot}, "minimized": {"mark": mac_dot},
              "hover": {}, "attention": {"mark": dot("#ff9f0a", 1.0)}},
             {"normal": {}, "hover": {"r": 5, "edge": 6, "op": 0.2}, "pressed": {"r": 5, "edge": 6, "op": 0.24}})
plasma_theme("kwick-fluent", "KwickFluent",
             {"r": 0, "fill": "#202020", "op": 0.85, "margins": (4, 4, 4, 4)},
             {"normal": {"mark": pill("#9d9d9d", 6, 3)}, "minimized": {"mark": pill("#9d9d9d", 6, 3)},
              "focus": {"r": 4, "edge": 6, "op": 0x0F / 255, "mark": pill("#60cdff", 16, 3)},
              "hover": {"r": 4, "edge": 6, "op": 0x0F / 255}, "attention": {"r": 4, "edge": 6, "op": 0x0F / 255, "mark": pill("#fce100", 16, 3)}})


def wallpaper(name, painter, size=(2560, 1440)):
    from PIL import Image, ImageFilter
    img = painter(size)
    rnd = Image.effect_noise(size, 12).convert("RGB")
    img = Image.blend(img, Image.merge("RGB", [rnd.split()[0]] * 3), 0.025)
    d = f"usr/share/wallpapers/{name}/contents/images"
    os.makedirs(os.path.join(R, d), exist_ok=True)
    img.save(os.path.join(R, d, "2560x1440.png"), optimize=True)
    img.resize((1920, 1080), Image.LANCZOS).save(os.path.join(R, d, "1920x1080.png"), optimize=True)
    w(f"usr/share/wallpapers/{name}/metadata.json", json.dumps({"KPlugin": {"Authors": [{"Name": "KwickOS"}],
                                                                           "Id": name, "License": "CC-BY-SA-4.0", "Name": name}}, indent=4) + "\n")


def glass_wall(size):
    from PIL import Image, ImageDraw, ImageFilter, ImageChops
    W, H = size
    s = 4
    base = Image.new("RGB", (W // s, H // s), (9, 10, 22))
    blobs = [(0.18, 0.25, 0.42, (40, 60, 190)), (0.72, 0.20, 0.38, (120, 60, 200)), (0.55, 0.78, 0.46, (20, 120, 200)),
             (0.10, 0.85, 0.30, (70, 40, 150)), (0.92, 0.75, 0.28, (30, 90, 170))]
    for cx, cy, r, col in blobs:
        layer = Image.new("RGB", base.size, (0, 0, 0))
        ld = ImageDraw.Draw(layer)
        for k in range(24, 0, -1):
            f = k / 24
            rr = int(r * W / s * f)
            a_ = tuple(int(c * (1 - f) ** 1.6 * 0.42) for c in col)
            ld.ellipse([cx * W / s - rr, cy * H / s - rr, cx * W / s + rr, cy * H / s + rr], fill=a_)
        base = ImageChops.add(base, layer)
    base = base.filter(ImageFilter.GaussianBlur(14))
    return base.resize((W, H), Image.BICUBIC)


def fluent_wall(size):
    from PIL import Image, ImageDraw, ImageFilter, ImageChops
    W, H = size
    s = 4
    base = Image.new("RGB", (W // s, H // s), (6, 12, 28))
    cx, cy = W / s * 0.5, H / s * 0.52
    for ang in range(0, 360, 60):
        layer = Image.new("RGB", base.size, (0, 0, 0))
        d = ImageDraw.Draw(layer)
        for k in range(30, 0, -1):
            f = k / 30
            rx, ry = W / s * 0.30 * f, H / s * 0.11 * f
            col = (int(10 * (1 - f)), int(110 * (1 - f) ** 1.5), int(255 * (1 - f) ** 1.2))
            ex = cx + math.cos(math.radians(ang)) * W / s * 0.12
            ey = cy + math.sin(math.radians(ang)) * H / s * 0.12
            petal = Image.new("RGB", base.size, (0, 0, 0))
            pd = ImageDraw.Draw(petal)
            pd.ellipse([ex - rx, ey - ry, ex + rx, ey + ry], fill=col)
            petal = petal.rotate(-ang + 90, center=(cx, cy))
            layer = ImageChops.add(layer, petal)
        base = ImageChops.add(base, layer.point(lambda v: int(v * 0.55)))
    base = base.filter(ImageFilter.GaussianBlur(10))
    return base.resize((W, H), Image.BICUBIC)


wallpaper("KwickGlass", glass_wall)
wallpaper("KwickFluent", fluent_wall)

def rgb(c):
    return f"{c[0]},{c[1]},{c[2]}"


def konsole(name, desc, bg, fg, bg_int, fg_faint, pal, palI, opacity, blur):
    cs = (f"[Background]\nColor={rgb(bg)}\n\n[BackgroundFaint]\nColor={rgb(bg)}\n\n[BackgroundIntense]\nColor={rgb(bg_int)}\n\n"
          f"[Foreground]\nColor={rgb(fg)}\n\n[ForegroundFaint]\nColor={rgb(fg_faint)}\n\n[ForegroundIntense]\nColor=255,255,255\n")
    for i, c in enumerate(pal):
        cs += f"\n[Color{i}]\nColor={rgb(c)}\n\n[Color{i}Faint]\nColor={rgb(c)}\n\n[Color{i}Intense]\nColor={rgb(palI[i])}\n"
    cs += f"\n[General]\nBlur={'true' if blur else 'false'}\nColorRandomization=false\nDescription={desc}\nOpacity={opacity}\nWallpaper=\n"
    w(f"usr/share/konsole/{name}.colorscheme", cs)


def profile(fname, pname, scheme_name, font, cursor=None):
    cur = f"\n[Cursor Options]\nCustomCursorColor={rgb(cursor)}\nUseCustomCursorColor=true\n" if cursor else ""
    w(f"usr/share/konsole/{fname}.profile", f"[Appearance]\nColorScheme={scheme_name}\nFont={font},-1,5,400,0,0,0,0,0,0,0,0,0,0,1\nTerminalMargin=14\nTerminalCenter=false\n{cur}\n[General]\nName={pname}\nParent=FALLBACK/\n\n[Scrolling]\nScrollBarPosition=2\n\n[Terminal Features]\nBlinkingCursorEnabled=true\n")


TERMINAL_APP = [(0, 0, 0), (153, 0, 0), (0, 166, 0), (153, 153, 0), (0, 0, 178), (178, 0, 178), (0, 166, 178), (191, 191, 191)]
TERMINAL_APP_BRIGHT = [(102, 102, 102), (230, 0, 0), (0, 217, 0), (230, 230, 0), (0, 0, 255), (230, 0, 230), (0, 230, 230), (230, 230, 230)]
konsole("KwickGlass", "KwickOS Terminal (macOS Basic, dark)", (30, 30, 30), (255, 255, 255), (30, 30, 30),
        (over(MAC["secondary"], 30),) * 3, TERMINAL_APP, TERMINAL_APP_BRIGHT, 1, False)
CAMPBELL = [(12, 12, 12), (197, 15, 31), (19, 161, 14), (193, 156, 0), (0, 55, 218), (136, 23, 152), (58, 150, 221), (204, 204, 204)]
CAMPBELL_BRIGHT = [(118, 118, 118), (231, 72, 86), (22, 198, 12), (249, 241, 165), (59, 120, 255), (180, 0, 158), (97, 214, 214), (242, 242, 242)]
konsole("KwickFluent", "KwickOS Terminal (Windows Terminal Campbell)", (12, 12, 12), (204, 204, 204), (12, 12, 12),
        (118, 118, 118), CAMPBELL, CAMPBELL_BRIGHT, 1, False)
konsole("KwickNight", "KwickOS Glass", (16, 17, 24), (226, 228, 240), (24, 25, 34), (150, 153, 170),
        [(30, 32, 44), (255, 95, 109), (80, 214, 140), (255, 200, 87), (86, 156, 255), (190, 130, 255), (70, 210, 220), (210, 214, 228)],
        [(90, 94, 112), (255, 128, 140), (120, 235, 170), (255, 220, 130), (130, 185, 255), (212, 165, 255), (120, 230, 238), (255, 255, 255)],
        0.82, True)
profile("KwickOS", "KwickOS", "KwickGlass", "JetBrains Mono,11", (146, 146, 146))
profile("KwickFluent", "KwickOS Fluent", "KwickFluent", "Cascadia Code,11", (255, 255, 255))
profile("KwickLinux", "KwickOS Linux", "KwickNight", "JetBrains Mono,11")
w("etc/xdg/konsolerc", "[Desktop Entry]\nDefaultProfile=KwickOS.profile\n\n[KonsoleWindow]\nShowMenuBarByDefault=false\n")

logo = os.path.join(ROOT, "docs/img/kwickos-logo.svg")
for name in ("kwickos-logo", "kwick-start", "kwick-start-fluent"):
    target = os.path.join(R, f"usr/share/icons/hicolor/scalable/apps/{name}.svg")
    os.makedirs(os.path.dirname(target), exist_ok=True)
    shutil.copyfile(logo, target)
print("theme assets written")
