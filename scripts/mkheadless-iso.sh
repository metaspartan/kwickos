#!/bin/bash
set -euo pipefail
ARCH=${1:?arch}; TAR=${2:-${OUT:-/out}/$ARCH/kwickos-rootfs-$ARCH.tar.gz}
OUT=${OUT:-/out}; BUILD=${BUILD:-/build}
HERE=$(cd "$(dirname "$0")" && pwd)
K="$OUT/$ARCH/kernel-generic"; D="$OUT/$ARCH"
W="$BUILD/headless-$ARCH"; rm -rf "$W"; mkdir -p "$W/root" "$W/live/kwick"
[ -f "$K/vmlinuz" ] || { echo "need generic kernel"; exit 1; }
[ -f "$TAR" ] || { echo "need rootfs tar $TAR"; exit 1; }
case $ARCH in amd64) EFINAME=BOOTX64.EFI;; arm64) EFINAME=BOOTAA64.EFI;; riscv64) EFINAME=BOOTRISCV64.EFI;; esac
. "$HERE/live-boot.sh"

tar -C "$W/root" --numeric-owner -xpf "$TAR"
rm -f "$W/root/.dockerenv"
zstd -dc "$K/modules.tar.zst" | tar -C "$W/root/usr" -x
KREL=$(cat "$K/version")
depmod -b "$W/root" "$KREL" 2>/dev/null || depmod -b "$W/root/usr" "$KREL" || true

mkfs.erofs --quiet -zlz4hc,12 -T"${SOURCE_DATE_EPOCH:-$(date +%s)}" "$W/live/kwick/root.erofs" "$W/root"
echo "KwickOS $(cat "$W/root/etc/kwick-release" 2>/dev/null) headless live ($KREL)" > "$W/live/kwick/README"
live_boot_prepare "$ARCH" "$K" "$W" "$EFINAME"
xorriso -as mkisofs -quiet -V KWICKOS -J -joliet-long -r "${BIOSARGS[@]}" \
  -append_partition 2 0xef "$W/efiboot.img" -appended_part_as_gpt \
  -e --interval:appended_partition_2:all:: -no-emul-boot -isohybrid-gpt-basdat \
  -o "$D/kwickos-$ARCH-headless.iso" "$W/live"
echo ">> rootfs $(du -sh "$W/root" | cut -f1), erofs $(du -h "$W/live/kwick/root.erofs" | cut -f1)"
rm -rf "$W"
ls -l "$D/kwickos-$ARCH-headless.iso"
