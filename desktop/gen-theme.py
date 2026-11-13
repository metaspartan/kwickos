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


# ----------------------------------------------------------------- color schemes
def scheme(name, win, win_alt, view, view_alt, btn, btn_alt, accent, focus, header):
    out, grp = [], None
    for line in BREEZE.splitlines():
        m = re.match(r"\[(.*?)\](\[.*?\])?$", line)
        if m:
            grp = m.group(1)
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
        elif grp == "Colors:Header":
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
        out.append(f"{key}={rep}" if rep else line)
    w(f"usr/share/color-schemes/{name}.colors", "\n".join(out) + "\n")


scheme("KwickGlass", "29,30,36", "36,37,45", "22,23,29", "28,29,36", "46,47,56", "56,57,68",
       "10,132,255", "10,132,255", "33,34,41")
scheme("KwickFluent", "32,32,32", "39,39,39", "28,28,28", "35,35,35", "45,45,45", "55,55,55",
       "0,120,212", "96,205,255", "32,32,32")
scheme("KwickDark", "22,23,31", "29,30,41", "17,18,26", "24,25,34", "35,37,50", "44,46,62",
       "94,129,244", "94,129,244", "26,27,37")


# ------------------------------------------------------------- aurorae decorations
def svg_rect_path(x, y, wd, ht, rtl=0, rtr=0, fill="#000", op=1.0):
    d = f"M{x},{y + rtl} " + (f"A{rtl},{rtl} 0 0 1 {x + rtl},{y} " if rtl else f"L{x},{y} ")
    d += f"L{x + wd - rtr},{y} " + (f"A{rtr},{rtr} 0 0 1 {x + wd},{y + rtr} " if rtr else f"L{x + wd},{y} ")
    d += f"L{x + wd},{y + ht} L{x},{y + ht} Z"
    return f'<path d="{d}" fill="{fill}" fill-opacity="{op}"/>'


def aurorae(name, title_h, border, radius, bar_a, bar_i, edge, buttons, btn_w, btn_h, spacing, margin_top,
            align, text_a, text_i):
    """buttons: callable(kind, state) -> svg fragment drawn in a (btn_w x btn_h) box at 0,0."""
    parts = ['<svg xmlns="http://www.w3.org/2000/svg" width="640" height="320" viewBox="0 0 640 320">']
    for prefix, y, bar in (("decoration", 0, bar_a), ("decoration-inactive", 60, bar_i)):
        col, op = bar
        parts.append(f'<g id="{prefix}-topleft"><g transform="translate(0,{y})">{svg_rect_path(0, 0, radius, title_h, rtl=radius, fill=col, op=op)}</g></g>')
        parts.append(f'<g id="{prefix}-top"><g transform="translate(30,{y})">{svg_rect_path(0, 0, 8, title_h, fill=col, op=op)}</g></g>')
        parts.append(f'<g id="{prefix}-topright"><g transform="translate(60,{y})">{svg_rect_path(0, 0, radius, title_h, rtr=radius, fill=col, op=op)}</g></g>')
        parts.append(f'<g id="{prefix}-left"><g transform="translate(90,{y})"><rect width="{border}" height="8" fill="{edge[0]}" fill-opacity="{edge[1]}"/></g></g>')
        parts.append(f'<g id="{prefix}-center"><g transform="translate(110,{y})"><rect width="8" height="8" fill="#000" fill-opacity="0"/></g></g>')
        parts.append(f'<g id="{prefix}-right"><g transform="translate(130,{y})"><rect width="{border}" height="8" fill="{edge[0]}" fill-opacity="{edge[1]}"/></g></g>')
        parts.append(f'<g id="{prefix}-bottomleft"><g transform="translate(150,{y})"><rect width="{border}" height="{border}" fill="{edge[0]}" fill-opacity="{edge[1]}"/></g></g>')
        parts.append(f'<g id="{prefix}-bottom"><g transform="translate(170,{y})"><rect width="8" height="{border}" fill="{edge[0]}" fill-opacity="{edge[1]}"/></g></g>')
        parts.append(f'<g id="{prefix}-bottomright"><g transform="translate(190,{y})"><rect width="{border}" height="{border}" fill="{edge[0]}" fill-opacity="{edge[1]}"/></g></g>')
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
BorderLeft={border}
BorderRight={border}
BorderBottom={border}
TitleEdgeTop=0
TitleEdgeBottom=0
TitleEdgeLeft=12
TitleEdgeRight=12
TitleBorderLeft=0
TitleBorderRight=0
TitleHeight={title_h}
ButtonWidth={btn_w}
ButtonHeight={btn_h}
ButtonSpacing={spacing}
ButtonMarginTop={margin_top}
ExplicitButtonSpacer=6
PaddingTop=0
PaddingLeft=0
PaddingRight=0
PaddingBottom=0
""")
    w(f"{d}/metadata.json", json.dumps({"KPlugin": {"Id": name, "Name": name, "Description": "KwickOS window decoration",
                                                      "Authors": [{"Name": "KwickOS"}], "License": "MIT"}}, indent=2) + "\n")
    w(f"{d}/metadata.desktop", f"[Desktop Entry]\nName={name}\nComment=KwickOS window decoration\nX-KDE-PluginInfo-Name={name}\nX-KDE-PluginInfo-Author=KwickOS\nX-KDE-PluginInfo-License=MIT\n")


def mac_buttons(kind, st):
    col = {"close": "#ff5f57", "minimize": "#febc2e", "maximize": "#28c840", "restore": "#28c840"}.get(kind, "#8e8e93")
    if st in ("inactive", "deactivated"):
        col = "#58585d"
    glyph = ""
    if st in ("hover", "pressed"):
        g = {"close": "M4.2,4.2 L9.8,9.8 M9.8,4.2 L4.2,9.8", "minimize": "M3.5,7 L10.5,7",
             "maximize": "M7,3.5 L7,10.5 M3.5,7 L10.5,7", "restore": "M7,3.5 L7,10.5 M3.5,7 L10.5,7"}.get(kind, "")
        glyph = f'<path d="{g}" stroke="#2b1a18" stroke-width="1.5" stroke-linecap="round" fill="none"/>'
    shade = ' opacity="0.8"' if st == "pressed" else ""
    return f'<circle cx="7" cy="7" r="6.5" fill="{col}"{shade}/><circle cx="7" cy="7" r="6.5" fill="none" stroke="#000" stroke-opacity="0.25" stroke-width="0.6"/>{glyph}'


def win_buttons(kind, st):
    inactive = st in ("inactive", "deactivated")
    fg = "#7a7a7a" if inactive else "#ffffff"
    bg = ""
    if st == "hover":
        bg = '<rect width="46" height="34" fill="%s"/>' % ("#c42b1c" if kind == "close" else "#ffffff")
        bg = bg.replace("/>", ' fill-opacity="%s"/>' % ("1" if kind == "close" else "0.09"))
    if st == "pressed":
        bg = '<rect width="46" height="34" fill="%s" fill-opacity="%s"/>' % ("#b32b1c" if kind == "close" else "#ffffff", "1" if kind == "close" else "0.05")
    g = {"close": "M18.5,12.5 L27.5,21.5 M27.5,12.5 L18.5,21.5", "minimize": "M18,17.5 L28,17.5",
         "maximize": "M18.5,12.5 H27.5 V21.5 H18.5 Z", "restore": "M20.5,14.5 H27.5 V21.5 H20.5 Z M22.5,12.5 H29.5 V19.5"}.get(kind, "")
    return f'{bg}<path d="{g}" stroke="{fg}" stroke-width="1" fill="none" stroke-linecap="square"/>'


aurorae("KwickGlass", 34, 1, 12, ("#262730", 0.80), ("#202129", 0.70), ("#ffffff", 0.10),
        mac_buttons, 14, 14, 8, 10, "Center", "235,235,245", "130,130,145")
aurorae("KwickFluent", 34, 1, 8, ("#202020", 0.96), ("#2b2b2b", 0.96), ("#ffffff", 0.08),
        win_buttons, 46, 34, 0, 0, "Left", "255,255,255", "140,140,140")


# ------------------------------------------------------------------- wallpapers
def wallpaper(name, painter, size=(2560, 1440)):
    from PIL import Image, ImageFilter
    img = painter(size)
    rnd = Image.effect_noise(size, 12).convert("RGB")  # break up banding
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
    s = 4  # draw small, blur, upscale (soft, fast)
    base = Image.new("RGB", (W // s, H // s), (9, 10, 22))
    blobs = [(0.18, 0.25, 0.42, (40, 60, 190)), (0.72, 0.20, 0.38, (120, 60, 200)), (0.55, 0.78, 0.46, (20, 120, 200)),
             (0.10, 0.85, 0.30, (70, 40, 150)), (0.92, 0.75, 0.28, (30, 90, 170))]
    for cx, cy, r, col in blobs:
        layer = Image.new("RGB", base.size, (0, 0, 0))
        ld = ImageDraw.Draw(layer)
        for k in range(24, 0, -1):  # big -> small, each ellipse overwrites: smooth radial falloff
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

# ---------------------------------------------------------------------- konsole
cs = """[Background]
Color=16,17,24

[BackgroundFaint]
Color=16,17,24

[BackgroundIntense]
Color=24,25,34

[Foreground]
Color=226,228,240

[ForegroundFaint]
Color=150,153,170

[ForegroundIntense]
Color=255,255,255
"""
pal = [(30, 32, 44), (255, 95, 109), (80, 214, 140), (255, 200, 87), (86, 156, 255), (190, 130, 255), (70, 210, 220), (210, 214, 228)]
palI = [(90, 94, 112), (255, 128, 140), (120, 235, 170), (255, 220, 130), (130, 185, 255), (212, 165, 255), (120, 230, 238), (255, 255, 255)]
for i, c in enumerate(pal):
    cs += f"\n[Color{i}]\nColor={c[0]},{c[1]},{c[2]}\n\n[Color{i}Faint]\nColor={c[0]},{c[1]},{c[2]}\n\n[Color{i}Intense]\nColor={palI[i][0]},{palI[i][1]},{palI[i][2]}\n"
cs += "\n[General]\nBlur=true\nColorRandomization=false\nDescription=KwickOS Glass\nOpacity=0.82\nWallpaper=\n"
w("usr/share/konsole/KwickGlass.colorscheme", cs)
w("usr/share/konsole/KwickOS.profile", "[Appearance]\nColorScheme=KwickGlass\nFont=JetBrains Mono,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1\nTerminalMargin=14\nTerminalCenter=false\n\n[General]\nName=KwickOS\nParent=FALLBACK/\n\n[Scrolling]\nScrollBarPosition=2\n\n[Terminal Features]\nBlinkingCursorEnabled=true\n")
w("etc/xdg/konsolerc", "[Desktop Entry]\nDefaultProfile=KwickOS.profile\n\n[KonsoleWindow]\nShowMenuBarByDefault=false\n")

# ------------------------------------------------------------------------ icons
# Reuse the traced Flux K/lightning mark everywhere; never regenerate a
# substitute logo or a platform vendor's trademark here.
logo = os.path.join(ROOT, "docs/img/kwickos-logo.svg")
for name in ("kwickos-logo", "kwick-start", "kwick-start-fluent"):
    target = os.path.join(R, f"usr/share/icons/hicolor/scalable/apps/{name}.svg")
    os.makedirs(os.path.dirname(target), exist_ok=True)
    shutil.copyfile(logo, target)
print("theme assets written")
