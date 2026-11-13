#!/bin/bash
set -u
OUT=${1:-/out}; mkdir -p "$OUT"
export XDG_RUNTIME_DIR=/tmp/xdg-run; mkdir -p $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR
export LIBGL_ALWAYS_SOFTWARE=1 KWIN_COMPOSE=Q XDG_CURRENT_DESKTOP=KDE XDG_SESSION_TYPE=wayland QT_QPA_PLATFORM=wayland KDE_FULL_SESSION=true
export HOME=/root; mkdir -p $HOME/.config
exec dbus-run-session -- bash -c '
set -u
OUT='"$OUT"'
kwin_wayland --virtual --width 1440 --height 900 --no-lockscreen --socket wl0 >/tmp/kwin.log 2>&1 &
sleep 6; export WAYLAND_DISPLAY=wl0
plasmashell >/tmp/plasma.log 2>&1 &
sleep 25
shot() { spectacle -b -n -f -o "$OUT/$1.png" >/dev/null 2>&1; sleep 1; ls -l "$OUT/$1.png" 2>&1 | awk "{print \$5, \$9}"; }
shot 01-desktop-default
konsole --hold -e sh -c "echo; kwick-gpu; echo; kwick-layout; kwick-effects; echo; kwick-desktop list; echo; echo \"\$(cat /etc/kwick-release)  Plasma \$(plasmashell --version | cut -d\" \" -f2)\"" >/dev/null 2>&1 &
sleep 8; shot 02-terminal-tools
systemsettings >/dev/null 2>&1 &
sleep 12; shot 03-system-settings
for L in macos windows linux; do
  kwick-layout $L >/tmp/layout.log 2>&1; sleep 10; shot 10-layout-$L
done
kwick-layout macos >/dev/null 2>&1; kwick-effects full >/dev/null 2>&1; sleep 6; shot 20-effects-full-macos
tail -5 /tmp/kwin.log /tmp/plasma.log /tmp/layout.log
'