#!/bin/bash
set -euo pipefail
ARCH=${1:?arch}; TAR=${2:?rootfs tar}
OUT=${OUT:-/out}; BUILD=${BUILD:-/build}
K="$OUT/$ARCH/kernel-generic"; D="$OUT/$ARCH"
W="$BUILD/desk-$ARCH"; rm -rf "$W"; mkdir -p "$W/root" "$W/live/kwick"
[ -f "$K/vmlinuz" ] || { echo "need generic kernel"; exit 1; }
case $ARCH in amd64) EFINAME=BOOTX64.EFI;; arm64) EFINAME=BOOTAA64.EFI;; riscv64) EFINAME=BOOTRISCV64.EFI;; esac
. "$(cd "$(dirname "$0")" && pwd)/live-boot.sh"

tar -C "$W/root" --numeric-owner -xpf "$TAR"
rm -f "$W/root/.dockerenv"; : > "$W/root/etc/resolv.conf"; : > "$W/root/etc/machine-id"
echo kwick-desktop > "$W/root/etc/hostname"
zstd -dc "$K/modules.tar.zst" | tar -C "$W/root/usr" -x
KREL=$(cat "$K/version")
depmod -b "$W/root" "$KREL" 2>/dev/null || depmod -b "$W/root/usr" "$KREL" || true

mkfs.erofs --quiet -zzstd,level=19 -C65536 -T"${SOURCE_DATE_EPOCH:-$(date +%s)}" "$W/live/kwick/root.erofs" "$W/root"
echo "KwickOS Desktop live ($KREL)" > "$W/live/kwick/README"
live_boot_prepare "$ARCH" "$K" "$W" "$EFINAME"
xorriso -as mkisofs -quiet -V KWICKOS -J -joliet-long -r "${BIOSARGS[@]}" \
  -append_partition 2 0xef "$W/efiboot.img" -appended_part_as_gpt \
  -e --interval:appended_partition_2:all:: -no-emul-boot -isohybrid-gpt-basdat \
  -o "$D/kwickos-$ARCH-desktop.iso" "$W/live"
echo ">> rootfs $(du -sh "$W/root" | cut -f1), erofs $(du -h "$W/live/kwick/root.erofs" | cut -f1)"
rm -rf "$W"
ls -l "$D/kwickos-$ARCH-desktop.iso"
