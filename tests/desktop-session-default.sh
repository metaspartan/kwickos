#!/bin/sh
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KD="$ROOT/desktop/rootfs/usr/bin/kwick-desktop"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail=0
ok() { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }

if [ -e /etc/sddm.conf.d/30-kwick-session.conf ] || [ -e /etc/sddm.conf.d/20-autologin.conf ]; then
  echo "skip: this machine has its own SDDM session configuration"
  exit 0
fi

default_of() { KWICK_SDDM_STATE="$1" sh "$KD" list --json | tr '{' '\n' | sed -n 's/.*"name":"\([a-z]*\)".*"default":true.*/\1/p'; }

printf '[Last]\nSession=/usr/share/wayland-sessions/gnome.desktop\nUser=jane\n' > "$T/state.conf"
d=$(default_of "$T/state.conf")
[ "$d" = gnome ] && ok "the session SDDM remembers is the default ($d)" || bad "SDDM remembers gnome, list says '${d:-none}'"

printf '[Last]\nSession=/usr/share/xsessions/sway.desktop\n' > "$T/state.conf"
d=$(default_of "$T/state.conf")
[ "$d" = sway ] && ok "an X session path is read too ($d)" || bad "SDDM remembers sway, list says '${d:-none}'"

d=$(default_of "$T/missing.conf")
[ "$d" = kde ] && ok "without any SDDM state Plasma is the default" || bad "fresh install: list says '${d:-none}', expected kde"

n=$(KWICK_SDDM_STATE="$T/missing.conf" sh "$KD" list | grep -c ', default')
[ "$n" = 1 ] && ok "the text list marks exactly one default" || bad "the text list marks $n defaults"

grep -q 'remember "$(session "$de")"' "$KD" && ok "switch updates the session SDDM preselects" || bad "switch does not touch SDDM's remembered session, so the greeter keeps the old one"
exit $fail
