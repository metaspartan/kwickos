#!/bin/bash
set -euo pipefail
ARCH=${1:?arch}; TAR=${2:?rootfs tar}
OUT=${OUT:-/out}; BUILD=${BUILD:-/build}
K="$OUT/$ARCH/kernel-generic"; D="$OUT/$ARCH"
W="$BUILD/desk-$ARCH"; rm -rf "$W"; mkdir -p "$W/root" "$W/live/kwick"
[ -f "$K/vmlinuz" ] || { echo "need generic kernel"; exit 1; }
case $ARCH in amd64) EFINAME=BOOTX64.EFI;; arm64) EFINAME=BOOTAA64.EFI;; riscv64) EFINAME=BOOTRISCV64.EFI;; esac
EFI="$K/vmlinuz"; [ -f "$K/vmlinuz.efi" ] && EFI="$K/vmlinuz.efi"

tar -C "$W/root" --numeric-owner -xpf "$TAR"
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
BIOSARGS=()
if [ "$ARCH" = amd64 ] && [ -f /usr/lib/ISOLINUX/isolinux.bin ] && [ -f /usr/lib/syslinux/modules/bios/ldlinux.c32 ]; then
  mkdir -p "$W/live/isolinux"
  cp /usr/lib/ISOLINUX/isolinux.bin /usr/lib/syslinux/modules/bios/ldlinux.c32 "$W/live/isolinux/"
  cp "$K/vmlinuz" "$W/live/isolinux/vmlinuz"
  printf 'DEFAULT kwick\nPROMPT 0\nTIMEOUT 1\nLABEL kwick\n  KERNEL vmlinuz\n' > "$W/live/isolinux/isolinux.cfg"
  BIOSARGS=(-isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin -c isolinux/boot.cat -b isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot)
else
  echo "note: no isolinux in this builder, the ISO is UEFI only"
fi
xorriso -as mkisofs -quiet -V KWICKOS -J -joliet-long -r "${BIOSARGS[@]}" \
  -append_partition 2 0xef "$W/efiboot.img" -appended_part_as_gpt \
  -e --interval:appended_partition_2:all:: -no-emul-boot -isohybrid-gpt-basdat \
  -o "$D/kwickos-$ARCH-desktop.iso" "$W/live"
echo ">> rootfs $(du -sh "$W/root" | cut -f1), erofs $(du -h "$W/live/kwick/root.erofs" | cut -f1)"
rm -rf "$W"
ls -l "$D/kwickos-$ARCH-desktop.iso"
