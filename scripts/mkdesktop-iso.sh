#!/bin/bash
set -euo pipefail
ARCH=${1:?arch}; TAR=${2:?rootfs tar}
OUT=${OUT:-/out}; BUILD=${BUILD:-/build}; SRC=${SRC:-/src}
K="$OUT/$ARCH/kernel-generic"; D="$OUT/$ARCH"; DEBS=${DEBS:-$OUT/repo/pool/main}
W="$BUILD/desk-$ARCH"; rm -rf "$W"; mkdir -p "$W/root" "$W/live/kwick"
[ -f "$K/vmlinuz" ] || { echo "need generic kernel"; exit 1; }
case $ARCH in amd64) EFINAME=BOOTX64.EFI;; arm64) EFINAME=BOOTAA64.EFI;; riscv64) EFINAME=BOOTRISCV64.EFI;; esac
. "$(cd "$(dirname "$0")" && pwd)/live-boot.sh"
. "$(cd "$(dirname "$0")" && pwd)/deb.sh"
VER=$(kwick_version)

tar -C "$W/root" --numeric-owner -xpf "$TAR"
for p in kwick-core:$ARCH kwick-update:all kwick-gpu:all kwick-gaming:all kwick-essentials:all linux-image-kwick-generic:$ARCH kwick-desktop:$ARCH; do
  n=${p%:*}; a=${p#*:}
  deb=$(ls -t "$DEBS"/"$n"_*_"$a".deb 2>/dev/null | head -n 1)
  [ -n "$deb" ] || { echo "mkdesktop-iso: no $n package for $a in $DEBS (build it with scripts/mk*pkg.sh first)"; exit 1; }
  case $n in linux-image-*) ;; *) [ "$(dpkg-deb -f "$deb" Version)" = "$VER" ] || { echo "mkdesktop-iso: $deb is not version $VER"; exit 1; } ;; esac
  deb_register "$W/root" "$deb"
done
[ -f "$W/root/usr/lib/kwick/kernels/$(cat "$K/version")/vmlinuz" ] || { echo "mkdesktop-iso: the kernel package does not hold $(cat "$K/version")"; exit 1; }
deb_core_links "$W/root"
deb_check_deps "$W/root" || { echo "mkdesktop-iso: the registered packages have unmet dependencies in the desktop root"; exit 1; }
rm -f "$W/root/.dockerenv" "$W/root/etc/dpkg/dpkg.cfg.d/excludes"; : > "$W/root/etc/resolv.conf"; : > "$W/root/etc/machine-id"
sed -i '/^lean-builds/d' "$W/root/etc/kpkg.conf"
echo kwick-desktop > "$W/root/etc/hostname"
sed -i '/^127\.0\.1\.1/d' "$W/root/etc/hosts"
printf '127.0.1.1\tkwick-desktop\n' >> "$W/root/etc/hosts"
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
