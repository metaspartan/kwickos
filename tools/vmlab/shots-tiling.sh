#!/bin/bash
set -uo pipefail
VM=${1:-h1}; PREFIX=${2:-vm-tiling}; DESK=${3:-Hyprland}
S=/vm/$VM/ser.sock
vmlogin $S >/dev/null
sh2 $S "wget -qO /usr/local/bin/asuser http://10.0.2.2:8080/x/asuser.sh" 30 >/dev/null
RUN="su kwick -s /bin/sh -c"
for n in 1 2 3; do
  sh2 $S "$RUN \"XDG_CURRENT_DESKTOP=$DESK asuser setsid foot >/dev/null 2>&1 &\"" 30 >/dev/null
  sleep 3
done
for L in macos windows linux; do
  echo "== $L"
  sh2 $S "$RUN \"XDG_CURRENT_DESKTOP=$DESK asuser kwick-layout $L 2>&1 | tail -5\"" 90 | tail -6
  sleep 6
  qmp /vm/$VM/qmp.sock move 900 500 1600 900 >/dev/null
  sleep 2
  grab 9 /work/shots/$PREFIX-$L.png
done
