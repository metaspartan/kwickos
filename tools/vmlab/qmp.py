#!/usr/bin/env python3
import json, socket, sys, time

KEYS = {" ": "spc", "\n": "ret", "\t": "tab", ".": "dot", ",": "comma", "/": "slash", "-": "minus", "=": "equal", ";": "semicolon", "'": "apostrophe", "\\": "backslash", "[": "bracket_left", "]": "bracket_right", "`": "grave_accent"}
SHIFT = {"_": "minus", "+": "equal", ":": "semicolon", '"': "apostrophe", "<": "comma", ">": "dot", "?": "slash", "|": "backslash", "{": "bracket_left", "}": "bracket_right", "~": "grave_accent", "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0"}


class Q:
    def __init__(self, path):
        self.s = socket.socket(socket.AF_UNIX)
        self.s.connect(path)
        self.f = self.s.makefile("rw")
        self.f.readline()
        self.cmd("qmp_capabilities")

    def cmd(self, name, **args):
        self.f.write(json.dumps({"execute": name, "arguments": args}) + "\n")
        self.f.flush()
        while True:
            line = self.f.readline()
            if not line:
                raise SystemExit("qmp closed")
            r = json.loads(line)
            if "return" in r or "error" in r:
                return r

    def keys(self, names, hold=20):
        ks = [{"type": "qcode", "data": n} for n in names]
        self.cmd("send-key", keys=ks, **{"hold-time": hold})

    def text(self, t):
        for c in t:
            if c in KEYS:
                self.keys([KEYS[c]])
            elif c in SHIFT:
                self.keys(["shift", SHIFT[c]])
            elif c.isupper():
                self.keys(["shift", c.lower()])
            else:
                self.keys([c])
            time.sleep(0.02)

    def mouse(self, x, y, w, h, buttons=0):
        ax = int(x * 32767 / w)
        ay = int(y * 32767 / h)
        ev = [{"type": "abs", "data": {"axis": "x", "value": ax}}, {"type": "abs", "data": {"axis": "y", "value": ay}}]
        self.cmd("input-send-event", events=ev)

    def button(self, name, down):
        self.cmd("input-send-event", events=[{"type": "btn", "data": {"button": name, "down": down}}])

    def fingers(self, phase, points, w, h):
        ev = []
        for slot, (x, y) in enumerate(points):
            tid = -1 if phase == "end" else slot + 1
            ev.append({"type": "mtt", "data": {"type": phase, "slot": slot, "tracking-id": tid, "axis": "x", "value": 0}})
            if phase != "end":
                ev.append({"type": "mtt", "data": {"type": "data", "slot": slot, "tracking-id": tid, "axis": "x", "value": int(x * 32767 / w)}})
                ev.append({"type": "mtt", "data": {"type": "data", "slot": slot, "tracking-id": tid, "axis": "y", "value": int(y * 32767 / h)}})
        self.cmd("input-send-event", events=ev)

    def swipe(self, x0, y0, x1, y1, w, h, n=1, steps=24, hold=0.0):
        pts = lambda x, y: [(x + 70 * i, y) for i in range(n)]
        self.fingers("begin", pts(x0, y0), w, h)
        time.sleep(hold or 0.03)
        for i in range(1, steps + 1):
            self.fingers("update", pts(x0 + (x1 - x0) * i / steps, y0 + (y1 - y0) * i / steps), w, h)
            time.sleep(0.016)
        self.fingers("end", pts(x1, y1), w, h)


def main():
    sock, op, *a = sys.argv[1:]
    q = Q(sock)
    if op == "screendump":
        print(q.cmd("screendump", filename=a[0], format="png" if a[0].endswith(".png") else "ppm"))
    elif op == "burst":
        prefix, n, delay = a[0], int(a[1]), float(a[2]) if len(a) > 2 else 0
        t0 = time.time()
        for i in range(n):
            q.cmd("screendump", filename="%s%04d.ppm" % (prefix, i))
            if delay:
                time.sleep(delay)
        print("frames", n, "seconds", round(time.time() - t0, 2))
    elif op == "key":
        q.keys(a)
    elif op == "type":
        q.text(a[0])
    elif op == "move":
        q.mouse(int(a[0]), int(a[1]), int(a[2]), int(a[3]))
    elif op == "click":
        q.mouse(int(a[0]), int(a[1]), int(a[2]), int(a[3]))
        q.button("left", True)
        time.sleep(0.05)
        q.button("left", False)
    elif op == "drag":
        w, h = int(a[4]), int(a[5])
        x0, y0, x1, y1 = map(int, a[:4])
        steps = int(a[6]) if len(a) > 6 else 30
        q.mouse(x0, y0, w, h)
        time.sleep(0.1)
        q.button("left", True)
        for i in range(1, steps + 1):
            q.mouse(x0 + (x1 - x0) * i / steps, y0 + (y1 - y0) * i / steps, w, h)
            time.sleep(0.03)
        q.button("left", False)
    elif op == "tap":
        x, y, w, h = map(int, a[:4])
        q.swipe(x, y, x, y, w, h, 1, 1, float(a[4]) if len(a) > 4 else 0.05)
    elif op == "swipe":
        x0, y0, x1, y1, w, h = map(int, a[:6])
        q.swipe(x0, y0, x1, y1, w, h, int(a[6]) if len(a) > 6 else 1, int(a[7]) if len(a) > 7 else 24)
    elif op == "raw":
        print(json.dumps(q.cmd(a[0], **(json.loads(a[1]) if len(a) > 1 else {}))))
    else:
        raise SystemExit("unknown op")


main()
