#!/bin/sh
B=$1; d=$2; shift 2
cd /
wipe() {
  for f in pw luks; do
    [ -f "$d/$f" ] || continue
    shred -u "$d/$f" 2>/dev/null || rm -f "$d/$f"
  done
}
trap wipe EXIT INT TERM HUP
if [ "$(id -u)" = 0 ]; then
  "$B" run "$@" --yes >>"$d/out" 2>&1
elif sudo -n true 2>/dev/null; then
  sudo -n "$B" run "$@" --yes >>"$d/out" 2>&1
else
  pkexec "$B" run "$@" --yes >>"$d/out" 2>&1
fi
rc=$?
wipe
echo "EXIT $rc" >>"$d/out"
