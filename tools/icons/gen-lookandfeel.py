#!/usr/bin/env python3
"""Generate the three KwickOS Plasma global themes. usage: gen-lookandfeel.py <repo-root>"""
import json, os, shutil, sys

ROOT = sys.argv[1]
LNF = os.path.join(ROOT, "desktop/rootfs/usr/share/plasma/look-and-feel")

THEMES = {
    "macos": dict(name="KwickOS macOS", desc="Liquid glass: floating menu bar and dock, traffic lights, Inter",
                  scheme="KwickGlass", accent="10,132,255", lib="org.kde.kwin.aurorae", deco="__aurorae__svg__KwickGlass",
                  left="XIA", right="", wall="KwickGlass", ui="Inter", mono="JetBrains Mono", icons="KwickOS"),
    "windows": dict(name="KwickOS Windows", desc="Windows 11 style: centered taskbar, Fluent caption buttons, Selawik",
                    scheme="KwickFluent", accent="0,120,212", lib="org.kde.kwin.aurorae", deco="__aurorae__svg__KwickFluent",
                    left="M", right="IAX", wall="KwickFluent", ui="Selawik", mono="Cascadia Code", icons="KwickOS-Fluent"),
    "linux": dict(name="KwickOS Linux", desc="Classic Linux desktop: top panel, Breeze buttons, Ubuntu Sans",
                  scheme="KwickDark", accent="94,129,244", lib="org.kde.breeze", deco="Breeze",
                  left="M", right="IAX", wall="KwickOS", ui="Ubuntu Sans", mono="Ubuntu Sans Mono", icons="KwickOS-Linux"),
}

for old in ("org.kwickos.desktop",):
    shutil.rmtree(os.path.join(LNF, old), ignore_errors=True)

for key, t in THEMES.items():
    base = os.path.join(LNF, f"org.kwickos.{key}")
    os.makedirs(os.path.join(base, "contents/layouts"), exist_ok=True)
    os.makedirs(os.path.join(base, "contents/previews"), exist_ok=True)
    meta = {
        "KPackageStructure": "Plasma/LookAndFeel",
        "KPlugin": {
            "Authors": [{"Name": "KwickOS"}],
            "Category": "",
            "Description": t["desc"],
            "Id": f"org.kwickos.{key}",
            "License": "MIT",
            "Name": t["name"],
            "Version": "1.0",
            "Website": "https://github.com/metaspartan/kwickos",
        },
        "X-Plasma-APIVersion": "2",
    }
    with open(os.path.join(base, "metadata.json"), "w", newline="\n") as f:
        json.dump(meta, f, indent=4)
        f.write("\n")
    font = lambda n, w=400, pt=10: f"{n},{pt},-1,5,{w},0,0,0,0,0,0,0,0,0,0,1"
    defaults = f"""[kdeglobals][KDE]
widgetStyle=Breeze

[kdeglobals][General]
ColorScheme={t['scheme']}
AccentColor={t['accent']}
font={font(t['ui'])}
menuFont={font(t['ui'])}
toolBarFont={font(t['ui'])}
smallestReadableFont={font(t['ui'], pt=8)}
fixed={font(t['mono'])}

[kdeglobals][WM]
activeFont={font(t['ui'], 600)}

[kdeglobals][Icons]
Theme={t['icons']}

[plasmarc][Theme]
name=default

[kcminputrc][Mouse]
cursorTheme=breeze_cursors

[kwinrc][WindowSwitcher]
LayoutName=thumbnail_grid

[kwinrc][org.kde.kdecoration2]
library={t['lib']}
theme={t['deco']}
ButtonsOnLeft={t['left']}
ButtonsOnRight={t['right']}

[Wallpaper]
Image={t['wall']}
"""
    with open(os.path.join(base, "contents/defaults"), "w", newline="\n") as f:
        f.write(defaults)
    with open(os.path.join(ROOT, f"desktop/rootfs/usr/share/kwick/plasma/{key}.js")) as src:
        js = src.read()
    with open(os.path.join(base, "contents/layouts/org.kde.plasma.desktop-layout.js"), "w", newline="\n") as f:
        f.write(js)
