#!/usr/bin/env python3
"""Render a contact sheet of the KwickOS icon theme. usage: sheet.py <icon-theme-dir> <out.png> [full|sizes]"""
import glob, io, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFont

THEME, OUT = sys.argv[1], sys.argv[2]
MODE = sys.argv[3] if len(sys.argv) > 3 else "full"

SECTIONS = [
    ("Apps", "system-file-manager utilities-terminal accessories-text-editor org.kde.discover org.kde.systemsettings org.kde.gwenview org.kde.okular org.kde.ark org.kde.spectacle org.kde.kcalc org.kde.plasma-systemmonitor kwick-start"),
    ("System Settings", "preferences-desktop-wallpaper preferences-desktop-theme-global preferences-desktop-font preferences-desktop-icons preferences-desktop-cursors preferences-desktop-theme-windowdecorations preferences-desktop-effects preferences-desktop-virtual preferences-desktop-activities preferences-system-tabbox preferences-desktop-notification-bell preferences-desktop-screensaver preferences-desktop-launch-feedback preferences-system-session-services preferences-desktop-baloo preferences-desktop-keyboard preferences-desktop-keyboard-shortcut preferences-desktop-mouse preferences-desktop-touchpad preferences-desktop-tablet preferences-desktop-gaming preferences-desktop-sound preferences-desktop-display preferences-desktop-display-color preferences-system-network network-wired preferences-system-bluetooth preferences-system-time preferences-desktop-locale preferences-system-power-management preferences-system-users preferences-desktop-accessibility preferences-desktop-default-applications preferences-security kdeconnect preferences-system-about preferences-system-software-update tools-check-spelling kwick-gpu kwick-layout kwick-dock kwick-fonts"),
    ("Places", "folder folder-documents folder-download folder-pictures folder-music folder-video user-home user-desktop user-trash user-trash-full drive-harddisk drive-removable-media folder-network folder-recent"),
    ("Sidebar and taskbar", "user-home-symbolic user-desktop-symbolic folder-documents-symbolic folder-download-symbolic folder-pictures-symbolic folder-music-symbolic folder-videos-symbolic user-trash-symbolic folder-network-symbolic folder-recent-symbolic kwick-start-fluent edit-find kwick-taskview network-wireless-connected-100 audio-volume-high battery bluetooth"),
    ("Files", "text-x-generic application-pdf image-x-generic audio-x-generic video-x-generic application-zip application-x-executable text-x-python application-x-deb font-x-generic unknown"),
]
ACTIONS = "document-open document-save document-new edit-copy edit-cut edit-paste edit-delete edit-undo edit-redo edit-find list-add list-remove go-previous go-next go-up go-down view-refresh view-list-details view-list-icons view-more window-close system-shutdown system-reboot system-lock-screen system-log-out media-playback-start media-playback-pause media-skip-forward audio-volume-high dialog-information dialog-warning dialog-error dialog-ok configure help-about go-home zoom-in"

BG = (20, 21, 28)
try:
    FONT = ImageFont.truetype(glob.glob("/usr/share/fonts/**/Inter*.ttf", recursive=True)[0], 13)
    HEAD = ImageFont.truetype(glob.glob("/usr/share/fonts/**/Inter*.ttf", recursive=True)[0], 20)
except Exception:
    FONT = HEAD = ImageFont.load_default()


def find(name):
    for p in glob.glob(os.path.join(THEME, "scalable", "*", name + ".svg")):
        return p
    return None


def render(name, size):
    p = find(name)
    if not p:
        return None
    png = subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), p], capture_output=True).stdout
    return Image.open(io.BytesIO(png)).convert("RGBA")


def sheet_sizes(names):
    sizes = [16, 22, 32, 48, 128]
    W = 40 + sum(s + 24 for s in sizes) + 260
    img = Image.new("RGB", (W, 40 + len(names) * 150), BG)
    d = ImageDraw.Draw(img)
    y = 30
    for n in names:
        x = 40
        for s in sizes:
            im = render(n, s)
            if im:
                img.paste(im, (x, y + (128 - s) // 2), im)
            x += s + 24
        d.text((x, y + 56), n, fill=(210, 214, 226), font=FONT)
        y += 150
    img.save(OUT)


def sheet_full():
    cell, cols = 104, 12
    secs = [(t, n.split()) for t, n in SECTIONS]
    W = cols * cell + 60
    rows = sum(-(-len(n) // cols) for _, n in secs) + 2
    H = 60 + sum(-(-len(n) // cols) * (cell + 8) + 56 for _, n in secs) + 130
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    y = 30
    for title, names in secs:
        d.text((30, y), title, fill=(236, 238, 246), font=HEAD)
        y += 44
        for i, n in enumerate(names):
            im = render(n, 64)
            cx, cy = 30 + (i % cols) * cell, y + (i // cols) * (cell + 8)
            if im:
                img.paste(im, (cx + 20, cy), im)
            else:
                d.rectangle([cx + 20, cy, cx + 84, cy + 64], outline=(120, 40, 40))
            label = n if len(n) < 15 else n[:14] + "."
            tw = d.textlength(label, font=FONT)
            d.text((cx + 52 - tw / 2, cy + 72), label, fill=(150, 154, 170), font=FONT)
        y += -(-len(names) // cols) * (cell + 8) + 12
    d.text((30, y), "Actions", fill=(236, 238, 246), font=HEAD)
    y += 40
    for i, n in enumerate(ACTIONS.split()):
        im = render(n, 24)
        cx = 30 + i * 36
        if cx + 36 > W - 20:
            cx = 30 + (i % 30) * 36
            y2 = y + (i // 30) * 36
        else:
            y2 = y
        if im:
            img.paste(im, (cx, y2), im)
    img = img.crop((0, 0, W, y + 90))
    img.save(OUT)


if MODE == "sizes":
    sheet_sizes(sys.argv[4].split())
else:
    sheet_full()
