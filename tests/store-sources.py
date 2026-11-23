#!/usr/bin/env python3
import importlib.machinery, importlib.util, os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
BACKEND = os.path.join(ROOT, "desktop", "rootfs", "usr", "lib", "kwick", "store", "backend")
LISTPAGE = os.path.join(ROOT, "desktop", "rootfs", "usr", "share", "kwick", "store", "ListPage.qml")

loader = importlib.machinery.SourceFileLoader("kwick_store_backend", BACKEND)
spec = importlib.util.spec_from_loader(loader.name, loader)
be = importlib.util.module_from_spec(spec)
loader.exec_module(be)

fail = 0


def check(cond, msg):
    global fail
    print(("ok    " if cond else "FAIL  ") + msg)
    if not cond:
        fail = 1


apps = [
    {"key": "flathub:org.kde.kmines", "src": "flathub", "id": "org.kde.kmines", "name": "KMines", "desktop": ["org.kde.kmines.desktop"]},
    {"key": "apt:kmines", "src": "apt", "id": "org.kde.kmines", "pkg": "kmines", "name": "KMines", "desktop": ["org.kde.kmines.desktop"]},
    {"key": "flathub:org.example.Solo", "src": "flathub", "id": "org.example.Solo", "name": "Solo"},
]
be.index = lambda: apps
ctx = be.Ctx(live=False)

o = ctx.obj(apps[0])
check(o["src"] == "flathub" and o["srcs"] == ["flathub", "apt"], "a merged app lists both sources with Flathub first")
alt = (o.get("alt") or {}).get("apt") or {}
check(alt.get("key") == "apt:kmines" and alt.get("src") == "apt" and alt.get("pkg") == "kmines", "the merged app carries the Debian entry to install when Debian is chosen")
check("flathub" not in (o.get("alt") or {}), "the shown source is not repeated as an alternative")
check("alt" not in ctx.obj(apps[2]), "a single-source app has no alternatives")

qml = open(LISTPAGE, encoding="utf-8").read()
check(re.search(r"app: page\.filter !== \"all\".*modelData\.alt\[page\.filter\]", qml) is not None, "search results filtered to one source install from that source")
sys.exit(fail)
