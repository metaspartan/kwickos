#!/bin/sh
export XDG_RUNTIME_DIR=/run/user/1000
if [ -S "$XDG_RUNTIME_DIR/bus" ]; then
  export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
else
  for p in /proc/[0-9]*; do
    [ "$(stat -c %U "$p" 2>/dev/null)" = kwick ] || continue
    a=$(tr '\0' '\n' < "$p/environ" 2>/dev/null | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p')
    [ -n "$a" ] && { export DBUS_SESSION_BUS_ADDRESS=$a; break; }
  done
fi
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}
[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ] || export WAYLAND_DISPLAY=wayland-0
if [ -d "$XDG_RUNTIME_DIR/hypr" ]; then
  export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "$XDG_RUNTIME_DIR/hypr" | head -1)
fi
S=$(ls "$XDG_RUNTIME_DIR"/sway-ipc.* 2>/dev/null | head -1)
[ -n "$S" ] && export SWAYSOCK=$S
[ -z "$DISPLAY" ] && [ -S /tmp/.X11-unix/X0 ] && export DISPLAY=:0
XA=$(ls /run/user/1000/xauth_* 2>/dev/null | head -1); [ -n "$XA" ] && export XAUTHORITY=$XA
export XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-KDE}
export HOME=/home/kwick
export LANG=en_US.UTF-8
export LANGUAGE=en_KW:en_US
cd "$HOME"
exec "$@"
