#!/bin/bash
set -uo pipefail
VM=${1:-h1}; PREFIX=${2:-vm-gnome}; DESK=${3:-GNOME}; APP=${4:-gnome-text-editor}
S=/vm/$VM/ser.sock; Q=/vm/$VM/qmp.sock
sh2 $S "su kwick -s /bin/sh -c \"XDG_CURRENT_DESKTOP=$DESK asuser setsid $APP >/dev/null 2>&1 &\"" 30 >/dev/null
sleep 6
qmp $Q key esc >/dev/null
for L in macos windows linux; do
  echo "== $L"
  sh2 $S "su kwick -s /bin/sh -c \"XDG_CURRENT_DESKTOP=$DESK asuser kwick-layout $L 2>&1 | tail -5\"" 90 | tail -6
  sleep 5
  qmp $Q move 900 500 1600 900 >/dev/null
  sleep 2
  grab 9 /work/shots/$PREFIX-$L.png
done
