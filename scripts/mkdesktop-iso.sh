#!/bin/bash
# Build the KwickOS Desktop live ISO from an exported rootfs tarball.
#   mkdesktop-iso.sh <arch> <rootfs.tar>      (run as root in kwick-builder)
# Output: /out/<arch>/kwickos-<arch>-desktop.iso  (UEFI, generic kernel,
# erofs root under a tmpfs overlay; boots straight into Plasma).
set -euo pipefail
ARCH=${1:?arch}; TAR=${2:?rootfs tar}
OUT=${OUT:-/out}; BUILD=${BUILD:-/build}
K="$OUT/$ARCH/kernel-generic"; D="$OUT/$ARCH"
W="$BUILD/desk-$ARCH"; rm -rf "$W"; mkdir -p "$W/root" "$W/live/kwick"
[ -f "$K/vmlinuz" ] || { echo "need generic kernel"; exit 1; }
case $ARCH in amd64) EFINAME=BOOTX64.EFI;; arm64) EFINAME=BOOTAA64.EFI;; riscv64) EFINAME=BOOTRISCV64.EFI;; esac
EFI="$K/vmlinuz"; [ -f "$K/vmlinuz.efi" ] && EFI="$K/vmlinuz.efi"

tar -C "$W/root" --numeric-owner -xpf "$TAR"
# docker export leaves these as files/empty; reset runtime dirs
rm -f "$W/root/.dockerenv"; : > "$W/root/etc/resolv.conf"; : > "$W/root/etc/machine-id"
echo kwick-desktop > "$W/root/etc/hostname"
zstd -dc "$K/modules.tar.zst" | tar -C "$W/root/usr" -x
KREL=$(cat "$K/version")
depmod -b "$W/root" "$KREL" 2>/dev/null || depmod -b "$W/root/usr" "$KREL" || true

mkfs.erofs --quiet -zzstd,level=19 -C65536 -T"${SOURCE_DATE_EPOCH:-$(date +%s)}" "$W/live/kwick/root.erofs" "$W/root"
echo "KwickOS Desktop live ($KREL)" > "$W/live/kwick/README"
mkfs.vfat -n KWICK-ESP -C "$W/efiboot.img" $(( $(stat -c %s "$EFI") / 1024 + 512 )) >/dev/null
mmd -i "$W/efiboot.img" ::/EFI ::/EFI/BOOT
mcopy -i "$W/efiboot.img" "$EFI" "::/EFI/BOOT/$EFINAME"
xorriso -as mkisofs -quiet -V KWICKOS -J -joliet-long -r \
  -append_partition 2 0xef "$W/efiboot.img" -appended_part_as_gpt \
  -e --interval:appended_partition_2:all:: -no-emul-boot \
  -o "$D/kwickos-$ARCH-desktop.iso" "$W/live" 2>/dev/null
echo ">> rootfs $(du -sh "$W/root" | cut -f1), erofs $(du -h "$W/live/kwick/root.erofs" | cut -f1)"
rm -rf "$W"
ls -l "$D/kwickos-$ARCH-desktop.iso"
