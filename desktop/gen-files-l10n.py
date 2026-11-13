#!/usr/bin/env python3
"""Generate the KwickOS rename catalogs (run once, outputs are committed):
  usr/share/locale/en_KW/LC_MESSAGES/{dolphin,konsole,plasma-discover}.mo   app names shown to users
  usr/share/kwick/files/<layout>/kio6.mo                                    sidebar section titles per layout
en_KW is a private language code: plasma-localerc lists it before en_US, every string without a
translation falls back to the English source text.
usage: gen-files-l10n.py <repo-root>
"""
import os, struct, sys

R = os.path.join(sys.argv[1], "desktop/rootfs")


def mo(path, pairs):
    p = os.path.join(R, path)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    items = sorted((k.encode(), v.encode()) for k, v in pairs.items())
    keys = b"\0".join(k for k, _ in items) + b"\0"
    vals = b"\0".join(v for _, v in items) + b"\0"
    n = len(items)
    ko, vo = 28 + 16 * n, 28 + 16 * n + len(keys)
    kt, vt, o1, o2 = [], [], 0, 0
    for k, v in items:
        kt.append((len(k), ko + o1)); o1 += len(k) + 1
        vt.append((len(v), vo + o2)); o2 += len(v) + 1
    out = struct.pack("<7I", 0x950412DE, 0, n, 28, 28 + 8 * n, 0, 0)
    out += b"".join(struct.pack("<2I", *t) for t in kt) + b"".join(struct.pack("<2I", *t) for t in vt)
    with open(p, "wb") as f:
        f.write(out + keys + vals)


def both(ctx, msgs):
    d = {}
    for k, v in msgs.items():
        d[k] = v
        if ctx:
            d[ctx + "\x04" + k] = v
    return d


hdr = {"": "Content-Type: text/plain; charset=UTF-8\nPlural-Forms: nplurals=2; plural=(n != 1);\n"}
mo("usr/share/locale/en_KW/LC_MESSAGES/dolphin.mo", {**hdr, **both("@title", {"Dolphin": "Files"})})
mo("usr/share/locale/en_KW/LC_MESSAGES/konsole.mo", {**hdr, **both("@title", {"Konsole": "Terminal"})})
mo("usr/share/locale/en_KW/LC_MESSAGES/plasma-discover.mo", {**hdr, **both("@title", {"Discover": "Software"})})

sections = {
    "macos": {"Places": "Favorites", "Remote": "Locations"},
    "windows": {"Places": "Quick access", "Remote": "Network", "Devices": "This PC"},
}
for layout, m in sections.items():
    d = dict(hdr)
    for k, v in m.items():
        d.update(both("@item", {k: v}))
        d.update(both("@title:group", {k: v}))
    mo(f"usr/share/kwick/files/{layout}/kio6.mo", d)
