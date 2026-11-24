#!/bin/bash
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}; BUILD=${BUILD:-/build}
ARCH=arm64
R0="$BUILD/rootfs-$ARCH"; D="$OUT/$ARCH"; K="$D/kernel-rpi"; POOL="$OUT/repo/pool/main"
KDEB=$(ls -t "$POOL"/linux-image-kwick-rpi_*_arm64.deb 2>/dev/null | head -n 1 || true)
FDEB=$(ls -t "$POOL"/kwick-rpi-firmware_*_arm64.deb 2>/dev/null | head -n 1 || true)
[ -d "$R0" ] && [ -f "$K/version" ] && [ -n "$KDEB" ] && [ -n "$FDEB" ] || {
  echo "need the arm64 rootfs, the rpi kernel and the linux-image-kwick-rpi and kwick-rpi-firmware packages"; exit 1; }
KREL=$(cat "$K/version")
W="$BUILD/img-$ARCH-rpi"; rm -rf "$W"; mkdir -p "$W/boot"
R="$W/rootfs"; cp -a "$R0" "$R"

. "$SRC/scripts/deb.sh"
for deb in $(deb_base_pkgs "$ARCH" "$W/basepkg" "$D/kwickos-rootfs-$ARCH.tar.gz") "$FDEB" "$KDEB"; do deb_register "$R" "$deb"; done
deb_core_links "$R"
deb_check_deps "$R"
[ -f "$R/usr/lib/kwick/kernels/$KREL/vmlinuz" ] || { echo "kernel package does not hold $KREL"; exit 1; }

mkdir -p "$R/boot/firmware" "$R/var/lib/kwick" "$R/etc/systemd/system/multi-user.target.wants"
printf 'LABEL=KWICKBOOT\t/boot/firmware\tvfat\tdefaults,noatime\t0\t0\n' >> "$R/etc/fstab"
ln -sf /usr/lib/systemd/system/kwick-growroot.service "$R/etc/systemd/system/multi-user.target.wants/kwick-growroot.service"
echo rpi > "$R/etc/kwick-edition-rpi"

KWICK_NOMOUNT=1 KWICK_RPI_BOOT="$W/boot" KWICK_RPI_FW="$R/usr/lib/kwick/rpi-firmware" KWICK_RPI_SHARE="$R/usr/share/kwick/rpi" \
  KWICK_KDIR="$R/usr/lib/kwick/kernels" sh "$R/usr/sbin/kwick-rpi-boot" install "$KREL"
for f in kernel8.img config.txt cmdline.txt start4.elf fixup4.dat bcm2711-rpi-4-b.dtb bcm2712-rpi-5-b.dtb bcm2712d0-rpi-5-b.dtb overlays/vc4-kms-v3d-pi4.dtbo overlays/vc4-kms-v3d-pi5.dtbo overlays/overlay_map.dtb; do
  [ -f "$W/boot/$f" ] || { echo "boot partition lacks $f"; exit 1; }
done
grep -q 'root=LABEL=kwick-root' "$W/boot/cmdline.txt"
grep -qx 'arm_64bit=1' "$W/boot/config.txt"

BOOTMB=${BOOTMB:-256}
USEDMB=$(( $(du -sm "$R" | cut -f1) ))
ROOTMB=${ROOTMB:-$(( USEDMB * 13 / 10 + 256 ))}
[ "$ROOTMB" -ge 1024 ] || ROOTMB=1024
mkfs.vfat -F 32 -n KWICKBOOT -C "$W/boot.vfat" $((BOOTMB * 1024)) >/dev/null
mcopy -s -i "$W/boot.vfat" "$W"/boot/* ::/
mke2fs -q -t ext4 -L kwick-root -E root_owner=0:0 -d "$R" "$W/root.img" "${ROOTMB}M"
truncate -s "$((4 + BOOTMB + ROOTMB))M" "$W/disk.img"
sfdisk -q "$W/disk.img" <<EOF
label: dos
unit: sectors
start=4MiB, size=${BOOTMB}MiB, type=c, bootable
start=$((4 + BOOTMB))MiB, size=${ROOTMB}MiB, type=83
EOF
dd if="$W/boot.vfat" of="$W/disk.img" bs=1M seek=4 conv=notrunc,sparse status=none
dd if="$W/root.img" of="$W/disk.img" bs=1M seek=$((4 + BOOTMB)) conv=notrunc,sparse status=none
IMG="$D/kwickos-$ARCH-rpi.img"
mv "$W/disk.img" "$IMG"
rm -f "$IMG.zst"
zstd -T0 -19 -q "$IMG" -o "$IMG.zst"
[ -n "${KEEP_IMG:-}" ] || rm -f "$IMG"
rm -rf "$W"
ls -l "$D"/kwickos-$ARCH-rpi.img*
echo ">> rpi image $KREL done (boot ${BOOTMB} MiB, root ${ROOTMB} MiB, grows on first boot)"
