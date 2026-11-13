#!/bin/bash
set -euo pipefail
VM=${1:-h1}; DISP=${DISP:-9}; Q=/vm/$VM/qmp.sock
rm -f /work/fr/flame_*.png; mkdir -p /work/fr
grab "$DISP" /work/shots/flame-before.png
grab "$DISP" /work/fr/flame_ 2.5 20 &
G=$!
sleep 0.5
qmp "$Q" click ${RX:-290} ${RY:-141} 1600 900
wait $G
mkgif /work/fr/flame_ /work/shots/effects-flame.gif 20 800 4
