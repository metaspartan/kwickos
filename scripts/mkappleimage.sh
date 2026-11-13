#!/bin/bash
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}; BUILD=${BUILD:-/build}
. "$SRC/config/apple.env"
ARCH=arm64
VER=$(tr -d '\r\n' < "$SRC/VERSION")
R0="$BUILD/rootfs-$ARCH"; D="$OUT/$ARCH"; K="$D/kernel-apple"; B="$D/apple"
[ -d "$R0" ] && [ -f "$K/vmlinuz" ] && [ -f "$B/m1n1.bin" ] && [ -f "$B/u-boot-nodtb.bin" ] || { echo "need arm64 rootfs, apple kernel and boot payloads"; exit 1; }
KREL=$(cat "$K/version")
W="$BUILD/img-$ARCH-apple"; rm -rf "$W"; mkdir -p "$W/esp/EFI/BOOT" "$W/esp/EFI/kwick" "$W/esp/m1n1" "$W/pkg"

R="$W/rootfs"; cp -a "$R0" "$R"
zstd -dc "$K/modules.tar.zst" | tar -C "$R/usr" -x
mkdir -p "$R/usr/lib/kwick/kernels/$KREL" "$R/usr/lib/asahi-boot" "$R/usr/lib/kwick" "$R/usr/lib/systemd/system" "$R/etc/systemd/system/multi-user.target.wants" "$R/var/lib/kwick"
cp "$K/vmlinuz" "$K/config" "$R/usr/lib/kwick/kernels/$KREL/"
zstd -dc "$K/dtbs.tar.zst" | tar -C "$R/usr/lib/kwick/kernels/$KREL" -x
cp "$B/m1n1.bin" "$B/u-boot-nodtb.bin" "$R/usr/lib/asahi-boot/"
install -m 755 "$SRC/apple/rootfs/usr/sbin/kwick-apple-boot" "$R/usr/sbin/kwick-apple-boot"
install -m 755 "$SRC/apple/rootfs/usr/sbin/kwick-apple-grow-root" "$R/usr/sbin/kwick-apple-grow-root"
install -m 755 "$SRC/apple/rootfs/usr/lib/kwick/gpu-apple" "$R/usr/lib/kwick/gpu-apple"
install -m 644 "$SRC/apple/rootfs/etc/m1n1.conf" "$R/etc/m1n1.conf"
install -m 644 "$SRC/apple/rootfs/usr/lib/systemd/system/kwick-apple-grow-root.service" "$R/usr/lib/systemd/system/"
ln -sf /usr/lib/systemd/system/kwick-apple-grow-root.service "$R/etc/systemd/system/multi-user.target.wants/kwick-apple-grow-root.service"
echo "kwick-apple" > "$R/etc/kwick-edition-apple"

cp "$K/vmlinuz" "$W/esp/EFI/BOOT/BOOTAA64.EFI"
echo "$KREL" > "$W/esp/EFI/kwick/current"
mkdir -p "$W/dtbs"
zstd -dc "$K/dtbs.tar.zst" | tar -C "$W/dtbs" -x
{
  cat "$B/m1n1.bin"
  cat "$W"/dtbs/dtbs/apple/t6*.dtb "$W"/dtbs/dtbs/apple/t81*.dtb
  gzip -9 -c "$B/u-boot-nodtb.bin"
} > "$W/esp/m1n1/boot.bin"

ROOTMB=${ROOTMB:-3072}; ESPMB=${ESPMB:-500}
mke2fs -q -t ext4 -L kwick-root -E root_owner=0:0 -d "$R" "$W/pkg/root.img" "${ROOTMB}M"
cp -a "$W/esp" "$W/pkg/esp"

ESPTYPE=C12A7328-F81F-11D2-BA4B-00A0C93EC93B; ROOTTYPE=B921B045-1DF0-41C3-AF44-4C6F280D3FAE
mkfs.vfat -n KWICK-ESP -C "$W/esp.vfat" $((ESPMB * 1024)) >/dev/null
mcopy -s -i "$W/esp.vfat" "$W"/esp/EFI "$W"/esp/m1n1 ::/
truncate -s "$((1 + ESPMB + ROOTMB + 1))M" "$W/disk.img"
sfdisk -q "$W/disk.img" <<EOF
label: gpt
first-lba: 2048
start=1MiB, size=${ESPMB}MiB, type=$ESPTYPE, name="EFI System"
start=$((1 + ESPMB))MiB, size=${ROOTMB}MiB, type=$ROOTTYPE, name="kwick-root"
EOF
dd if="$W/esp.vfat" of="$W/disk.img" bs=1M seek=1 conv=notrunc,sparse status=none
dd if="$W/pkg/root.img" of="$W/disk.img" bs=1M seek=$((1 + ESPMB)) conv=notrunc,sparse status=none
mv "$W/disk.img" "$D/kwickos-$ARCH-apple.img"
zstd -T0 -6 -q -f "$D/kwickos-$ARCH-apple.img" -o "$D/kwickos-$ARCH-apple.img.zst"

PKGNAME="kwickos-$VER-apple.zip"
( cd "$W/pkg" && python3 -m zipfile -c "$D/$PKGNAME" esp root.img )
ROOTBYTES=$(stat -c %s "$W/pkg/root.img")
VOLID=$(printf '0x%s' "$(echo "kwickos-$VER" | sha256sum | cut -c1-8)")
SUPPORTED_FW=${SUPPORTED_FW:-12.3 12.3.1 13.5 14.8.3}
FWJSON=$(printf '%s\n' $SUPPORTED_FW | jq -R . | jq -sc .)
jq -n --arg name "KwickOS $VER (Apple Silicon)" --arg pkg "$PKGNAME" --arg vol "$VOLID" \
  --argjson fw "$FWJSON" --arg espsize "$((ESPMB * 1024 * 1024))B" --arg rootsize "${ROOTBYTES}B" \
  '{os_list:[{name:$name,default_os_name:"KwickOS",boot_object:"m1n1.bin",next_object:"m1n1/boot.bin",package:$pkg,supported_fw:$fw,
    partitions:[{name:"EFI",type:"EFI",size:$espsize,format:"fat",volume_id:$vol,copy_firmware:true,copy_installer_data:true,source:"esp"},
                {name:"Root",type:"Linux",size:$rootsize,expand:true,image:"root.img"}]}]}' > "$D/installer_data.json"
install -m 755 "$SRC/apple/installer/bootstrap.sh" "$D/kwickos-apple-bootstrap.sh"
rm -rf "$W"
ls -l "$D/$PKGNAME" "$D/installer_data.json" "$D/kwickos-$ARCH-apple.img.zst"
echo ">> apple image $KREL done"
