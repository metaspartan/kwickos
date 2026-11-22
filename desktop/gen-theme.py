#!/usr/bin/env python3
import json, math, os, re, shutil, sys

ROOT = sys.argv[1]
BREEZE = open(sys.argv[2]).read()
BREEZE_LIGHT = open(sys.argv[3] if len(sys.argv) > 3 else os.path.join(os.path.dirname(sys.argv[2]), "BreezeLight.colors")).read()
R = os.path.join(ROOT, "desktop/rootfs")


def w(path, text, mode="w"):
    p = os.path.join(R, path)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, mode) as f:
        f.write(text)


def scheme(name, win, win_alt, view, view_alt, btn, btn_alt, accent, focus, header, extra=None, base=None):
    out, grp = [], None
    for line in (base or BREEZE).splitlines():
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
       "orange": "255,159,10", "green": "50,215,75", "ink": 255, "fill": 0.047, "button_alt": 0.098}
MAC_LIGHT = {"window": 236, "under": 246, "control_bg": 255, "alt_row": 244, "button": 255,
             "label": 0.847, "secondary": 0.498, "tertiary": 0.259,
             "blue": "0,122,255", "link": "0,104,218", "purple": "175,82,222", "red": "255,59,48",
             "orange": "255,149,0", "green": "40,205,65", "ink": 0, "fill": 0.03, "button_alt": 0.05}


def mac_fg(P, bg):
    ink = P["ink"]
    return {"ForegroundNormal": grey(over(P["label"], bg, ink)), "ForegroundInactive": grey(over(P["secondary"], bg, ink)),
            "ForegroundActive": P["blue"], "ForegroundLink": P["link"], "ForegroundVisited": P["purple"],
            "ForegroundNegative": P["red"], "ForegroundNeutral": P["orange"], "ForegroundPositive": P["green"]}


def mac_scheme(name, P, base):
    ink = P["ink"]

    def fg(bg):
        return mac_fg(P, bg)

    scheme(name, grey(P["window"]), grey(over(P["fill"], P["window"], ink)), grey(P["control_bg"]), grey(P["alt_row"]),
           grey(P["button"]), grey(over(P["button_alt"], P["button"], ink)), P["blue"], P["blue"], grey(P["window"]), {
               "Colors:Window": fg(P["window"]),
               "Colors:View": fg(P["control_bg"]),
               "Colors:Button": fg(P["button"]),
               "Colors:Header": fg(P["window"]),
               "Colors:Header[Inactive]": dict(fg(P["under"]), BackgroundNormal=grey(P["under"]), BackgroundAlternate=grey(P["under"])),
               "Colors:Tooltip": dict(fg(P["window"]), BackgroundNormal=grey(P["window"]), BackgroundAlternate=grey(P["under"])),
               "Colors:Complementary": dict(mac_fg(MAC, MAC["window"]), BackgroundNormal=grey(MAC["window"]), BackgroundAlternate=grey(MAC["under"])),
               "Colors:Selection": {"BackgroundAlternate": "0,88,208", "ForegroundNormal": "255,255,255", "ForegroundActive": "255,255,255",
                                    "ForegroundInactive": grey(over(MAC["label"], 0)), "ForegroundLink": "255,255,255",
                                    "ForegroundVisited": "255,255,255", "ForegroundNegative": P["red"],
                                    "ForegroundNeutral": P["orange"], "ForegroundPositive": P["green"]},
               "WM": {"activeBackground": grey(P["window"]), "activeBlend": grey(over(P["label"], P["window"], ink)),
                      "activeForeground": grey(over(P["label"], P["window"], ink)), "inactiveBackground": grey(P["under"]),
                      "inactiveBlend": grey(over(P["tertiary"], P["under"], ink)), "inactiveForeground": grey(over(P["tertiary"], P["under"], ink))},
           }, base)


mac_scheme("KwickGlass", MAC, BREEZE)
mac_scheme("KwickGlassLight", MAC_LIGHT, BREEZE_LIGHT)

FLU = {"base": 32, "secondary": 28, "card": over(0x0D / 255, 32), "control": over(0x0F / 255, 32),
       "control2": over(0x15 / 255, 32), "alt": over(0x08 / 255, 28), "flyout": 44, "text2": 0xC5 / 255, "text3": 0x87 / 255,
       "ink": 255, "text": "255,255,255", "accent": "0,120,212", "accent_light2": "96,205,255", "accent_light3": "153,235,255",
       "success": "108,203,95", "caution": "252,225,0", "critical": "255,153,164"}
FLU_LIGHT = {"base": 243, "secondary": 249, "card": 251, "control": 251, "control2": 246, "alt": 243, "flyout": 249,
             "text2": 0x9E / 255, "text3": 0x72 / 255, "ink": 0, "text": "27,27,27", "accent": "0,120,212",
             "accent_light2": "0,95,184", "accent_light3": "0,62,146",
             "success": "15,123,15", "caution": "157,93,0", "critical": "196,43,28"}


def flu_fg(bg, F=FLU):
    return {"ForegroundNormal": F["text"], "ForegroundInactive": grey(over(F["text2"], bg, F["ink"])),
            "ForegroundActive": F["accent_light2"], "ForegroundLink": F["accent_light3"],
            "ForegroundNegative": F["critical"], "ForegroundNeutral": F["caution"], "ForegroundPositive": F["success"]}


def flu_scheme(name, F, base=None):
    dim = grey(over(F["text3"], F["base"], F["ink"]))
    scheme(name, grey(F["base"]), grey(F["card"]), grey(F["secondary"]), grey(F["alt"]),
           grey(F["control"]), grey(F["control2"]), F["accent"], F["accent_light2"], grey(F["base"]), {
               "Colors:Window": flu_fg(F["base"], F),
               "Colors:View": flu_fg(F["secondary"], F),
               "Colors:Button": flu_fg(F["control"], F),
               "Colors:Header": flu_fg(F["base"], F),
               "Colors:Header[Inactive]": flu_fg(F["base"], F),
               "Colors:Tooltip": dict(flu_fg(F["flyout"], F), BackgroundNormal=grey(F["flyout"]), BackgroundAlternate=grey(F["base"])),
               "Colors:Complementary": dict(flu_fg(F["secondary"], F), BackgroundNormal=grey(F["secondary"]), BackgroundAlternate=grey(F["base"])),
               "Colors:Selection": {"ForegroundNormal": "255,255,255", "ForegroundActive": "255,255,255", "ForegroundLink": "255,255,255"},
               "WM": {"activeBackground": grey(F["base"]), "activeBlend": F["text"], "activeForeground": F["text"],
                      "inactiveBackground": grey(F["base"]), "inactiveBlend": dim, "inactiveForeground": dim},
           }, base=base)


flu_scheme("KwickFluent", FLU)
flu_scheme("KwickFluentLight", FLU_LIGHT, BREEZE_LIGHT)
scheme("KwickDark", "22,23,31", "29,30,41", "17,18,26", "24,25,34", "35,37,50", "44,46,62",
       "94,129,244", "94,129,244", "26,27,37")
scheme("KwickLight", "239,240,244", "230,231,237", "255,255,255", "246,247,250", "251,251,253", "239,240,244",
       "46,125,233", "46,125,233", "228,230,236", base=BREEZE_LIGHT)


def svg_rect_path(x, y, wd, ht, rtl=0, rtr=0, fill="#000", op=1.0):
    d = f"M{x},{y + rtl} " + (f"A{rtl},{rtl} 0 0 1 {x + rtl},{y} " if rtl else f"L{x},{y} ")
    d += f"L{x + wd - rtr},{y} " + (f"A{rtr},{rtr} 0 0 1 {x + wd},{y + rtr} " if rtr else f"L{x + wd},{y} ")
    d += f"L{x + wd},{y + ht} L{x},{y + ht} Z"
    return f'<path d="{d}" fill="{fill}" fill-opacity="{op}"/>'


def aurorae(name, title_h, border, radius, bar_a, bar_i, edge, buttons, btn_w, btn_h, spacing, margin_top,
            align, text_a, text_i, rc_title_h=None, shadow=(6, 10, 14, 0.15, 0.08), sides=(1.0, 1.0, 1.0), cr=0, layout=None):
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

        def rstops(f=1.0, inner=0.0):
            pts = [(1 - o, v) for o, v in reversed(q)]
            if inner > 0:
                pts = [(0, pts[0][1])] + [(round(inner + o * (1 - inner), 4), v) for o, v in pts]
            return "".join(f'<stop offset="{o}" stop-color="#000" stop-opacity="{a * f * v:.4f}"/>' for o, v in pts)

        defs += (
            f'<linearGradient id="gl{k}" x1="0" y1="0" x2="1" y2="0">{stops(f=fs)}</linearGradient>'
            f'<linearGradient id="gr{k}" x1="0" y1="0" x2="1" y2="0">{stops(True, fs)}</linearGradient>'
            f'<linearGradient id="gt{k}" x1="0" y1="0" x2="0" y2="1">{stops(f=ft)}</linearGradient>'
            f'<linearGradient id="gb{k}" x1="0" y1="0" x2="0" y2="1">{stops(True, fb)}</linearGradient>'
        )
        for nm, cx, cy, sx, sy, f in (("rtl", ps + cr, pt + cr, ps, pt, (ft + fs) / 2), ("rtr", -cr, pt + cr, ps, pt, (ft + fs) / 2),
                                      ("rbl", ps + cr, -cr, ps, pb, (fb + fs) / 2), ("rbr", -cr, -cr, ps, pb, (fb + fs) / 2)):
            inner = cr / ((sx + sy) / 2 + cr) if cr else 0.0
            defs += f'<radialGradient id="{nm}{k}" gradientUnits="userSpaceOnUse" cx="0" cy="0" r="1" gradientTransform="translate({cx} {cy}) scale({sx + cr} {sy + cr})">{rstops(f, inner)}</radialGradient>'
        tl = f'<rect x="0" y="0" width="{ps}" height="{pt}" fill="url(#rtl{k})"/><rect x="0" y="{pt}" width="{ps}" height="{T}" fill="url(#gl{k})"/>' + (f'<rect x="{ps - ov}" y="{pt}" width="{ov}" height="{T + 1}" fill="{col}" fill-opacity="{op}"/>' if ov else "")
        tp = f'<rect x="0" y="0" width="8" height="{pt}" fill="url(#gt{k})"/>{svg_rect_path(0, pt, 8, T + 1, fill=col, op=op)}'
        tr = f'<rect x="0" y="0" width="{ps}" height="{pt}" fill="url(#rtr{k})"/><rect x="0" y="{pt}" width="{ps}" height="{T}" fill="url(#gr{k})"/>' + (f'<rect x="0" y="{pt}" width="{ov}" height="{T + 1}" fill="{col}" fill-opacity="{op}"/>' if ov else "")
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
    for prefix, y, (col, op) in (("decoration-maximized", 200, bar_a), ("decoration-maximized-inactive", 250, bar_i)):
        for i, nm in enumerate(("topleft", "top", "topright", "left", "right", "bottomleft", "bottom", "bottomright")):
            parts.append(f'<g id="{prefix}-{nm}"><rect x="{300 + 4 * i}" y="{y}" width="1" height="1" fill="#000" fill-opacity="0"/></g>')
        parts.append(f'<g id="{prefix}-center"><rect x="340" y="{y}" width="8" height="8" fill="{col}" fill-opacity="{op}"/></g>')
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
    rc = f"""[General]
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
"""
    for key, val in (layout or {}).items():
        rc = re.sub(rf"^{key}=.*$", f"{key}={val}", rc, flags=re.M) if re.search(rf"^{key}=", rc, re.M) else rc + f"{key}={val}\n"
    for key in ("TitleEdgeTop", "TitleEdgeBottom", "TitleEdgeLeft", "TitleEdgeRight", "ButtonMarginTop"):
        rc += f"{key}Maximized={re.search(rf'^{key}=(.*)$', rc, re.M).group(1)}\n"
    w(f"{d}/{name}rc", rc)
    w(f"{d}/metadata.json", json.dumps({"KPlugin": {"Id": name, "Name": name, "Description": "KwickOS window decoration",
                                                      "Authors": [{"Name": "KwickOS"}], "License": "MIT"}}, indent=2) + "\n")
    w(f"{d}/metadata.desktop", f"[Desktop Entry]\nName={name}\nComment=KwickOS window decoration\nX-KDE-PluginInfo-Name={name}\nX-KDE-PluginInfo-Author=KwickOS\nX-KDE-PluginInfo-License=MIT\n")


def mac_buttons(kind, st, idle="#4d4d4d"):
    col = {"close": "#ff5f57", "minimize": "#febc2e", "maximize": "#28c840", "restore": "#28c840"}.get(kind, "#98989d")
    if st in ("inactive", "deactivated"):
        col = idle
    glyph = ""
    if st in ("hover", "pressed"):
        g = {"close": "M4.2,4.2 L9.8,9.8 M9.8,4.2 L4.2,9.8", "minimize": "M3.5,7 L10.5,7",
             "maximize": "M7,3.5 L7,10.5 M3.5,7 L10.5,7", "restore": "M7,3.5 L7,10.5 M3.5,7 L10.5,7"}.get(kind, "")
        glyph = f'<path d="{g}" stroke="#2b1a18" stroke-width="1.5" stroke-linecap="round" fill="none"/>'
    shade = ' opacity="0.8"' if st == "pressed" else ""
    return f'<circle cx="7" cy="7" r="5.8" fill="{col}"{shade}/><circle cx="7" cy="7" r="5.8" fill="none" stroke="#000" stroke-opacity="0.25" stroke-width="0.6"/>{glyph}'


def win_buttons(kind, st, light=False):
    inactive = st in ("inactive", "deactivated")
    red = kind == "close" and st in ("hover", "pressed")
    fg = "#ffffff" if red else ("#a0a0a0" if light else "#717171") if inactive else "#1b1b1b" if light else "#ffffff"
    tint = "#000000" if light else "#ffffff"
    bg = ""
    if st == "hover":
        bg = '<rect width="46" height="32" fill="%s" fill-opacity="%s"/>' % ("#c42b1c" if red else tint, "1" if red else "0.0373" if light else "0.0588")
    if st == "pressed":
        bg = '<rect width="46" height="32" fill="%s" fill-opacity="%s"/>' % ("#c42b1c" if red else tint, "0.9" if red else "0.0241" if light else "0.0392")
    g = {"close": "M18.5,11.5 L27.5,20.5 M27.5,11.5 L18.5,20.5", "minimize": "M18,16.5 L28,16.5",
         "maximize": "M18.5,11.5 H27.5 V20.5 H18.5 Z", "restore": "M20.5,13.5 H27.5 V20.5 H20.5 Z M22.5,11.5 H29.5 V18.5"}.get(kind, "")
    return f'{bg}<path d="{g}" stroke="{fg}" stroke-width="1" fill="none" stroke-linecap="square"/>'


aurorae("KwickGlass", 34, 1, 10, ("#323232", 1), ("#282828", 1), ("#323232", 1),
        mac_buttons, 14, 14, 5, 7, "Center", grey(over(MAC["label"], MAC["window"])),
        grey(over(MAC["tertiary"], MAC["under"])), 28, shadow=(30, 46, 64, 0.40, 0.20), cr=10)
aurorae("KwickGlassLight", 34, 1, 10, ("#ececec", 1), ("#f6f6f6", 1), ("#ececec", 1),
        lambda kind, st: mac_buttons(kind, st, "#d1d1d1"), 14, 14, 5, 7, "Center", grey(over(MAC_LIGHT["label"], MAC_LIGHT["window"], 0)),
        grey(over(MAC_LIGHT["tertiary"], MAC_LIGHT["under"], 0)), 28, shadow=(30, 46, 64, 0.30, 0.14), cr=10)
FLU_CAPTION = {"TitleEdgeLeft": 16, "TitleEdgeRight": 0, "TitleBorderLeft": 16, "ButtonWidthMenu": 16, "ExplicitButtonSpacer": 0}
aurorae("KwickFluent", 32, 1, 8, ("#202020", 1), ("#202020", 1), ("#202020", 1),
        win_buttons, 46, 32, 0, 0, "Left", "255,255,255", grey(over(FLU["text3"], FLU["base"])), layout=FLU_CAPTION)
aurorae("KwickFluentLight", 32, 1, 8, ("#f3f3f3", 1), ("#f3f3f3", 1), ("#f3f3f3", 1),
        lambda kind, st: win_buttons(kind, st, True), 46, 32, 0, 0, "Left", FLU_LIGHT["text"],
        grey(over(FLU_LIGHT["text3"], FLU_LIGHT["base"], 0)), shadow=(6, 10, 14, 0.12, 0.06), layout=FLU_CAPTION)


def frame_svg(r, fill, op, stroke=None, stroke_op=0.0, prefix="", margins=(4, 4, 4, 4), bottom_extra="", ox=0, oy=0, edge=None, inset=0, bw=64):
    e = edge or r or 4
    pieces = []

    def piece(name, x, y, wd, ht, body):
        if inset and name.startswith(("top", "bottom")):
            shift = f' transform="translate(0 {inset})"' if name.startswith("top") else ""
            body = f'<g{shift}>{body}</g>'
            y, ht = y, ht + inset
        pieces.append(f'<g id="{prefix}{name}"><rect x="{x}" y="{y}" width="{wd}" height="{ht}" fill="#000" fill-opacity="0"/>{body}</g>')

    f = f'fill="{fill}" fill-opacity="{op}"'
    s = f'stroke="{stroke}" stroke-opacity="{stroke_op}" stroke-width="1" fill="none"' if stroke else ""
    rf = f'fill="{stroke}" fill-opacity="{stroke_op}"'
    x0, y0 = ox, oy
    if r:
        x, y, X, Y, p = x0, y0, x0 + 40, y0 + 40, r - 1
        piece("topleft", x, y, e, e, f'<path d="M{x},{y + e} L{x},{y + r} A{r},{r} 0 0 1 {x + r},{y} L{x + e},{y} L{x + e},{y + e} Z" {f}/>' +
              (f'<path d="M{x},{y + e} L{x},{y + r} A{r},{r} 0 0 1 {x + r},{y} L{x + e},{y} L{x + e},{y + 1} L{x + r},{y + 1} A{p},{p} 0 0 0 {x + 1},{y + r} L{x + 1},{y + e} Z" {rf}/>' if s else ""))
        piece("topright", X, y, e, e, f'<path d="M{X},{y} L{X + e - r},{y} A{r},{r} 0 0 1 {X + e},{y + r} L{X + e},{y + e} L{X},{y + e} Z" {f}/>' +
              (f'<path d="M{X},{y} L{X + e - r},{y} A{r},{r} 0 0 1 {X + e},{y + r} L{X + e},{y + e} L{X + e - 1},{y + e} L{X + e - 1},{y + r} A{p},{p} 0 0 0 {X + e - r},{y + 1} L{X},{y + 1} Z" {rf}/>' if s else ""))
        piece("bottomleft", x, Y, e, e, f'<path d="M{x},{Y} L{x + e},{Y} L{x + e},{Y + e} L{x + r},{Y + e} A{r},{r} 0 0 1 {x},{Y + e - r} Z" {f}/>' +
              (f'<path d="M{x},{Y} L{x + 1},{Y} L{x + 1},{Y + e - r} A{p},{p} 0 0 0 {x + r},{Y + e - 1} L{x + e},{Y + e - 1} L{x + e},{Y + e} L{x + r},{Y + e} A{r},{r} 0 0 1 {x},{Y + e - r} Z" {rf}/>' if s else ""))
        piece("bottomright", X, Y, e, e, f'<path d="M{X},{Y} L{X + e},{Y} L{X + e},{Y + e - r} A{r},{r} 0 0 1 {X + e - r},{Y + e} L{X},{Y + e} Z" {f}/>' +
              (f'<path d="M{X + e},{Y} L{X + e},{Y + e - r} A{r},{r} 0 0 1 {X + e - r},{Y + e} L{X},{Y + e} L{X},{Y + e - 1} L{X + e - r},{Y + e - 1} A{p},{p} 0 0 0 {X + e - 1},{Y + e - r} L{X + e - 1},{Y} Z" {rf}/>' if s else ""))
    else:
        for nm, x, y in (("topleft", x0, y0), ("topright", x0 + 40, y0), ("bottomleft", x0, y0 + 40), ("bottomright", x0 + 40, y0 + 40)):
            piece(nm, x, y, e, e, f'<rect x="{x}" y="{y}" width="{e}" height="{e}" {f}/>' if op else "")
    line = lambda x1, y1, x2, y2: (f'<rect x="{min(x1, x2) - (0.5 if x1 == x2 else 0)}" y="{min(y1, y2) - (0.5 if y1 == y2 else 0)}" width="{abs(x2 - x1) or 1}" height="{abs(y2 - y1) or 1}" fill="{stroke}" fill-opacity="{stroke_op}"/>' if s and r else "")
    piece("top", x0 + 20, y0, 10, e, f'<rect x="{x0 + 20}" y="{y0}" width="10" height="{e}" {f}/>' + line(x0 + 20, y0 + 0.5, x0 + 30, y0 + 0.5))
    piece("bottom", x0 + 20, y0 + 40, 10 if not bottom_extra else bw, e, f'<rect x="{x0 + 20}" y="{y0 + 40}" width="{10 if not bottom_extra else bw}" height="{e}" {f}/>' +
          line(x0 + 20, y0 + 40 + e - 0.5, x0 + 30, y0 + 40 + e - 0.5) + bottom_extra.format(x=x0 + 20, y=y0 + 40))
    piece("left", x0, y0 + 20, e, 10, f'<rect x="{x0}" y="{y0 + 20}" width="{e}" height="10" {f}/>' + line(x0 + 0.5, y0 + 20, x0 + 0.5, y0 + 30))
    piece("right", x0 + 40, y0 + 20, e, 10, f'<rect x="{x0 + 40}" y="{y0 + 20}" width="{e}" height="10" {f}/>' + line(x0 + 40 + e - 0.5, y0 + 20, x0 + 40 + e - 0.5, y0 + 30))
    piece("center", x0 + 20, y0 + 20, 10, 10, f'<rect x="{x0 + 20}" y="{y0 + 20}" width="10" height="10" {f}/>')
    for side, m in zip(("top", "bottom", "left", "right"), margins):
        pieces.append(f'<rect id="{prefix}hint-{side}-margin" x="{x0 + 100}" y="{y0}" width="{m}" height="{m}" fill="#000" fill-opacity="0"/>')
    return "".join(pieces)


def shadow_svg(size, alpha, oy=0):
    q = [(o, math.exp(-((1 - o) * 2.15) ** 2) if o > 0 else 0.0) for o in (0, 0.15, 0.3, 0.45, 0.6, 0.72, 0.84, 0.93, 1)]

    def stops(f):
        return "".join(f'<stop offset="{o}" stop-color="#000" stop-opacity="{alpha * f * v:.4f}"/>' for o, v in q)

    t, b = size - oy, size + oy
    defs = (f'<linearGradient id="sh-t" x1="0" y1="0" x2="0" y2="1">{stops(0.6)}</linearGradient>'
            f'<linearGradient id="sh-b" x1="0" y1="1" x2="0" y2="0">{stops(1)}</linearGradient>'
            f'<linearGradient id="sh-l" x1="0" y1="0" x2="1" y2="0">{stops(0.8)}</linearGradient>'
            f'<linearGradient id="sh-r" x1="1" y1="0" x2="0" y2="0">{stops(0.8)}</linearGradient>')
    pieces, x0 = [], 600
    for nm, x, y, wd, ht, cx, cy, f in (("topleft", 0, 0, size, t, size, t, 0.7), ("topright", 80, 0, size, t, 0, t, 0.7),
                                        ("bottomleft", 0, 80, size, b, size, 0, 0.9), ("bottomright", 80, 80, size, b, 0, 0, 0.9)):
        defs += (f'<radialGradient id="sh-{nm}" gradientUnits="userSpaceOnUse" cx="0" cy="0" r="1" '
                 f'gradientTransform="translate({x0 + x + cx} {y + cy}) scale({wd} {ht})">'
                 + "".join(f'<stop offset="{1 - o}" stop-color="#000" stop-opacity="{alpha * f * v:.4f}"/>' for o, v in reversed(q))
                 + '</radialGradient>')
        pieces.append(f'<rect id="shadow-{nm}" x="{x0 + x}" y="{y}" width="{wd}" height="{ht}" fill="url(#sh-{nm})"/>')
    pieces += [f'<rect id="shadow-top" x="{x0 + 40}" y="0" width="10" height="{t}" fill="url(#sh-t)"/>',
               f'<rect id="shadow-bottom" x="{x0 + 40}" y="80" width="10" height="{b}" fill="url(#sh-b)"/>',
               f'<rect id="shadow-left" x="{x0}" y="40" width="{size}" height="10" fill="url(#sh-l)"/>',
               f'<rect id="shadow-right" x="{x0 + 80}" y="40" width="{size}" height="10" fill="url(#sh-r)"/>']
    pieces += [f'<rect id="shadow-hint-{side}-margin" x="{x0 + 150}" y="0" width="1" height="1" fill="#000" fill-opacity="0"/>'
               for side in ("top", "bottom", "left", "right")]
    return f"<defs>{defs}</defs>" + "".join(pieces)


def plasma_theme(name, title, panel, tasks, menubar=None, tabbar=None, dialog=None, tooltip=None, blur=True):
    d = f"usr/share/plasma/desktoptheme/{name}"
    w(f"{d}/metadata.json", json.dumps({"KPlugin": {"Authors": [{"Name": "KwickOS"}], "Description": f"{title} panels for KwickOS",
                                                     "Id": name, "License": "MIT", "Name": title, "Version": "1.0"},
                                         "X-Plasma-API": "5.0"}, indent=4) + "\n")
    w(f"{d}/plasmarc", f"[ContrastEffect]\nenabled=false\n\n[BlurBehindEffect]\nenabled={str(blur).lower()}\n\n[AdaptiveTransparency]\nenabled=true\n")
    head = '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400" viewBox="0 0 400 400">'
    for sub, op in (("widgets", 1.0), ("translucent/widgets", panel["op"]), ("opaque/widgets", 1.0), ("solid/widgets", 1.0)):
        body = frame_svg(panel["r"], panel["fill"], op, panel.get("stroke"), panel.get("stroke_op", 0), margins=panel["margins"])
        body += frame_svg(panel["r"], panel["fill"], panel.get("edge_op", op), prefix="north-", ox=200, margins=panel.get("north_margins", panel["margins"]))
        body += frame_svg(panel["r"], "#000", 1.0, prefix="mask-", oy=200, margins=panel["margins"])
        w(f"{d}/{sub}/panel-background.svg", head + body + "</svg>\n")
    body = '<rect id="hint-stretch-borders" x="380" y="380" width="4" height="4" fill="#000" fill-opacity="0"/>'
    for i, (state, spec) in enumerate(tasks.items()):
        body += frame_svg(spec.get("r", 0), spec.get("fill", "#ffffff"), spec.get("op", 0.0), prefix=f"{state}-",
                          margins=spec.get("margins", (4, 4, 4, 4)), bottom_extra=spec.get("mark", ""), bw=spec.get("bw", 64), ox=0, oy=i * 80,
                          edge=spec.get("edge", 6), inset=spec.get("inset", 0))
    w(f"{d}/widgets/tasks.svg", head.replace('height="400"', 'height="420"').replace("0 0 400 400", "0 0 400 420") + body + "</svg>\n")
    if menubar:
        body = ""
        for i, (state, spec) in enumerate(menubar.items()):
            body += frame_svg(spec.get("r", 0), spec.get("fill", "#ffffff"), spec.get("op", 0.0), prefix=f"{state}-",
                              margins=spec.get("margins", (4, 4, 8, 8)), ox=0, oy=i * 80, edge=spec.get("edge", 6), inset=spec.get("inset", 0))
        w(f"{d}/widgets/menubaritem.svg", head + body + "</svg>\n")
    if tabbar:
        body = "".join(frame_svg(tabbar.get("r", 0), tabbar.get("fill", "#ffffff"), tabbar.get("op", 0.0), prefix=f"{side}-active-tab-",
                                 margins=(4, 4, 4, 4), oy=i * 80, edge=tabbar.get("edge", 6), inset=tabbar.get("inset", 0))
                       for i, side in enumerate(("north", "south", "west", "east")))
        w(f"{d}/widgets/tabbar.svg", head + body + "</svg>\n")
    wide = head.replace('width="400"', 'width="800"').replace("0 0 400 400", "0 0 800 400")
    for path, spec in (("dialogs/background", dialog), ("widgets/tooltip", tooltip)):
        if spec:
            body = frame_svg(spec["r"], spec["fill"], spec["op"], spec.get("stroke"), spec.get("stroke_op", 0), margins=spec["margins"])
            body += frame_svg(spec["r"], "#000", 1.0, prefix="mask-", oy=200, margins=spec["margins"])
            w(f"{d}/{path}.svg", wide + body + shadow_svg(*spec["shadow"]) + "</svg>\n")


def dot(col, op, size=4, h=6):
    return (f'<circle cx="{{x}}" cy="{{y}}" r="{size / 2}" fill="{col}" fill-opacity="{op}" '
            f'transform="translate(32 {h - size / 2 - 1})"/>')


def pill(col, wd, ht, h=6, bw=64):
    return f'<rect x="{{x}}" y="{{y}}" width="{wd}" height="{ht}" rx="{ht / 2}" fill="{col}" transform="translate({bw / 2 - wd / 2} {h - ht - 1})"/>'


mac_dot = dot("#ffffff", 0.55)
plasma_theme("kwick-glass", "KwickGlass",
             {"r": 18, "fill": "#323232", "op": 0.55, "edge_op": 0, "stroke": "#ffffff", "stroke_op": 0.15, "margins": (2, 2, 6, 6), "north_margins": (5, 5, 6, 6)},
             {"normal": {"mark": mac_dot}, "focus": {"mark": mac_dot}, "minimized": {"mark": mac_dot},
              "hover": {}, "attention": {"mark": dot("#ff9f0a", 1.0)}},
             {"normal": {"inset": 4}, "hover": {"r": 6, "edge": 6, "op": 0.2, "inset": 4}, "pressed": {"r": 6, "edge": 6, "op": 0.24, "inset": 4}},
             {"r": 6, "edge": 6, "op": 0.24, "inset": 4}, blur=False)
mac_dot_light = dot("#000000", 0.45)
plasma_theme("kwick-glass-light", "KwickGlass Light",
             {"r": 18, "fill": "#f6f6f6", "op": 0.6, "edge_op": 0, "stroke": "#000000", "stroke_op": 0.12, "margins": (2, 2, 6, 6), "north_margins": (5, 5, 6, 6)},
             {"normal": {"mark": mac_dot_light}, "focus": {"mark": mac_dot_light}, "minimized": {"mark": mac_dot_light},
              "hover": {}, "attention": {"mark": dot("#ff9500", 1.0)}},
             {"normal": {"inset": 4}, "hover": {"r": 6, "edge": 6, "op": 0.2, "inset": 4}, "pressed": {"r": 6, "edge": 6, "op": 0.24, "inset": 4}},
             {"r": 6, "edge": 6, "fill": "#000000", "op": 0.12, "inset": 4}, blur=False)


def fluent_theme(name, title, bar, bar_op, fill, tint, hover, idle, accent, warn, flyout, stroke, stroke_op, shade):
    task = {"r": 4, "edge": 6, "fill": tint, "op": hover, "inset": 4, "margins": (12, 12, 10, 10), "bw": 36}
    plasma_theme(name, title,
                 {"r": 0, "fill": bar, "op": bar_op, "margins": (4, 4, 4, 4)},
                 {"normal": dict(task, op=0.0, mark=pill(idle, 6, 3, bw=36)), "minimized": dict(task, op=0.0, mark=pill(idle, 6, 3, bw=36)),
                  "focus": dict(task, op=hover * 0.75, mark=pill(accent, 16, 3, bw=36)), "hover": task,
                  "attention": dict(task, mark=pill(warn, 16, 3, bw=36))},
                 dialog={"r": 8, "fill": fill, "op": 0.94, "stroke": stroke, "stroke_op": stroke_op, "margins": (1, 1, 1, 1),
                         "shadow": (28, shade, 6)},
                 tooltip={"r": 4, "fill": flyout, "op": 1.0, "stroke": stroke, "stroke_op": stroke_op, "margins": (8, 8, 10, 10),
                          "shadow": (10, shade * 0.6, 2)})


fluent_theme("kwick-fluent", "KwickFluent", "#202020", 0.85, "#242424", "#ffffff", 0x0F / 255, "#9d9d9d", "#60cdff", "#fce100",
             "#2c2c2c", "#ffffff", 0.08, 0.32)
fluent_theme("kwick-fluent-light", "KwickFluent Light", "#eeeeee", 0.93, "#f2f2f2", "#000000", 0x09 / 255, "#868686", "#005fb8", "#9d5d00",
             "#f9f9f9", "#000000", 0.07, 0.18)


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
