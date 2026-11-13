#!/usr/bin/env python3
import json, socket, sys, time, os

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
    elif op == "raw":
        print(json.dumps(q.cmd(a[0], **(json.loads(a[1]) if len(a) > 1 else {}))))
    else:
        raise SystemExit("unknown op")


main()
