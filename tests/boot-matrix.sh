#!/bin/bash
set -uo pipefail
ARCH=${1:?arch}
HERE=$(cd "$(dirname "$0")" && pwd)
case $ARCH in
  amd64)   MODES="microvm ram direct efi iso" ;;
  arm64)   MODES="ram direct efi iso" ;;
  riscv64) MODES="ram direct" ;;
esac
[ -w /dev/kvm ] && [ "$ARCH" = "$(dpkg --print-architecture)" ] || export TIMEOUT=${TIMEOUT:-600}
fail=0
for m in $MODES; do
  out=$(TAIL=${TAIL:-40} bash "$HERE/boot-test.sh" "$ARCH" "$m" "${RUNCMD:-}")
  if [ $? -eq 0 ]; then grep '^RESULT' <<<"$out"; else echo "$out"; fail=1; fi
done
exit $fail
