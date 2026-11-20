#!/usr/bin/env python3
import json
import os
import sys

import numpy as np
from PIL import Image

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "rootfs")
SCALE = float(os.environ.get("KWICK_WALL_SCALE", "1"))
ONLY = os.environ.get("KWICK_WALL_ONLY", "")


def ramp(stops, t):
    t = np.clip(t, 0, 1)
    xs = np.array([s[0] for s in stops])
    out = np.empty(t.shape + (3,))
    for c in range(3):
        out[..., c] = np.interp(t, xs, np.array([s[1][c] for s in stops], dtype=float))
    return out


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def grid(W, H):
    y, x = np.mgrid[0:H, 0:W].astype(np.float64)
    a = W / H
    return x / H - a / 2, y / H - 0.5, a


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def silk(W, H, p):
    X, Y, a = grid(W, H)
    if p.get("flip"):
        X = -X
    u = X * np.cos(p["rot"]) - Y * np.sin(p["rot"])
    v = X * np.sin(p["rot"]) + Y * np.cos(p["rot"])
    wu = u + 0.18 * np.sin(v * 2.1 + 0.7) + 0.07 * np.sin(v * 5.3 + u * 1.7 + 2.0)
    wv = v + 0.22 * np.sin(u * 1.6 + 1.3) + 0.09 * np.sin(u * 3.7 - v * 2.2 + 0.4)
    t = wv * p["freq"] + 1.6 * np.sin(wu * 1.1 + p["phase"]) + 0.6 * np.sin(wu * 2.7 - wv * 1.3 + 1.1)
    h = np.sin(t) + 0.45 * np.sin(2 * t + wu * 2.0) + 0.18 * np.sin(wu * 5.0 + wv * 3.0) + 0.5 * np.sin(wu * 1.7 + wv * 2.3 + p["phase"] * 2)
    gy, gx = np.gradient(h)
    k = p["relief"] * H / 1440
    n = np.dstack([-gx * k * 60, -gy * k * 60, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    L = np.array(p["light"], dtype=float)
    L /= np.linalg.norm(L)
    diff = np.clip(n @ L, 0, 1)
    Hh = L + np.array([0, 0, 1.0])
    Hh /= np.linalg.norm(Hh)
    spec = np.clip(n @ Hh, 0, 1) ** p["gloss"]
    base = ramp(p["stops"], p["mix"][0] * (u / a + 0.5) + p["mix"][1] * (v + 0.5) + p["mix"][2] * (h * 0.25 + 0.5) + p["mix"][3])
    shade = p["amb"] + (1 - p["amb"]) * diff
    col = base * shade[..., None] + np.array(p["sheen"], dtype=float) * spec[..., None] * p["spec"]
    if "vignette" in p:
        r = np.sqrt((X / a * 1.2) ** 2 + (Y * 1.1) ** 2)
        col *= (1 - p["vignette"] * smooth(0.35, 0.95, r))[..., None]
    return col


BAYER = (np.array([[0, 32, 8, 40, 2, 34, 10, 42], [48, 16, 56, 24, 50, 18, 58, 26], [12, 44, 4, 36, 14, 46, 6, 38],
                   [60, 28, 52, 20, 62, 30, 54, 22], [3, 35, 11, 43, 1, 33, 9, 41], [51, 19, 59, 27, 49, 17, 57, 25],
                   [15, 47, 7, 39, 13, 45, 5, 37], [63, 31, 55, 23, 61, 29, 53, 21]]) + 0.5) / 64


def finish(col):
    H, W = col.shape[:2]
    T = np.tile(BAYER, (H // 8 + 1, W // 8 + 1))[:H, :W, None]
    return Image.fromarray(np.clip(np.floor(col + T), 0, 255).astype(np.uint8), "RGB")


WALLS = {
    "KwickGlass": (silk, dict(
        rot=-0.42, freq=6.5, phase=0.6, relief=1.6, gloss=40, spec=0.6, amb=0.28,
        light=(-0.45, -0.75, 0.8), sheen=(255, 210, 235), mix=(0.6, 0.3, 0.12, -0.12), vignette=0.4,
        stops=[(0.0, hexc("#0a0a26")), (0.22, hexc("#24166a")), (0.45, hexc("#5a25b0")), (0.68, hexc("#c13a92")), (0.86, hexc("#ff7a5c")), (1.0, hexc("#ffc27a"))])),
    "KwickFluent": (silk, dict(
        flip=True, rot=-0.42, freq=6.5, phase=0.6, relief=1.6, gloss=40, spec=0.6, amb=0.28,
        light=(-0.45, -0.75, 0.8), sheen=(200, 230, 255), mix=(0.6, 0.3, 0.12, -0.12), vignette=0.4,
        stops=[(0.0, hexc("#03081c")), (0.22, hexc("#0a1f5c")), (0.45, hexc("#1446b8")), (0.68, hexc("#1f86f0")), (0.86, hexc("#3fc6ff")), (1.0, hexc("#a8ecff"))])),
    "KwickOS": (silk, dict(
        rot=-0.3, freq=6.8, phase=1.5, relief=1.6, gloss=40, spec=0.6, amb=0.28,
        light=(-0.45, -0.75, 0.8), sheen=(210, 255, 240), mix=(0.6, 0.3, 0.12, -0.12), vignette=0.4,
        stops=[(0.0, hexc("#020c14")), (0.22, hexc("#05303f")), (0.45, hexc("#0a6470")), (0.68, hexc("#10a88f")), (0.86, hexc("#5ee0a0")), (1.0, hexc("#d2f7a8"))])),
}


def main():
    for name, (fn, p) in WALLS.items():
        if ONLY and name not in ONLY.split(","):
            continue
        W, H = int(2560 * SCALE), int(1440 * SCALE)
        img = finish(fn(W, H, p))
        d = os.path.join(ROOT, "usr/share/wallpapers", name, "contents/images")
        os.makedirs(d, exist_ok=True)
        if SCALE == 1:
            img.save(os.path.join(d, "2560x1440.png"), optimize=True)
            if os.path.exists(os.path.join(d, "1920x1080.png")):
                os.remove(os.path.join(d, "1920x1080.png"))
            with open(os.path.join(ROOT, "usr/share/wallpapers", name, "metadata.json"), "w", newline="\n") as f:
                f.write(json.dumps({"KPlugin": {"Authors": [{"Name": "KwickOS"}], "Id": name, "License": "CC-BY-SA-4.0", "Name": name}}, indent=4) + "\n")
        else:
            img.save(os.path.join(d, "preview.png"))
        print(name)


main()
