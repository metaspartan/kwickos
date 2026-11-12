#!/usr/bin/env python3
"""Generate the KwickOS wallpaper (PNG, no third-party modules):
a deep indigo -> teal diagonal gradient with two soft glows and a subtle
diagonal light streak."""
import math, struct, sys, zlib

W, H = int(sys.argv[2]) if len(sys.argv) > 2 else 1920, int(sys.argv[3]) if len(sys.argv) > 3 else 1080
out = sys.argv[1] if len(sys.argv) > 1 else "wallpaper.png"

c0 = (12, 14, 38)      # top-left: near-black indigo
c1 = (38, 30, 110)     # mid: indigo
c2 = (14, 116, 144)    # bottom-right: teal
glows = [(0.78, 0.30, 0.42, (120, 80, 255), 0.55), (0.22, 0.85, 0.38, (0, 200, 200), 0.35)]

def lerp(a, b, t):
    return a + (b - a) * t

rows = []
for y in range(H):
    v = y / (H - 1)
    row = bytearray([0])
    for x in range(W):
        u = x / (W - 1)
        t = (u * 0.6 + v * 0.4)
        if t < 0.5:
            k = t / 0.5
            r, g, b = (lerp(c0[i], c1[i], k) for i in range(3))
        else:
            k = (t - 0.5) / 0.5
            r, g, b = (lerp(c1[i], c2[i], k) for i in range(3))
        for gx, gy, rad, col, a in glows:
            dx, dy = (u - gx) * W / H, v - gy
            f = math.exp(-(dx * dx + dy * dy) / (2 * rad * rad * 0.25)) * a
            r, g, b = r + (col[0] - r) * f, g + (col[1] - g) * f, b + (col[2] - b) * f
        s = abs((u - v * 0.9) - 0.15)
        streak = max(0.0, 1 - s / 0.06) ** 2 * 0.10
        r, g, b = r + (255 - r) * streak, g + (255 - g) * streak, b + (255 - b) * streak
        n = ((x * 73856093 ^ y * 19349663) & 7) - 3.5  # dither against banding
        row += bytes((max(0, min(255, int(r + n * 0.6))), max(0, min(255, int(g + n * 0.6))), max(0, min(255, int(b + n * 0.6)))))
    rows.append(bytes(row))

def chunk(t, d):
    c = struct.pack(">I", len(d)) + t + d
    return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)

png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b"")
open(out, "wb").write(png)
print(out, W, H, len(png))
