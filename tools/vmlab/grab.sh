#!/bin/bash
set -euo pipefail
DISP=${1:?display number}; OUT=${2:?out file or prefix}; SECS=${3:-0}; FPS=${4:-30}
for w in $(DISPLAY=":$DISP" xdotool search --name QEMU); do DISPLAY=":$DISP" xdotool windowmove "$w" 0 0 2>/dev/null || true; done
SIZE=$(DISPLAY=":$DISP" xdpyinfo | awk '/dimensions:/{print $2}')
if [ "$SECS" = 0 ]; then
  ffmpeg -v error -y -f x11grab -video_size "$SIZE" -i ":$DISP" -frames:v 1 "$OUT"
else
  ffmpeg -v error -y -f x11grab -framerate "$FPS" -video_size "$SIZE" -i ":$DISP" -t "$SECS" -c:v utvideo -f nut "${OUT}.nut"
  rm -f "${OUT}"[0-9]*.png
  ffmpeg -v error -y -i "${OUT}.nut" -vsync 0 "${OUT}%04d.png"
  rm -f "${OUT}.nut"
fi
