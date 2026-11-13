#!/usr/bin/env python3
"""Generate the neutral KwickOS app entries (run once, outputs are committed):
  usr/share/applications/kwick-<id>.desktop       Exec=kwick-app <id>, picks the native app of the running session
  usr/local/share/applications/<vendor>.desktop   overrides (NoDisplay, or KDE-only visible for pinned apps) carrying the same name and icon
  usr/share/icons/hicolor/scalable/apps/kwick-<id>.svg
usage: gen-apps.py <repo-root>
"""
import os, sys

R = os.path.join(sys.argv[1], "desktop/rootfs")


def w(path, text):
    p = os.path.join(R, path)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", newline="\n") as f:
        f.write(text)


IMG = "image/png;image/jpeg;image/gif;image/webp;image/svg+xml;image/bmp;image/tiff;"
DOC = "application/pdf;application/epub+zip;image/vnd.djvu;application/postscript;"
ARC = "application/zip;application/x-tar;application/gzip;application/x-xz;application/x-bzip2;application/x-7z-compressed;application/vnd.rar;application/zstd;"
TXT = "text/plain;text/markdown;text/x-shellscript;text/x-python;text/x-csrc;application/json;application/xml;"

APPS = [
    ("editor", "Text Editor", "Plain text and code editor", "%F", TXT, "org.kde.kate",
     "System;Utility;TextEditor;", "text;code;edit;notes;markdown;",
     [("org.kde.kate", "kate -b %U"), ("org.kde.kwrite", "kwrite %U"), ("org.gnome.TextEditor", "gnome-text-editor %U")]),
    ("software", "Software", "Find and install applications", "", "", "org.kde.discover",
     "System;PackageManager;", "software;apps;store;install;flatpak;",
     [("org.kde.discover", "plasma-discover %F"), ("org.gnome.Software", "gnome-software")]),
    ("image-viewer", "Image Viewer", "View pictures and photos", "%U", IMG, "org.kde.gwenview",
     "Graphics;Viewer;", "image;photo;picture;viewer;",
     [("org.kde.gwenview", "gwenview %U"), ("org.gnome.Loupe", "loupe %U"), ("org.gnome.eog", "eog %U")]),
    ("document-viewer", "Document Viewer", "Read PDFs and e-books", "%U", DOC, "org.kde.okular",
     "Office;Viewer;", "pdf;document;epub;reader;",
     [("org.kde.okular", "okular %U"), ("org.gnome.Papers", "papers %U"), ("org.gnome.Evince", "evince %U")]),
    ("archive-manager", "Archive Manager", "Create and extract archives", "%U", ARC, "org.kde.ark",
     "Utility;Archiving;", "archive;zip;tar;extract;compress;",
     [("org.kde.ark", "ark %U"), ("org.gnome.FileRoller", "file-roller %U")]),
    ("screenshot", "Screenshot", "Capture the screen", "", "", "org.kde.spectacle",
     "Utility;", "screenshot;capture;screen;",
     [("org.kde.spectacle", "spectacle"), ("org.gnome.Screenshot", "gnome-screenshot --interactive")]),
    ("calculator", "Calculator", "Perform calculations", "", "", "org.kde.kcalc",
     "Utility;Calculator;", "calculator;math;",
     [("org.kde.kcalc", "kcalc"), ("org.gnome.Calculator", "gnome-calculator")]),
    ("system-monitor", "System Monitor", "Processes, memory and CPU usage", "", "", "org.kde.plasma-systemmonitor",
     "System;Monitor;", "monitor;processes;cpu;memory;task;",
     [("org.kde.plasma-systemmonitor", "plasma-systemmonitor"), ("org.gnome.SystemMonitor", "gnome-system-monitor")]),
]

for aid, name, comment, arg, mime, wmclass, cats, kw, vendors in APPS:
    ex = f"kwick-app {aid} {arg}".strip()
    lines = ["[Desktop Entry]", "Type=Application", f"Name={name}", f"Comment={comment}", f"Icon=kwick-{aid}",
             f"Exec={ex}", f"Categories={cats}", f"Keywords={kw}"]
    if mime:
        lines.append(f"MimeType={mime}")
    lines += ["StartupNotify=true", f"StartupWMClass={wmclass}", "Terminal=false"]
    w(f"usr/share/applications/kwick-{aid}.desktop", "\n".join(lines) + "\n")
    for vid, vex in vendors:
        w(f"usr/local/share/applications/{vid}.desktop",
          f"[Desktop Entry]\nType=Application\nName={name}\nComment={comment}\nIcon=kwick-{aid}\nExec={vex}\n"
          f"Categories={cats}\nStartupNotify=true\nTerminal=false\nNoDisplay=true\n")

GRAD = ('<linearGradient id="g" x1="0.1" y1="0" x2="0.9" y2="1"><stop offset="0" stop-color="#19f0c8"/>'
        '<stop offset="0.55" stop-color="#6e8ff0"/><stop offset="1" stop-color="#a62cf5"/></linearGradient>')
HEAD = ('<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">\n  <defs>\n'
        '    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#1b1840"/><stop offset="1" stop-color="#0a0720"/></linearGradient>\n'
        f'    {GRAD}\n'
        '    <linearGradient id="sh" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity="0.16"/><stop offset="0.5" stop-color="#ffffff" stop-opacity="0"/></linearGradient>\n'
        '  </defs>\n'
        '  <rect x="4" y="4" width="120" height="120" rx="28" fill="url(#bg)"/>\n'
        '  <rect x="4.5" y="4.5" width="119" height="119" rx="27.5" fill="url(#sh)" stroke="#ffffff" stroke-opacity="0.1"/>\n')
S = 'fill="none" stroke="url(#g)" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"'
F = 'fill="url(#g)"'

GLYPHS = {
    "editor": f'<path d="M38 24 H78 L94 40 V104 H38 Z" {S}/><path d="M78 24 V40 H94" {S}/><path d="M50 62 H82 M50 78 H82 M50 94 H68" {S}/>',
    "software": f'<path d="M30 50 H98 L94 100 a6 6 0 0 1-6 5 H40 a6 6 0 0 1-6-5 Z" {S}/><path d="M48 50 V42 a16 16 0 0 1 32 0 V50" {S}/><path d="M52 72 q12 14 24 0" {S}/>',
    "image-viewer": f'<rect x="22" y="30" width="84" height="68" rx="12" {S}/><circle cx="84" cy="54" r="7" {F}/><path d="M28 92 L52 66 L70 84 L82 74 L102 94" {S}/>',
    "document-viewer": f'<path d="M34 22 H76 L96 42 V106 H34 Z" {S}/><path d="M76 22 V42 H96" {S}/><path d="M46 62 H84 M46 76 H84 M46 90 H70" {S}/>',
    "archive-manager": f'<rect x="26" y="30" width="76" height="22" rx="7" {S}/><path d="M32 52 V100 a6 6 0 0 0 6 6 H90 a6 6 0 0 0 6-6 V52" {S}/><path d="M56 70 H72" {S}/>',
    "screenshot": f'<path d="M22 46 V34 a8 8 0 0 1 8-8 H46 M82 26 H98 a8 8 0 0 1 8 8 V46 M106 82 V94 a8 8 0 0 1-8 8 H82 M46 102 H30 a8 8 0 0 1-8-8 V82" {S}/><circle cx="64" cy="64" r="12" {F}/>',
    "calculator": f'<rect x="30" y="20" width="68" height="88" rx="12" {S}/><path d="M44 42 H84" {S}/><circle cx="46" cy="68" r="4.5" {F}/><circle cx="64" cy="68" r="4.5" {F}/><circle cx="82" cy="68" r="4.5" {F}/><circle cx="46" cy="88" r="4.5" {F}/><circle cx="64" cy="88" r="4.5" {F}/><circle cx="82" cy="88" r="4.5" {F}/>',
    "system-monitor": f'<rect x="20" y="30" width="88" height="68" rx="12" {S}/><path d="M30 70 H48 L56 50 L68 86 L78 62 H98" {S}/>',
}
for aid, g in GLYPHS.items():
    w(f"usr/share/icons/hicolor/scalable/apps/kwick-{aid}.svg", HEAD + "  " + g + "\n</svg>\n")

w("usr/bin/kwick-app", """#!/bin/sh
role=${1:?usage: kwick-app <role> [args]}; shift
de=$(printf '%s' "${XDG_CURRENT_DESKTOP:-}" | tr 'A-Z' 'a-z')
[ -n "${SWAYSOCK:-}${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && de=tiling
case $role in
  editor)          kde="kate"; gnome="gnome-text-editor"; any="mousepad kate gnome-text-editor" ;;
  software)        kde="plasma-discover"; gnome="gnome-software"; any="plasma-discover gnome-software" ;;
  image-viewer)    kde="gwenview"; gnome="loupe eog"; any="imv loupe eog gwenview" ;;
  document-viewer) kde="okular"; gnome="papers evince"; any="zathura papers evince okular" ;;
  archive-manager) kde="ark"; gnome="file-roller"; any="file-roller ark" ;;
  screenshot)      kde="spectacle"; gnome="gnome-screenshot"; any="spectacle gnome-screenshot" ;;
  calculator)      kde="kcalc"; gnome="gnome-calculator"; any="gnome-calculator kcalc" ;;
  system-monitor)  kde="plasma-systemmonitor"; gnome="gnome-system-monitor"; any="gnome-system-monitor plasma-systemmonitor" ;;
  files)           kde="dolphin"; gnome="nautilus"; any="nautilus thunar pcmanfm dolphin" ;;
  *) echo "kwick-app: unknown role $role" >&2; exit 2 ;;
esac
case $de in
  *kde*) order="$kde $gnome $any" ;;
  *gnome*|*cinnamon*|*unity*) order="$gnome $kde $any" ;;
  *) order="$any $kde $gnome" ;;
esac
for c in $order; do
  if command -v "$c" >/dev/null 2>&1; then
    [ "$c" = gnome-screenshot ] && [ "$#" -eq 0 ] && exec "$c" --interactive
    exec "$c" "$@"
  fi
done
echo "kwick-app: no $role application installed" >&2
exit 1
""")
