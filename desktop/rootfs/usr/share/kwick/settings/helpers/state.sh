#!/bin/sh
echo "[layout]"
kwick-layout 2>/dev/null
echo "[preset]"
kwick-effects 2>/dev/null
echo "[status]"
kwick-effects status 2>/dev/null
echo "[backend]"
kwick-effects backend 2>/dev/null
echo "[switch]"
kwick-effects switch 2>/dev/null
echo "[tabbox]"
kwick-effects tabbox 2>/dev/null
echo "[check]"
kwick-effects check 2>/dev/null
echo "[type]"
qdbus6 org.kde.KWin /Compositor org.kde.kwin.Compositing.compositingType 2>/dev/null
echo "[radius]"
kwick-layout radius 2>/dev/null
echo "[accent]"
kreadconfig6 --file kdeglobals --group General --key AccentColor 2>/dev/null
echo "[gpu]"
kwick-gpu 2>&1 | head -6
echo "[sessions]"
sudo -n kwick-desktop list 2>/dev/null
