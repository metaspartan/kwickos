#!/bin/bash
set -euo pipefail
ARCH=${1:?arch}; FLAVOR=${2:?variant}; KVER=${3:-${KVER:-}}
SRC=${SRC:-/src}; OUT=${OUT:-/out}; BUILD=${BUILD:-/build}; CACHE=${CACHE:-/cache}
mkdir -p "$BUILD" "$CACHE"
[ -f "$SRC/config/kernel/$FLAVOR.config" ] || { echo "no config/kernel/$FLAVOR.config"; exit 1; }
[ -n "$KVER" ] || KVER=$(tr -d '\r\n' < "$SRC/KERNEL_VERSION")
MAJOR=${KVER%%.*}
echo ">> kernel $KVER ($ARCH/$FLAVOR)"

TARBALL="$CACHE/linux-$KVER.tar.xz"
if [ ! -f "$TARBALL" ]; then
  curl -fL --retry 3 -o "$TARBALL.part" "https://cdn.kernel.org/pub/linux/kernel/v$MAJOR.x/linux-$KVER.tar.xz"
  curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/v$MAJOR.x/sha256sums.asc" -o "$CACHE/sha256sums-v$MAJOR.asc"
  want=$(grep " linux-$KVER.tar.xz\$" "$CACHE/sha256sums-v$MAJOR.asc" | awk '{print $1}')
  got=$(sha256sum "$TARBALL.part" | awk '{print $1}')
  [ -n "$want" ] && [ "$want" = "$got" ] || { echo "sha256 mismatch for linux-$KVER"; exit 1; }
  mv "$TARBALL.part" "$TARBALL"
fi
KSRC="$BUILD/src/linux-$KVER"
if [ ! -f "$KSRC/Makefile" ]; then
  mkdir -p "$BUILD/src"; tar -C "$BUILD/src" -xf "$TARBALL"
fi

case "$ARCH" in
  arm64)   KARCH=arm64; HOSTM=aarch64; CROSS=aarch64-linux-gnu-; IMG=arch/arm64/boot/Image; FRAG=arm64 ;;
  amd64)   KARCH=x86_64; HOSTM=x86_64; CROSS=; IMG=arch/x86/boot/bzImage; FRAG=x86_64 ;;
  *) echo "unsupported arch $ARCH"; exit 1 ;;
esac
[ "$(uname -m)" = "$HOSTM" ] && CROSS=
O="$BUILD/kernel-$ARCH-$FLAVOR"
mkdir -p "$O"
M=(make -C "$KSRC" O="$O" ARCH="$KARCH" CROSS_COMPILE="$CROSS" -j"$(nproc)" KBUILD_BUILD_USER=kwick KBUILD_BUILD_HOST=kwickos)

FR="$O/fragments"; mkdir -p "$FR"
FILES="common $FRAG"
[ -f "$SRC/config/kernel/generic.config" ] && FILES="$FILES generic"
[ -f "$SRC/config/kernel/generic-$FRAG.config" ] && FILES="$FILES generic-$FRAG"
FILES="$FILES $FLAVOR"
for f in $FILES; do sed 's/\r$//' "$SRC/config/kernel/$f.config" > "$FR/$f.config"; done

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

"${M[@]}" defconfig >/dev/null
FRLIST=""
for f in $FILES; do FRLIST="$FRLIST $FR/$f.config"; done
"$KSRC/scripts/kconfig/merge_config.sh" -m -O "$O" "$O/.config" $FRLIST "$FR/initramfs.config" >/dev/null
"${M[@]}" olddefconfig >/dev/null

REQ="DEVTMPFS BLK_DEV_INITRD EXT4_FS EROFS_FS OVERLAY_FS TMPFS CGROUPS NAMESPACES SECCOMP_FILTER EFI_STUB BLK_DEV_NVME
     SQUASHFS FUSE_FS BINFMT_ELF MODULES PRINTK"
VREQ=""
case $FLAVOR in
  gb10) VREQ="ACPI ARM_SMMU_V3 NUMA ZONE_DEVICE MMU_NOTIFIER PCI_DOE BLK_DEV_NVME ARM64_4K_PAGES SERIAL_AMBA_PL011_CONSOLE MLX5_CORE MLX5_INFINIBAND R8169 MT7925E" ;;
esac
dropped=""
for f in $FILES; do
  while IFS= read -r l; do
    case "$l" in CONFIG_*=y|CONFIG_*=m) grep -qx "${l%=*}=[ym]" "$O/.config" || dropped="$dropped ${l%=*}";; esac
  done < "$FR/$f.config"
done
[ -z "$dropped" ] || echo "note: options not applied:$dropped"
missing=""
for o in $REQ; do grep -q "^CONFIG_$o=y" "$O/.config" || missing="$missing $o"; done
for o in $VREQ; do grep -qE "^CONFIG_$o=[ym]" "$O/.config" || missing="$missing $o"; done
[ -z "$missing" ] || { echo "!! required kernel options missing:$missing"; exit 1; }
if [ "${CONFIG_ONLY:-}" = 1 ]; then
  mkdir -p "$OUT/$ARCH"; cp "$O/.config" "$OUT/$ARCH/$FLAVOR-kernel.config"; echo ">> config ok"; exit 0
fi

T0=$(date +%s)
TARGETS="$(basename $IMG) modules"
[ "$ARCH" = arm64 ] && TARGETS="$TARGETS vmlinuz.efi"
"${M[@]}" $TARGETS > "$O/build.log" 2>&1 || { tail -40 "$O/build.log"; exit 1; }
echo ">> built in $(( $(date +%s) - T0 ))s"

D="$OUT/$ARCH/kernel-$FLAVOR"
rm -rf "$D"; mkdir -p "$D"
cp "$O/$IMG" "$D/vmlinuz"
[ -f "$O/arch/$KARCH/boot/vmlinuz.efi" ] && cp "$O/arch/$KARCH/boot/vmlinuz.efi" "$D/vmlinuz.efi"
cp "$O/.config" "$D/config"
KREL=$(cat "$O/include/config/kernel.release")
echo "$KREL" > "$D/version"
MD="$O/modroot"; rm -rf "$MD"
"${M[@]}" INSTALL_MOD_PATH="$MD" INSTALL_MOD_STRIP=1 modules_install >/dev/null
rm -f "$MD/lib/modules/$KREL/build" "$MD/lib/modules/$KREL/source"
tar -C "$MD" -c lib | zstd -19 -T0 -q -o "$D/modules.tar.zst"
ls -l "$D"
echo ">> $KREL done"
