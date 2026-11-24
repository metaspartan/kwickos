#!/bin/sh
KINIT=${1:?usage: kinit-tmpfiles.sh KINIT_BINARY  (run as root in a throwaway container: it writes /etc/tmpfiles.d and /tmp)}
[ "$(id -u)" = 0 ] || { echo "run as root in a throwaway container"; exit 2; }
[ -e /run/kinit.sock ] && { echo "refusing to run on a system managed by kinit"; exit 2; }
B=$(mktemp -d)
T=/tmp/kwicktest
trap 'rm -rf "$B" "$T" /etc/tmpfiles.d/kwicktest.conf' EXIT
ln -s "$KINIT" "$B/systemd-tmpfiles"
mkdir -p /etc/tmpfiles.d "$T/ice/sub" "$T/keep"
printf 'D! %s/ice 1777 root root -\nd %s/keep 1777 root root -\n' "$T" "$T" > /etc/tmpfiles.d/kwicktest.conf
: > "$T/ice/1954"; : > "$T/ice/sub/x"; : > "$T/keep/1954"
ln -s /etc/hostname "$T/ice/link"
fail=0
ok() { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }

"$B/systemd-tmpfiles" --create kwicktest.conf
[ -e "$T/ice/1954" ] && ok "--create alone keeps D contents (package postinst runs)" || bad "--create without --remove emptied a D directory"
"$B/systemd-tmpfiles" --create --remove kwicktest.conf
[ -d "$T/ice" ] && [ -z "$(ls -A "$T/ice")" ] && ok "--remove empties a D directory at boot (stale ICE and X11 sockets)" || bad "D directory not emptied: $(ls -A "$T/ice" | tr '\n' ' ')"
[ "$(stat -c %a "$T/ice")" = 1777 ] && ok "the emptied directory keeps mode 1777" || bad "mode is $(stat -c %a "$T/ice")"
[ -e /etc/hostname ] && ok "symlinks inside are removed, not followed" || bad "a symlink target outside was removed"
[ -e "$T/keep/1954" ] && ok "d directories keep their contents" || bad "a d directory was emptied"
grep -q '^D! /tmp/.ICE-unix' "$(dirname "$0")/../desktop/rootfs/usr/lib/tmpfiles.d/kwick-desktop.conf" && ok "the desktop purges /tmp/.ICE-unix at boot" || bad "kwick-desktop.conf does not purge /tmp/.ICE-unix"
exit $fail
