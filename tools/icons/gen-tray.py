#!/usr/bin/env python3
import importlib.util, math, os, sys


def sibling(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), os.path.join(os.path.dirname(os.path.abspath(__file__)), name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


CUT = sibling("fill-symbolic").CUT
SW = 1.5
DIM = 0.32
BUSY = 0.55
TEXT = "#ffffff"
USAGE = "usage: gen-tray.py <icon-theme-dir>"


def pt(cx, cy, r, a):
    t = math.radians(a)
    return cx + r * math.sin(t), cy - r * math.cos(t)


def f(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s == "-0" else s


def arc(cx, cy, r, a0, a1, extra=""):
    x0, y0 = pt(cx, cy, r, a0)
    x1, y1 = pt(cx, cy, r, a1)
    big = 1 if abs(a1 - a0) > 180 else 0
    return f'<path d="M{f(x0)} {f(y0)}A{f(r)} {f(r)} 0 {big} 1 {f(x1)} {f(y1)}"{extra}/>'


def P(d, extra=""):
    return f'<path d="{d}"{extra}/>'


def solid_stroked(d, extra=""):
    return f'<path d="{d}" fill="currentColor"{extra}/>'


def dot(cx, cy, r, extra=""):
    return f'<circle cx="{f(cx)}" cy="{f(cy)}" r="{f(r)}" fill="currentColor" stroke="none"{extra}/>'


def rect(x, y, w, h, rx, extra=""):
    return f'<rect x="{f(x)}" y="{f(y)}" width="{f(w)}" height="{f(h)}" rx="{f(rx)}"{extra}/>'


def frect(x, y, w, h, rx, extra=""):
    return rect(x, y, w, h, rx, ' fill="currentColor" stroke="none"' + extra)


def dim(on):
    return "" if on else f' opacity="{DIM}"'


def slash():
    return P("M4.25 3.75l13.5 14.5")


def move(dx, dy, body):
    return f'<g transform="translate({f(dx)} {f(dy)})">{body}</g>'


def speaker(level, muted=False):
    body = solid_stroked("M3 8.5h2.75L9.75 5v12l-4-3.5H3z")
    if muted:
        return move(0.5, 0, body + P("M13.25 8.5l5 5") + P("M18.25 8.5l-5 5"))
    waves = [(3.25, 52), (6.25, 46), (9.25, 40)]
    for i, (r, a) in enumerate(waves):
        body += arc(10, 11, r, 90 - a, 90 + a, dim(i < level))
    return move(-0.25, 0, body)


def microphone(muted=False):
    body = rect(8.25, 4.75, 5.5, 8.5, 2.75) + P("M5.75 10.75a5.25 5.25 0 0 0 10.5 0") + P("M11 16v1.25")
    if muted:
        body = f'<g opacity="{DIM}">{body}</g>' + slash()
    return body


def wifi(lit, cross=False, lock=False):
    cx, cy = 11, 16.5
    body = dot(cx, cy, 1.45, dim(lit >= 1))
    for i, r in enumerate((4.25, 8, 11.75)):
        body += arc(cx, cy, r, -43, 43, dim(lit >= i + 2))
    if cross:
        body = f'<g opacity="{DIM}">{body}</g>' + slash()
    return body


def hotspot():
    body = dot(11, 11, 1.6)
    for r, a in ((4.25, 50), (7.75, 44)):
        body += arc(11, 11, r, 90 - a, 90 + a) + arc(11, 11, r, -90 - a, -90 + a)
    return body


def wired(state="on"):
    lines = P("M11 8.75v2.5") + P("M5.5 13v-1.75h11V13")
    top = frect(8, 4, 6, 5, 1.25)
    left = frect(2.5, 13, 6, 5, 1.25)
    right = frect(13.5, 13, 6, 5, 1.25)
    if state == "on":
        return top + lines + left + right
    if state == "limited":
        return top + lines + f'<g opacity="{DIM}">{left}{right}</g>'
    if state == "available":
        return top + f'<g opacity="{DIM}">{lines}{left}{right}</g>'
    return f'<g opacity="{DIM}">{top}{lines}{left}{right}</g>' + slash()


def bars(lit, cross=False):
    body = ""
    for i, (x, h) in enumerate(((3, 4.5), (7.5, 7.5), (12, 10.5), (16.5, 14))):
        body += frect(x, 18 - h, 2.75, h, 1, dim(lit > i))
    if cross:
        body = f'<g opacity="{DIM}">{body}</g>' + slash()
    return body


def plane(on=True):
    body = solid_stroked("M11 3.9c.75 0 1.15.75 1.15 1.6v3.6l5.6 3.15v1.6l-5.6-1.55v2.8l1.75 1.35v1.3L11 17.1l-2.85.65v-1.3l1.75-1.35v-2.8l-5.6 1.55v-1.6l5.6-3.15V5.5c0-.85.35-1.6 1.1-1.6z", ' stroke-width="0.9"')
    body = f'<g transform="translate(0.77 1.24) scale(0.93)">{body}</g>'
    return body if on else f'<g opacity="{DIM}">{body}</g>' + slash()


def battery(level, charging=False, missing=False):
    body = rect(1.75, 5.75, 16.75, 10.5, 3) + frect(19.6, 8.75, 1.65, 4.5, 0.8)
    if missing:
        return f'<g opacity="{DIM}">{body}</g>' + P("M7.25 8.5l5.5 5") + P("M12.75 8.5l-5.5 5")
    w = 12.25 * max(level, 0.12)
    fill = frect(3.75, 7.75, w, 6.5, 1.5)
    if charging:
        return body + f'<g opacity="{DIM}">{fill}</g>' + solid_stroked("M11.6 6.9L7.4 11.6h3.1l-1.1 3.5 4.2-4.7h-3.1z", ' stroke-width="1"')
    return body + fill


def sun(big=True):
    body = f'<circle cx="11" cy="11" r="{3 if big else 2.75}"/>'
    r0, r1 = (5.1, 6.25) if big else (5.5, 5.5)
    for i in range(8):
        a = i * 45
        x0, y0 = pt(11, 11, r0, a)
        x1, y1 = pt(11, 11, r1, a)
        body += P(f"M{f(x0)} {f(y0)}L{f(x1)} {f(y1)}") if big else dot(x0, y0, 0.95)
    return body


def moon(on=True):
    body = solid_stroked("M15.9 13.6A6.1 6.1 0 0 1 8.4 4.6a6.75 6.75 0 1 0 9.2 9.2 6.1 6.1 0 0 1-1.7-.2z")
    return body if on else f'<g opacity="{DIM}">{body}</g>' + slash()


def disc():
    return '<circle cx="11" cy="11" r="6.25"/>' + '<circle cx="11" cy="11" r="1.6"/>' + arc(11, 11, 3.9, 210, 260)


def eject():
    return solid_stroked("M11 4.75l6.25 7H4.75z") + frect(4, 15, 14, 3, 1.25)


def usb():
    return rect(6.75, 8.75, 8.5, 8.5, 2) + rect(8.5, 4.75, 5, 4, 0.75) + frect(9.9, 6.1, 0.9, 1.3, 0.2) + frect(11.2, 6.1, 0.9, 1.3, 0.2)


def harddisk():
    return rect(2.75, 6.75, 16.5, 8.5, 2.25) + dot(15.5, 11, 1.1) + P("M6 11h4.5")


def bell(state="idle"):
    body = P("M5.25 14h11.5l-1.5-2V9.25a4.25 4.25 0 0 0-8.5 0V12z") + P("M9.5 16.25a1.7 1.7 0 0 0 3 0")
    if state == "active":
        return body + dot(16, 5.75, 2)
    if state == "off":
        return f'<g opacity="{DIM}">{body}</g>' + slash()
    return body


def bluetooth(state="on"):
    body = P("M7 8l8 6.25-4 3V4.75l4 3-8 6.25")
    if state == "connected":
        return body + dot(4.25, 11, 1) + dot(17.75, 11, 1)
    if state == "off":
        return f'<g opacity="{DIM}">{body}</g>'
    return body


def update(badge=False):
    body = P("M11 4.75v8") + P("M7.5 9.5L11 13l3.5-3.5") + P("M4.75 14v1.5a1.75 1.75 0 0 0 1.75 1.75h9a1.75 1.75 0 0 0 1.75-1.75V14")
    return body + dot(16.5, 5.75, 2) if badge else body


def chevron(down=True):
    return P("M11 4.75v12.5") + (P("M6.5 12.75l4.5 4.5 4.5-4.5") if down else P("M6.5 9.25l4.5-4.5 4.5 4.5"))


def clipboard():
    return rect(5, 5.75, 12, 11.5, 2.25) + frect(8.25, 4, 5.5, 3.25, 1.25)


def phone():
    return rect(6.75, 4.75, 8.5, 12.5, 2.25) + P("M10 14.75h2")


def printer():
    return rect(2.75, 8.25, 16.5, 6.75, 2) + P("M6.5 8.25V4.75h9v3.5") + rect(6.5, 11.75, 9, 5.5, 0.75, ' fill="currentColor"')


def leaf():
    return P("M4.75 17.25C4.75 9.75 9 4.75 17.25 4.75c0 8.25-5 12.5-12.5 12.5z") + P("M4.75 17.25l7.5-7.5")


def gauge(angle):
    x, y = pt(11, 13, 4.5, angle)
    return arc(11, 13, 7.25, -125, 125) + P(f"M11 13L{f(x)} {f(y)}") + dot(11, 13, 1.5)


def poly(pts):
    return "M" + "L".join(f"{f(x)} {f(y)}" for x, y in pts) + "Z"


def slant(run, share, rise, t):
    a = t
    for _ in range(8):
        a = t * math.hypot(run - a * share, rise) / rise
    return a


def vee(x0, w, y0, h, t):
    x1, cx, y1 = x0 + w, x0 + w / 2, y0 + h
    a = slant(w / 2, 0.5, h, t)
    yv = y0 + (cx - x0 - a) * h / (cx - x0 - a / 2)
    return poly([(x0, y0), (x0 + a, y0), (cx, yv), (x1 - a, y0), (x1, y0), (cx + a / 2, y1), (cx - a / 2, y1)])


def pee(x0, w, y0, h, t):
    r = h / 3
    x1, y1, ym = x0 + w, y0 + h, y0 + 2 * r
    ri = r - t
    return (f"M{f(x0)} {f(y1)}V{f(y0)}H{f(x1 - r)}A{f(r)} {f(r)} 0 0 1 {f(x1 - r)} {f(ym)}H{f(x0 + t)}V{f(y1)}Z"
            f"M{f(x0 + t)} {f(y0 + t)}V{f(ym - t)}H{f(x1 - r)}A{f(ri)} {f(ri)} 0 0 0 {f(x1 - r)} {f(y0 + t)}Z")


def enn(x0, w, y0, h, t):
    x1, y1 = x0 + w, y0 + h
    a = slant(w, 1, h, t * 0.95)
    yr = y0 + (x1 - t - x0 - a) / (x1 - x0 - a) * h
    yl = y0 + t / (x1 - a - x0) * h
    return poly([(x0, y1), (x0, y0), (x0 + a, y0), (x1 - t, yr), (x1 - t, y0), (x1, y0), (x1, y1), (x1 - a, y1), (x0 + t, yl), (x0 + t, y1)])


def vpn_letters(paint, extra=""):
    t, x, y0, h, gap = 1, 3.5, 8, 6, 1
    widths = (4.5, 4, 4)
    out = ""
    for shape, w in zip((vee, pee, enn), widths):
        out += f'<path d="{shape(x, w, y0, h, t)}" fill="{paint}" stroke="none"{extra}/>'
        x += w + gap
    return out


def vpn(state):
    if state == "off":
        return rect(1.75, 5.75, 18.5, 10.5, 3) + vpn_letters("currentColor")
    return frect(1, 5, 20, 12, 3.75, "" if state == "on" else f' opacity="{BUSY}"') + vpn_letters(CUT)


def names():
    n = {}

    def add(keys, body):
        for k in keys.split():
            n[k] = body

    add("audio-volume-muted audio-volume-muted-blocking audio-volume-zero audio-volume-off", speaker(0, True))
    add("audio-volume-low", speaker(1))
    add("audio-volume-medium", speaker(2))
    add("audio-volume-high audio-volume-high-warning audio-volume-high-danger audio-volume-overamplified", speaker(3))
    add("microphone-sensitivity-low microphone-sensitivity-medium microphone-sensitivity-high microphone-sensitivity audio-input-microphone", microphone())
    add("microphone-sensitivity-muted audio-input-microphone-muted", microphone(True))

    for lvl, lit in (("0", 0), ("00", 0), ("20", 1), ("40", 2), ("60", 3), ("80", 4), ("100", 4)):
        for v in ("", "-locked", "-limited"):
            if not (lvl == "00" and v):
                n[f"network-wireless-{lvl}{v}"] = wifi(lit)
        n[f"network-wireless-connected-{lvl}"] = wifi(lit)
    n["network-wireless-connected-00"] = wifi(0)
    add("network-wireless network-wireless-connected network-wireless-on network-wireless-signal-excellent network-wireless-secure network-wireless-encrypted", wifi(4))
    add("network-wireless-signal-good", wifi(3))
    add("network-wireless-signal-ok", wifi(2))
    add("network-wireless-signal-weak", wifi(1))
    add("network-wireless-signal-none network-wireless-available network-wireless-acquiring", wifi(0))
    add("network-wireless-disconnected network-wireless-offline network-wireless-off network-wireless-disabled network-wireless-no-route", wifi(4, cross=True))
    add("network-wireless-hotspot", hotspot())
    add("network-wired-activated network-wired-activated-locked network-wired network-wired-locked network-wired-connected", wired("on"))
    add("network-wired-activated-limited network-wired-limited network-wired-no-route", wired("limited"))
    add("network-wired-available network-wired-acquiring", wired("available"))
    add("network-wired-disconnected network-wired-unavailable network-wired-offline network-unavailable network-offline", wired("off"))
    for lvl, lit in (("0", 0), ("20", 1), ("40", 2), ("60", 3), ("80", 4), ("100", 4)):
        for v in ("", "-locked", "-limited"):
            n[f"network-mobile-{lvl}{v}"] = bars(lit)
    add("network-mobile network-mobile-on", bars(4))
    add("network-mobile-available", bars(0))
    add("network-mobile-off", bars(4, cross=True))
    add("network-flightmode-on airplane-mode", plane(True))
    add("network-flightmode-off airplane-mode-disabled", plane(False))
    add("network-bluetooth network-wireless-bluetooth bluetooth bluetooth-active preferences-system-bluetooth", bluetooth("on"))
    add("network-bluetooth-activated bluetooth-connected bluetooth-paired", bluetooth("connected"))
    add("network-bluetooth-inactive bluetooth-inactive bluetooth-disabled bluetooth-offline", bluetooth("off"))

    for p in range(0, 101, 10):
        k = f"battery-{p:03d}"
        for suffix, chg in (("", False), ("-charging", True)):
            for prof in ("", "-profile-powersave", "-profile-performance"):
                n[k + suffix + prof] = battery(p / 100, chg)
    add("battery-full battery-full-charged battery-100-charged battery-good", battery(1))
    add("battery-full-charging battery-good-charging", battery(1, True))
    add("battery-low battery-caution", battery(0.2))
    add("battery-low-charging battery-caution-charging", battery(0.2, True))
    add("battery-empty", battery(0))
    add("battery-missing", battery(0, missing=True))
    for p in range(0, 101, 10):
        add(f"battery-level-{p}", battery(p / 100))
        add(f"battery-level-{p}-charging", battery(p / 100, True))
    add("battery-level-100-charged", battery(1, True))
    add("power-profile-power-saver", leaf())
    add("power-profile-balanced", gauge(0))
    add("power-profile-performance", gauge(60))
    add("network-vpn", vpn("on"))
    add("network-vpn-acquiring", vpn("wait"))
    add("network-vpn-disconnected network-vpn-disabled network-vpn-offline", vpn("off"))
    add("audio-input-microphone-low audio-input-microphone-medium audio-input-microphone-high", microphone())
    add("network-cellular-signal-excellent network-cellular-connected", bars(4))
    add("network-cellular-signal-good", bars(3))
    add("network-cellular-signal-ok", bars(2))
    add("network-cellular-signal-weak", bars(1))
    add("network-cellular-signal-none network-cellular-acquiring", bars(0))
    add("network-cellular-offline network-cellular-disabled", bars(4, cross=True))

    add("brightness-high video-display-brightness display-brightness", sun(True))
    add("brightness-low", sun(False))
    add("redshift-status-on night-light", moon(True))
    add("redshift-status-off night-light-disabled", moon(False))
    add("redshift-status-day", sun(True))

    add("media-optical media-optical-data media-optical-audio media-optical-video media-optical-dvd media-optical-cd media-optical-cd-audio media-optical-dvd-video media-optical-blu-ray media-optical-recordable media-optical-mixed-cd drive-optical", disc())
    add("device-notifier media-eject", eject())
    add("drive-removable-media drive-removable-media-usb drive-removable-media-usb-pendrive media-removable media-flash media-flash-memory-stick media-flash-sd-mmc", usb())
    add("drive-harddisk drive-harddisk-usb drive-harddisk-external", harddisk())

    add("notification-inactive notifications notification-progress-inactive", bell())
    add("notification-active notification-new notification-progress-active", bell("active"))
    add("notification-disabled notifications-disabled", bell("off"))

    add("update-none", update(False))
    add("update-low update-medium update-high", update(True))
    add("arrow-down", chevron(True))
    add("arrow-up", chevron(False))
    add("klipper", clipboard())
    add("kdeconnect-tray kdeconnect", phone())
    add("printer printer-printing", printer())
    return n


def svg(body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 22 22">'
            f'<style id="current-color-scheme" type="text/css">.ColorScheme-Text{{color:{TEXT}}}</style>'
            f'<g class="ColorScheme-Text" fill="none" stroke="currentColor" stroke-width="{SW}" stroke-linecap="round" stroke-linejoin="round">{body}</g></svg>\n')


def write_theme(theme):
    base = os.path.join(theme, "scalable")
    subs = [d for d in sorted(os.listdir(base)) if os.path.isdir(os.path.join(base, d))] if os.path.isdir(base) else []
    count = 0
    for name, body in names().items():
        text = svg(body)
        shared = name.startswith(("drive-", "media-", "printer", "klipper", "kdeconnect"))
        for n in ((name + "-symbolic",) if shared else (name, name + "-symbolic")):
            dests = {os.path.join(base, d, n + ".svg") for d in subs if os.path.exists(os.path.join(base, d, n + ".svg"))}
            dests.add(os.path.join(base, "status", n + ".svg"))
            for p in dests:
                os.makedirs(os.path.dirname(p), exist_ok=True)
                with open(p, "w", newline="\n") as fh:
                    fh.write(text)
                count += 1
    return count


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(USAGE)
    print("tray glyphs written:", write_theme(sys.argv[1]))
