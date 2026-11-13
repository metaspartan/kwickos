#!/bin/sh
echo "[have]"
command -v kwick-dock
echo "[conf]"
cat "${XDG_CONFIG_HOME:-$HOME/.config}/kwick/dock.conf" 2>/dev/null
echo "[list]"
kwick-dock list 2>/dev/null
echo "[help]"
kwick-dock --help 2>&1 | head -40
