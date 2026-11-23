#!/usr/bin/env python3
import os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "desktop", "rootfs", "usr", "share", "kwick", "installer")
RING = re.compile(r"Rectangle \{\n(?P<body>(?:[^{}]|\{[^{}]*\})*?border\.color: [^\n]*Theme\.focusRing[^\n]*\n(?:[^{}]|\{[^{}]*\})*?)\}")

fail = 0


def bad(msg):
    global fail
    print("FAIL  " + msg)
    fail = 1


theme = open(os.path.join(DIR, "Theme.qml"), encoding="utf-8").read()
m = re.search(r"focusRing: Qt\.rgba\([^,]+,[^,]+,[^,]+, (.+)\)\n", theme)
if not m:
    bad("Theme.qml has no focusRing colour")
else:
    alphas = [float(a) for a in re.findall(r"\d*\.\d+", m.group(1))]
    if not alphas or max(alphas) > 0.5:
        bad("focusRing alpha %s is heavier than the macOS focus ring (at most 0.5)" % m.group(1))

rings = 0
for f in sorted(os.listdir(DIR)):
    if not f.endswith(".qml"):
        continue
    text = open(os.path.join(DIR, f), encoding="utf-8").read()
    for r in RING.finditer(text):
        body = r.group("body")
        mm = re.search(r"anchors\.margins: (-?[\d.]+)", body)
        wm = re.search(r"border\.width: ([\d.]+)", body)
        if not mm or not wm:
            continue
        rings += 1
        margin, width = float(mm.group(1)), float(wm.group(1))
        if f in ("PLook.qml", "Disclosure.qml"):
            continue
        if -margin > width:
            bad("%s: focus ring leaves a %.1f px gap around its control (margins %s, border %s), which reads as a dark outline" % (f, -margin - width, mm.group(1), wm.group(1)))
        if width > 4:
            bad("%s: focus ring is %s px wide" % (f, wm.group(1)))
if rings < 6:
    bad("found only %d focus rings in the installer" % rings)
print("ok" if not fail else "installer focus rings are wrong")
sys.exit(fail)
