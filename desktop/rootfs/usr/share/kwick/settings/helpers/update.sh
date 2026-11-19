#!/bin/sh
if [ "${1:-}" = kernel ]; then
  echo "[kernel]"
  [ -x /usr/sbin/kwick-kernel ] && /usr/sbin/kwick-kernel list --json 2>/dev/null
  exit 0
fi
echo "[status]"
[ -x /usr/sbin/kwick-update ] && /usr/sbin/kwick-update status --json 2>/dev/null
[ "${1:-}" = status ] && exit 0
echo "[kernel]"
cat /var/lib/kwick/update/kernels.json 2>/dev/null
echo "[access]"
if sudo -n true 2>/dev/null; then echo sudo; elif id -nG | grep -qwE 'sudo|wheel'; then echo group; else echo none; fi
