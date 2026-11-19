#!/bin/bash
set -euo pipefail
VM=${1:-h1}; STYLE=${2:?open/close style}; APP=${APP:-dolphin}; DISP=${DISP:-9}; W=${W:-/vm}
Q=$W/$VM/qmp.sock; S=$W/$VM/ser.sock; F=/work/fr/oc_$STYLE
rm -rf "$F"; mkdir -p "$F" /work/shots
sh2 "$S" "su kwick -s /bin/sh -c 'asuser kwick-effects open-close $STYLE >/dev/null; asuser setsid $APP >/dev/null 2>&1 &'" 40 >/dev/null
sleep "${OPENWAIT:-4}"
qmp "$Q" move 1598 880 1600 900
grab "$DISP" "$F/f_" "${SECS:-3}" "${FPS:-20}" &
G=$!
sleep 0.4
qmp "$Q" key alt f4
wait $G
mkgif "$F/f_" "${OUT:-/work/shots/effects-$STYLE.gif}" "${FPS:-20}" "${WIDTH:-480}" "${MAXMB:-1}"
