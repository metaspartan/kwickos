#!/bin/bash
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}; BUILD=${BUILD:-/build}
. "$SRC/config/apple.env"
ARCH=arm64; FLAVOR=apple
mkdir -p "$BUILD"
KSRC="$BUILD/src/asahi-linux"
mkdir -p "$BUILD/src"
bash "$SRC/scripts/fetch-pinned.sh" "$ASAHI_KERNEL_REPO" "$ASAHI_KERNEL_TAG" "$ASAHI_KERNEL_COMMIT" "$KSRC"
KVER=$(make -s -C "$KSRC" kernelversion)
echo ">> asahi kernel $KVER ($ASAHI_KERNEL_TAG)"
if [ "$(uname -m)" = aarch64 ]; then CROSS=; else CROSS=aarch64-linux-gnu-; fi
O="$BUILD/kernel-$ARCH-$FLAVOR"
mkdir -p "$O"
M=(make -C "$KSRC" O="$O" ARCH=arm64 CROSS_COMPILE="$CROSS" -j"$(nproc)" KBUILD_BUILD_USER=kwick KBUILD_BUILD_HOST=kwickos)

FR="$O/fragments"; mkdir -p "$FR"
for f in common apple; do sed 's/\r$//' "$SRC/config/kernel/$f.config" > "$FR/$f.config"; done
KINIT="$OUT/$ARCH/userland/kinit"
[ -x "$KINIT" ] || { echo "missing $KINIT - build userland first"; exit 1; }
cat > "$O/initramfs.list" <<EOT
dir /dev 0755 0 0
nod /dev/console 0600 0 0 c 5 1
dir /proc 0755 0 0
dir /sys 0755 0 0
dir /run 0755 0 0
dir /newroot 0755 0 0
file /init $KINIT 0755 0 0
EOT
echo "CONFIG_INITRAMFS_SOURCE=\"$O/initramfs.list\"" > "$FR/initramfs.config"

"${M[@]}" rustavailable
"${M[@]}" defconfig >/dev/null
"$KSRC/scripts/kconfig/merge_config.sh" -m -O "$O" "$O/.config" "$KSRC/arch/arm64/configs/asahi.config" "$FR/common.config" "$FR/apple.config" "$FR/initramfs.config" >/dev/null
"${M[@]}" olddefconfig >/dev/null

REQ="ARCH_APPLE ARM64_16K_PAGES APPLE_AIC APPLE_DART APPLE_SART APPLE_RTKIT APPLE_MAILBOX NVME_APPLE PINCTRL_APPLE_GPIO
     SERIAL_SAMSUNG_CONSOLE EFI_STUB BLK_DEV_INITRD DEVTMPFS EXT4_FS EROFS_FS OVERLAY_FS TMPFS CGROUPS NAMESPACES SECCOMP_FILTER
     RUST BLK_DEV_NVME SQUASHFS FUSE_FS BINFMT_ELF"
MODREQ="DRM_ASAHI DRM_APPLE SND_SOC_APPLE_MACAUDIO BRCMFMAC"
dropped=""
for f in "$FR"/common.config "$FR/apple.config"; do
  while IFS= read -r l; do
    case "$l" in CONFIG_*=y|CONFIG_*=m) grep -qx "${l%=*}=[ym]" "$O/.config" || dropped="$dropped ${l%=*}";; esac
  done < "$f"
done
[ -z "$dropped" ] || echo "note: options not applied:$dropped"
missing=""
for o in $REQ; do grep -q "^CONFIG_$o=y" "$O/.config" || missing="$missing $o"; done
for o in $MODREQ; do grep -qE "^CONFIG_$o=[ym]" "$O/.config" || missing="$missing $o"; done
[ -z "$missing" ] || { echo "!! required kernel options missing:$missing"; exit 1; }
[ "${CONFIG_ONLY:-}" = 1 ] && { cp "$O/.config" "$OUT/$ARCH/apple-kernel.config"; echo ">> config ok"; exit 0; }

T0=$(date +%s)
"${M[@]}" Image dtbs modules > "$O/build.log" 2>&1 || { tail -60 "$O/build.log"; exit 1; }
echo ">> built in $(( $(date +%s) - T0 ))s"

D="$OUT/$ARCH/kernel-$FLAVOR"
rm -rf "$D"; mkdir -p "$D"
cp "$O/arch/arm64/boot/Image" "$D/vmlinuz"
cp "$O/.config" "$D/config"
KREL=$(cat "$O/include/config/kernel.release")
echo "$KREL" > "$D/version"
MD="$O/modroot"; rm -rf "$MD"
"${M[@]}" INSTALL_MOD_PATH="$MD" INSTALL_MOD_STRIP=1 modules_install >/dev/null
rm -f "$MD/lib/modules/$KREL/build" "$MD/lib/modules/$KREL/source"
tar -C "$MD" -c lib | zstd -19 -T0 -q -o "$D/modules.tar.zst"
mkdir -p "$D/dtbs/apple"
cp "$O"/arch/arm64/boot/dts/apple/*.dtb "$D/dtbs/apple/"
tar -C "$D" -c dtbs | zstd -19 -T0 -q -o "$D/dtbs.tar.zst"
rm -rf "$D/dtbs"
ls -l "$D"
echo ">> $KREL done"
