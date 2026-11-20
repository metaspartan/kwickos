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
case ${XDG_CURRENT_DESKTOP:-} in
  *GNOME*)
    case $(gsettings get org.gnome.desktop.interface accent-color 2>/dev/null) in
      "'blue'") echo 10,132,255 ;; "'purple'") echo 191,90,242 ;; "'pink'") echo 255,55,95 ;; "'red'") echo 255,69,58 ;;
      "'orange'") echo 255,159,10 ;; "'yellow'") echo 255,214,10 ;; "'green'") echo 48,209,88 ;; "'slate'") echo 152,152,157 ;;
    esac ;;
  *) kreadconfig6 --file kdeglobals --group General --key AccentColor 2>/dev/null ;;
esac
echo "[gpu]"
kwick-gpu 2>&1 | head -6
echo "[sessions]"
kwick-desktop list 2>/dev/null
echo "[shell]"
kwick-shell --current 2>/dev/null
