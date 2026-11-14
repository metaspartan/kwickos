#!/bin/sh
umask 077
base=${XDG_RUNTIME_DIR:-/tmp}
[ -d "$base" ] && [ -w "$base" ] || base=/tmp
d=$(mktemp -d "$base/kwick-installer.XXXXXX") || exit 1
chmod 700 "$d"
for f in pw luks; do : > "$d/$f"; chmod 600 "$d/$f"; done
: > "$d/out"
echo "$d"
