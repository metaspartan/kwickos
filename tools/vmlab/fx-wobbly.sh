#!/bin/bash
set -euo pipefail
VM=${1:-h1}; DISP=${DISP:-9}; Q=/vm/$VM/qmp.sock
rm -f /work/fr/wob_*.png; mkdir -p /work/fr
grab "$DISP" /work/fr/wob_ 3.5 20 &
G=$!
sleep 0.8
qmp "$Q" drag 800 291 1250 560 1600 900 12
sleep 0.9
qmp "$Q" drag 1250 560 500 330 1600 900 12
wait $G
mkgif /work/fr/wob_ /work/shots/effects-wobbly.gif 20 800 4
