#!/usr/bin/env python3
import math, sys, time
import libevdev as E

W, H, RES = 3000, 2000, 30
TOOLS = {1: E.EV_KEY.BTN_TOOL_FINGER, 2: E.EV_KEY.BTN_TOOL_DOUBLETAP, 3: E.EV_KEY.BTN_TOOL_TRIPLETAP, 4: E.EV_KEY.BTN_TOOL_QUADTAP, 5: E.EV_KEY.BTN_TOOL_QUINTTAP}


def device():
    d = E.Device()
    d.name = "KwickOS virtual touchpad"
    d.id = {"bustype": 0x18, "vendor": 0x6b77, "product": 0x7470}
    d.enable(E.INPUT_PROP_POINTER)
    d.enable(E.INPUT_PROP_BUTTONPAD)
    for c in [E.EV_KEY.BTN_LEFT, E.EV_KEY.BTN_TOUCH] + list(TOOLS.values()):
        d.enable(c)
    ax = E.InputAbsInfo(minimum=0, maximum=W, resolution=RES)
    ay = E.InputAbsInfo(minimum=0, maximum=H, resolution=RES)
    d.enable(E.EV_ABS.ABS_X, ax)
    d.enable(E.EV_ABS.ABS_Y, ay)
    d.enable(E.EV_ABS.ABS_MT_SLOT, E.InputAbsInfo(minimum=0, maximum=4))
    d.enable(E.EV_ABS.ABS_MT_POSITION_X, ax)
    d.enable(E.EV_ABS.ABS_MT_POSITION_Y, ay)
    d.enable(E.EV_ABS.ABS_MT_TRACKING_ID, E.InputAbsInfo(minimum=0, maximum=65535))
    return d.create_uinput_device()


def frame(u, pts, first=False, last=False):
    ev = []
    for i, (x, y) in enumerate(pts):
        ev.append(E.InputEvent(E.EV_ABS.ABS_MT_SLOT, i))
        if first:
            ev.append(E.InputEvent(E.EV_ABS.ABS_MT_TRACKING_ID, 100 + i))
        if last:
            ev.append(E.InputEvent(E.EV_ABS.ABS_MT_TRACKING_ID, -1))
        else:
            ev.append(E.InputEvent(E.EV_ABS.ABS_MT_POSITION_X, int(x)))
            ev.append(E.InputEvent(E.EV_ABS.ABS_MT_POSITION_Y, int(y)))
    if not last:
        ev.append(E.InputEvent(E.EV_ABS.ABS_X, int(pts[0][0])))
        ev.append(E.InputEvent(E.EV_ABS.ABS_Y, int(pts[0][1])))
    if first or last:
        ev.append(E.InputEvent(E.EV_KEY.BTN_TOUCH, 0 if last else 1))
        ev.append(E.InputEvent(TOOLS[len(pts)], 0 if last else 1))
    ev.append(E.InputEvent(E.EV_SYN.SYN_REPORT, 0))
    u.send_events(ev)
    time.sleep(0.012)


def gesture(u, path, steps=40):
    frame(u, path(0), first=True)
    for i in range(1, steps + 1):
        frame(u, path(i / steps))
    frame(u, path(1), last=True)


def main():
    kind, n = sys.argv[1], int(sys.argv[2])
    u = device()
    time.sleep(float(sys.argv[3]) if len(sys.argv) > 3 else 2.0)
    cx, cy = W / 2, H / 2
    if kind in ("up", "down", "left", "right"):
        dx, dy = {"up": (0, -1), "down": (0, 1), "left": (-1, 0), "right": (1, 0)}[kind]
        gesture(u, lambda t: [(cx + (i - n / 2) * 300 + dx * 1100 * (t - 0.5), cy + dy * 900 * (t - 0.5)) for i in range(n)])
    else:
        r0, r1 = (700, 250) if kind == "pinch" else (250, 700)
        gesture(u, lambda t: [(cx + (r0 + (r1 - r0) * t) * math.cos(2 * math.pi * i / n), cy + (r0 + (r1 - r0) * t) * math.sin(2 * math.pi * i / n)) for i in range(n)])
    time.sleep(0.5)


main()
