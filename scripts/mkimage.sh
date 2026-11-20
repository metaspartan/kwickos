#!/bin/bash
set -euo pipefail
ARCH=${1:?arch}
OUT=${OUT:-/out}; BUILD=${BUILD:-/build}
R0="$BUILD/rootfs-$ARCH"; D="$OUT/$ARCH"
W="$BUILD/img-$ARCH"; rm -rf "$W"; mkdir -p "$W"
KV="$D/kernel-virt"; KG="$D/kernel-generic"
[ -d "$R0" ] && [ -f "$KV/vmlinuz" ] || { echo "need rootfs and virt kernel"; exit 1; }
case $ARCH in
  amd64)   EFINAME=BOOTX64.EFI;     ROOTTYPE=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709 ;;
  arm64)   EFINAME=BOOTAA64.EFI;    ROOTTYPE=B921B045-1DF0-41C3-AF44-4C6F280D3FAE ;;
  riscv64) EFINAME=BOOTRISCV64.EFI; ROOTTYPE=72EC70A6-CF74-40E6-BD49-4BDA08E8F224 ;;
esac
efibin() { if [ -f "$1/vmlinuz.efi" ]; then echo "$1/vmlinuz.efi"; else echo "$1/vmlinuz"; fi; }
EFIV=$(efibin "$KV")
cp "$EFIV" "$D/kwickos-$ARCH.efi"
SRC=${SRC:-/src}
kdeb() {
  local t="$W/kpkg-$2"
  mkdir -p "$t/$ARCH"; cp -a "$1" "$t/$ARCH/kernel-$2"
  OUT=$t SRC=$SRC bash "$SRC/scripts/mkkernelpkg.sh" "$ARCH" "$2" >/dev/null
  ls "$t"/repo/pool/main/linux-image-kwick-"$2"_*.deb
}
register() {
  local R=$1 deb=$2 pkg x
  pkg=$(dpkg-deb -f "$deb" Package)
  x="$W/ctl-$pkg"; rm -rf "$x"; mkdir -p "$x"
  dpkg-deb -x "$deb" "$R"
  dpkg-deb -e "$deb" "$x"
  for s in preinst postinst prerm postrm md5sums conffiles; do
    [ -f "$x/$s" ] && cp -p "$x/$s" "$R/var/lib/dpkg/info/$pkg.$s"
  done
  dpkg-deb --fsys-tarfile "$deb" | tar -t | sed -e 's|^\./|/|' -e 's|/$||' -e 's|^$|/.|' | sort -u > "$R/var/lib/dpkg/info/$pkg.list"
  { echo; dpkg-deb -f "$deb" | awk '{ print } /^Package:/ { print "Status: install ok installed" }'; echo; } >> "$R/var/lib/dpkg/status"
  chmod 755 "$R"
}
RD="$W/rootfs-disk"; cp -a "$R0" "$RD"
register "$RD" "$(kdeb "$KV" virt)"

( cd "$R0" && find . -mindepth 1 | LC_ALL=C sort | cpio --quiet -o -H newc -R 0:0 ) | zstd -19 -T"${SOURCE_DATE_EPOCH:-$(date +%s)}" -q > "$D/kwickos-$ARCH-initramfs.cpio.zst"

ROOTMB=${ROOTMB:-1024}; ESPMB=48
mke2fs -q -t ext4 -L kwick-root -E root_owner=0:0 -d "$RD" "$W/root.ext4" "${ROOTMB}M"
mkfs.vfat -n KWICK-ESP -C "$W/esp.vfat" $((ESPMB * 1024)) >/dev/null
mmd -i "$W/esp.vfat" ::/EFI ::/EFI/BOOT ::/EFI/kwick
mcopy -i "$W/esp.vfat" "$EFIV" "::/EFI/BOOT/$EFINAME"
truncate -s "$((1 + ESPMB + ROOTMB + 1))M" "$W/disk.img"
sfdisk -q "$W/disk.img" <<EOF
label: gpt
first-lba: 2048
start=1MiB, size=${ESPMB}MiB, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI System"
start=$((1 + ESPMB))MiB, size=${ROOTMB}MiB, type=$ROOTTYPE, name="kwick-root"
EOF
dd if="$W/esp.vfat" of="$W/disk.img" bs=1M seek=1 conv=notrunc,sparse status=none
dd if="$W/root.ext4" of="$W/disk.img" bs=1M seek=$((1 + ESPMB)) conv=notrunc,sparse status=none
mv "$W/disk.img" "$D/kwickos-$ARCH.img"
qemu-img convert -c -O qcow2 "$D/kwickos-$ARCH.img" "$D/kwickos-$ARCH.qcow2"

KI=$KV; KF=virt; [ -f "$KG/vmlinuz" ] && KI=$KG && KF=generic
RI="$W/rootfs-iso"; cp -a "$R0" "$RI"
register "$RI" "$(kdeb "$KI" $KF)"
EFII=$(efibin "$KI")
. "$(cd "$(dirname "$0")" && pwd)/live-boot.sh"
uki_build "$ARCH" "$EFII" "$W/live-efi.efi" kwick.live && EFII="$W/live-efi.efi"
LR="$W/live"; mkdir -p "$LR/kwick"
mkfs.erofs --quiet -zlz4hc,12 -T"${SOURCE_DATE_EPOCH:-$(date +%s)}" "$LR/kwick/root.erofs" "$RI"
cp "$KI/vmlinuz" "$LR/kwick/vmlinuz"
echo "KwickOS $(cat "$RI/etc/kwick-release" 2>/dev/null) live ($(cat "$KI/version"))" > "$LR/kwick/README"
mkfs.vfat -n KWICK-ESP -C "$W/efiboot.img" $(( $(stat -c %s "$EFII") / 1024 + 512 )) >/dev/null
mmd -i "$W/efiboot.img" ::/EFI ::/EFI/BOOT
mcopy -i "$W/efiboot.img" "$EFII" "::/EFI/BOOT/$EFINAME"
xorriso -as mkisofs -quiet -V KWICKOS -J -joliet-long -r \
  -append_partition 2 0xef "$W/efiboot.img" -appended_part_as_gpt \
  -e --interval:appended_partition_2:all:: -no-emul-boot \
  -o "$D/kwickos-$ARCH.iso" "$LR" 2>/dev/null
rm -rf "$W"
ls -l "$D"/kwickos-$ARCH.{efi,img,qcow2,iso} "$D/kwickos-$ARCH-initramfs.cpio.zst"
