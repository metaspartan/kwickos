#!/bin/bash
# Build a KwickOS kernel inside the kwick-builder container.
#   build-kernel.sh <arch: amd64|arm64|riscv64> <flavor: virt|generic> [version]
# The version defaults to the newest "stable" from kernel.org/releases.json,
# so CI picks up new upstream releases (and their CVE fixes) automatically.
# Outputs /out/<arch>/kernel-<flavor>/{vmlinuz,vmlinuz.efi?,config,version,modules.tar.zst?}
set -euo pipefail
ARCH=${1:?arch}; FLAVOR=${2:?flavor}; KVER=${3:-${KVER:-}}
SRC=${SRC:-/src}; OUT=${OUT:-/out}; BUILD=${BUILD:-/build}; CACHE=${CACHE:-/cache}
mkdir -p "$BUILD" "$CACHE"

if [ -z "$KVER" ]; then
  KVER=$(curl -fsSL https://www.kernel.org/releases.json | jq -r '[.releases[]|select(.moniker=="stable" and .iseol==false)][0].version')
fi
MAJOR=${KVER%%.*}
echo ">> kernel $KVER ($ARCH/$FLAVOR)"

TARBALL="$CACHE/linux-$KVER.tar.xz"
if [ ! -f "$TARBALL" ]; then
  curl -fL --retry 3 -o "$TARBALL.part" "https://cdn.kernel.org/pub/linux/kernel/v$MAJOR.x/linux-$KVER.tar.xz"
  # integrity: compare against kernel.org's published sha256sums
  curl -fsSL "https://cdn.kernel.org/pub/linux/kernel/v$MAJOR.x/sha256sums.asc" -o "$CACHE/sha256sums-v$MAJOR.asc"
  want=$(grep " linux-$KVER.tar.xz\$" "$CACHE/sha256sums-v$MAJOR.asc" | awk '{print $1}')
  got=$(sha256sum "$TARBALL.part" | awk '{print $1}')
  [ -n "$want" ] && [ "$want" = "$got" ] || { echo "sha256 mismatch for linux-$KVER ($got vs $want)"; exit 1; }
  mv "$TARBALL.part" "$TARBALL"
fi
KSRC="$BUILD/src/linux-$KVER"
if [ ! -f "$KSRC/Makefile" ]; then
  mkdir -p "$BUILD/src"; tar -C "$BUILD/src" -xf "$TARBALL"
fi

case "$ARCH" in
  amd64)   KARCH=x86_64; CROSS=;                    IMG=arch/x86/boot/bzImage; FRAG=x86_64 ;;
  arm64)   KARCH=arm64;  CROSS=aarch64-linux-gnu-;  IMG=arch/arm64/boot/Image; FRAG=arm64 ;;
  riscv64) KARCH=riscv;  CROSS=riscv64-linux-gnu-;  IMG=arch/riscv/boot/Image; FRAG=riscv64 ;;
  *) echo "unknown arch $ARCH"; exit 1 ;;
esac
O="$BUILD/kernel-$ARCH-$FLAVOR"
mkdir -p "$O"
M=(make -C "$KSRC" O="$O" ARCH="$KARCH" CROSS_COMPILE="$CROSS" -j"$(nproc)" KBUILD_BUILD_USER=kwick KBUILD_BUILD_HOST=kwickos)

# Fragments (normalize CRLF in case of a Windows checkout).
FR="$O/fragments"; mkdir -p "$FR"
for f in common "$FRAG" "$FLAVOR"; do sed 's/\r$//' "$SRC/config/kernel/$f.config" > "$FR/$f.config"; done

# Embedded initramfs: just kinit as /init (stage 0 root finder).
KINIT="$OUT/$ARCH/userland/kinit"
[ -x "$KINIT" ] || { echo "missing $KINIT - build userland first"; exit 1; }
cat > "$O/initramfs.list" <<EOF
dir /dev 0755 0 0
nod /dev/console 0600 0 0 c 5 1
dir /proc 0755 0 0
dir /sys 0755 0 0
dir /run 0755 0 0
dir /newroot 0755 0 0
file /init $KINIT 0755 0 0
EOF
echo "CONFIG_INITRAMFS_SOURCE=\"$O/initramfs.list\"" > "$FR/initramfs.config"

if [ "$FLAVOR" = virt ]; then BASE=tinyconfig; else BASE=defconfig; fi
"${M[@]}" $BASE >/dev/null
"$KSRC/scripts/kconfig/merge_config.sh" -m -O "$O" "$O/.config" "$FR"/common.config "$FR/$FRAG.config" "$FR/$FLAVOR.config" "$FR/initramfs.config" >/dev/null
"${M[@]}" olddefconfig >/dev/null

# Hard requirements: fail loudly if kconfig silently dropped something.
REQ="DEVTMPFS BLK_DEV_INITRD VIRTIO_PCI VIRTIO_BLK VIRTIO_NET VIRTIO_CONSOLE EXT4_FS EROFS_FS OVERLAY_FS
     TMPFS UNIX INET IPV6 CGROUPS MEMCG NAMESPACES USER_NS SECCOMP_FILTER NF_TABLES BLK_DEV_LOOP
     ISO9660_FS EFI_STUB SQUASHFS FUSE_FS VIRTIO_FS NET_9P_VIRTIO PRINTK BINFMT_ELF BINFMT_SCRIPT FUTEX EPOLL"
case $ARCH in amd64) REQ="$REQ SERIAL_8250_CONSOLE BLK_DEV_SR PVH KVM_GUEST";; arm64) REQ="$REQ SERIAL_AMBA_PL011_CONSOLE";; riscv64) REQ="$REQ SERIAL_8250_CONSOLE HVC_RISCV_SBI";; esac
# Report (non-fatal) every fragment option kconfig dropped.
dropped=""
for f in "$FR"/common.config "$FR/$FRAG.config" "$FR/$FLAVOR.config"; do
  while IFS= read -r l; do
    case "$l" in CONFIG_*=y|CONFIG_*=m) grep -qx "${l%=*}=[ym]" "$O/.config" || dropped="$dropped ${l%=*}";; esac
  done < "$f"
done
[ -z "$dropped" ] || echo "note: options not applied (unavailable on this arch/version or unmet deps):$dropped"
missing=""
for o in $REQ; do grep -q "^CONFIG_$o=y" "$O/.config" || missing="$missing $o"; done
[ -z "$missing" ] || { echo "!! required kernel options missing:$missing"; exit 1; }

T0=$(date +%s)
TARGETS=$(basename $IMG)
case $ARCH in arm64|riscv64) TARGETS="$TARGETS vmlinuz.efi";; esac
[ "$FLAVOR" = generic ] && TARGETS="$TARGETS modules"
"${M[@]}" $TARGETS > "$O/build.log" 2>&1 || { tail -40 "$O/build.log"; exit 1; }
echo ">> built in $(( $(date +%s) - T0 ))s"

D="$OUT/$ARCH/kernel-$FLAVOR"
rm -rf "$D"; mkdir -p "$D"
cp "$O/$IMG" "$D/vmlinuz"
[ -f "$O/arch/$KARCH/boot/vmlinuz.efi" ] && cp "$O/arch/$KARCH/boot/vmlinuz.efi" "$D/vmlinuz.efi"
[ "$ARCH" = amd64 ] && cp "$O/vmlinux" "$D/vmlinux" && strip "$D/vmlinux" 2>/dev/null || true
cp "$O/.config" "$D/config"
KREL=$(cat "$O/include/config/kernel.release")
echo "$KREL" > "$D/version"
if [ "$FLAVOR" = generic ]; then
  MD="$O/modroot"; rm -rf "$MD"
  "${M[@]}" INSTALL_MOD_PATH="$MD" INSTALL_MOD_STRIP=1 modules_install >/dev/null
  rm -f "$MD/lib/modules/$KREL/build" "$MD/lib/modules/$KREL/source"
  tar -C "$MD" -c lib | zstd -19 -T0 -q -o "$D/modules.tar.zst"
fi
ls -l "$D"
echo ">> $KREL done"
