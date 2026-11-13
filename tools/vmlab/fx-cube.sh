#!/bin/bash
set -euo pipefail
VM=${1:-h1}; DISP=${DISP:-9}; Q=/vm/$VM/qmp.sock; S=/vm/$VM/ser.sock
rm -f /work/fr/cube_*.png; mkdir -p /work/fr
sh2 $S "su kwick -s /bin/sh -c \"asuser qdbus6 org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager.createDesktop 1 Two; asuser qdbus6 org.kde.KWin /VirtualDesktopManager org.kde.KWin.VirtualDesktopManager.count\"" 40 | tail -2
sleep 1
qmp $Q move 800 450 1600 900
grab "$DISP" /work/fr/cube_ 5 30 &
G=$!
sleep 1
qmp $Q key ctrl alt right
sleep 2.5
qmp $Q key ctrl alt left
wait $G
mkgif /work/fr/cube_ /work/shots/effects-cube.gif 15 800 4
