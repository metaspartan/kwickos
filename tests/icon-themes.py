#!/usr/bin/env python3
import configparser, os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
ICONS = os.path.join(ROOT, "desktop", "rootfs", "usr", "share", "icons")
XBEL = os.path.join(ROOT, "desktop", "rootfs", "usr", "share", "kwick", "files", "common", "user-places.xbel")
SIDEBAR_SIZE = 22

fail = 0


def bad(msg):
    global fail
    print("FAIL  " + msg)
    fail = 1


def lookup(theme, cfg, name, size):
    for d in [x for x in cfg["Icon Theme"]["Directories"].split(",") if x]:
        s = cfg[d]
        if not (int(s.get("MinSize", s["Size"])) <= size <= int(s.get("MaxSize", s["Size"]))):
            continue
        p = os.path.join(ICONS, theme, d, name + ".svg")
        if os.path.isfile(p):
            return p
    return None


def symbolic(path):
    return bool(re.search(r'class="ColorScheme-[A-Za-z]+"', open(path, encoding="utf-8").read()))


names = ["user-trash", "user-trash-full"]
if os.path.isfile(XBEL):
    names += sorted(set(re.findall(r'bookmark:icon name="([^"]+)"', open(XBEL, encoding="utf-8").read())))
for theme in ("KwickOS", "KwickOS-Fluent", "KwickOS-Linux"):
    cfg = configparser.ConfigParser(interpolation=None)
    cfg.optionxform = str
    cfg.read(os.path.join(ICONS, theme, "index.theme"), encoding="utf-8")
    for d in [x for x in cfg["Icon Theme"]["Directories"].split(",") if x]:
        if d not in cfg:
            bad("%s: directory %s has no section in index.theme" % (theme, d))
        elif not os.path.isdir(os.path.join(ICONS, theme, d)):
            bad("%s: directory %s is listed but missing" % (theme, d))
    for n in names:
        p = lookup(theme, cfg, n, SIDEBAR_SIZE)
        if not p:
            bad("%s: no %s at sidebar size %d" % (theme, n, SIDEBAR_SIZE))
        elif not symbolic(p):
            bad("%s: %s at sidebar size is a full-colour icon (%s); file manager sidebars show it next to the neutral glyphs" % (theme, n, os.path.relpath(p, ICONS)))
    for n in ("user-trash", "user-trash-full"):
        p = lookup(theme, cfg, n, 48)
        if not p or os.path.basename(os.path.dirname(os.path.dirname(p))) != "scalable":
            bad("%s: %s at dock size should come from scalable/places, not the small sidebar glyphs" % (theme, n))
print("ok" if not fail else "icon themes are wrong")
sys.exit(fail)
