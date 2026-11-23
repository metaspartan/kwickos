#!/usr/bin/env python3
import os, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
APPS = os.path.join(ROOT, "desktop", "rootfs", "usr", "local", "share", "applications")
OWN = os.path.join(ROOT, "desktop", "rootfs", "usr", "share", "applications")
PRIVILEGED = {
    "org.kde.spectacle.desktop": ("/usr/bin/spectacle", "org.kde.KWin.ScreenShot2"),
    "kwick-capture.desktop": ("/usr/bin/kwick-capture", "org.kde.KWin.ScreenShot2"),
}

fail = 0


def entry(path):
    out = {}
    for line in open(path, encoding="utf-8"):
        if line.startswith("[") and out:
            break
        if "=" in line:
            k, v = line.rstrip("\n").split("=", 1)
            out.setdefault(k, v)
    return out


for name, (exe, iface) in PRIVILEGED.items():
    for d in (APPS, OWN):
        p = os.path.join(d, name)
        if not os.path.isfile(p):
            continue
        e = entry(p)
        rel = os.path.relpath(p, ROOT)
        if e.get("Exec", "").split(" ")[0] != exe:
            print("FAIL  %s: Exec must start with %s, KWin finds the desktop file of a client by its executable path" % (rel, exe))
            fail = 1
        if iface not in e.get("X-KDE-DBUS-Restricted-Interfaces", "").split(","):
            print("FAIL  %s: without X-KDE-DBUS-Restricted-Interfaces=%s KWin refuses its screenshots" % (rel, iface))
            fail = 1
print("ok" if not fail else "desktop file overrides break privileged apps")
sys.exit(fail)
