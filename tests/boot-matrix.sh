#!/bin/bash
# Boot every artifact of one arch under QEMU (KVM when native, else TCG).
#   boot-matrix.sh <arch>
set -uo pipefail
ARCH=${1:?arch}
HERE=$(cd "$(dirname "$0")" && pwd)
case $ARCH in
  amd64)   MODES="microvm ram direct efi iso" ;;
  arm64)   MODES="ram direct efi iso" ;;
  riscv64) MODES="ram direct" ;;
esac
# TCG is slow: give emulated boots more time
[ -w /dev/kvm ] && [ "$ARCH" = "$(dpkg --print-architecture)" ] || export TIMEOUT=${TIMEOUT:-600}
fail=0
for m in $MODES; do
  TAIL=0 bash "$HERE/boot-test.sh" "$ARCH" "$m" "${RUNCMD:-}" | grep '^RESULT' || fail=1
done
exit $fail
