#!/bin/bash
set -euo pipefail
VM=${1:-h1}; DISP=${DISP:-9}; Q=/vm/$VM/qmp.sock
rm -f /work/fr/lamp_*.png; mkdir -p /work/fr
qmp "$Q" drag 500 339 1030 200 1600 900 20
sleep 1.5
grab "$DISP" /work/shots/lamp-before.png
grab "$DISP" /work/fr/lamp_ 2.5 20 &
G=$!
sleep 0.5
qmp "$Q" click 343 200 1600 900
wait $G
mkgif /work/fr/lamp_ /work/shots/effects-magiclamp.gif 20 800 4
