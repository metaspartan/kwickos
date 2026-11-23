#!/bin/sh
ROOT=$(cd "$(dirname "$0")/.." && pwd)
L="$ROOT/desktop/rootfs/usr/bin/kwick-layout"
K="$ROOT/desktop/rootfs/usr/bin/kwick-keys"
fail=0
ok() { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }

body=$(sed -n '/^kdecapture() {$/,/^}$/p' "$L")
pin=$(printf '%s\n' "$body" | grep -n 'org.kde.spectacle.desktop --key _launch "Print"' | head -n 1 | cut -d: -f1)
ret=$(printf '%s\n' "$body" | grep -n 'command -v kwick-keys' | head -n 1 | cut -d: -f1)
if [ -n "$pin" ] && [ -n "$ret" ] && [ "$pin" -lt "$ret" ]; then
  ok "Spectacle's Meta+Shift+S default is released even when kwick-keys sets the Capture shortcut"
else
  bad "kdecapture leaves Spectacle on Meta+Shift+S when kwick-keys is installed, so Capture ends up with no shortcut"
fi
printf '%s\n' "$body" | grep -q 'setForeignShortcut' && ok "the running kglobalaccel is told too" || bad "only the rc file is changed; the running kglobalaccel keeps Spectacle on Meta+Shift+S"
grep -q 'getGlobalShortcutsByKey' "$K" && ok "kwick-keys frees chords held by other KDE components before taking them" || bad "kwick-keys does not look up who holds a chord"
exit $fail
