#!/bin/bash
SOCK=${1:?serial socket}; USER=${2:-root}; PASS=${3:-kwick}
(printf '\n'; sleep 1; printf '%s\n' "$USER"; sleep 1; printf '%s\n' "$PASS"; sleep 2) | socat - "UNIX-CONNECT:$SOCK" | tr -d '\033\r' | tail -4
