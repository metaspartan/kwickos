#!/bin/sh
d=$1; shift
chmod 600 "$d/pw" "$d/luks" 2>/dev/null
[ -s "$d/pw" ] || exit 1
for f in "$@"; do [ -s "$d/$f" ] || exit 1; done
exit 0
