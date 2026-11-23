#!/bin/sh
echo "[layout]"
kwick-layout 2>/dev/null
echo "[appearance]"
kwick-layout appearance 2>/dev/null
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
echo "[openclose]"
kwick-effects open-close list 2>/dev/null
echo "[duration]"
kwick-effects param duration 2>/dev/null
echo "[check]"
kwick-effects check 2>/dev/null
echo "[type]"
qdbus6 org.kde.KWin /Compositor org.kde.kwin.Compositing.compositingType 2>/dev/null
echo "[radius]"
kwick-layout radius 2>/dev/null
echo "[accent]"
kwick-layout accent 2>/dev/null
echo "[gpu]"
kwick-gpu 2>&1 | head -6
echo "[sessions]"
kwick-desktop list 2>/dev/null
echo "[shell]"
kwick-shell --current 2>/dev/null
