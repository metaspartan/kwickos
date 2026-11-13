#!/bin/bash
set -euo pipefail
ARCH=${1:?arch}; FLAVOR=${2:?flavor}
SRC=${SRC:-/src}; OUT=${OUT:-/out}; BUILD=${BUILD:-/build}
. "$SRC/config/nvidia.env"
K="$OUT/$ARCH/kernel-$FLAVOR"; O="$BUILD/kernel-$ARCH-$FLAVOR"
KREL=$(cat "$K/version"); KVER=${KREL%-kwick}
case $ARCH in
  amd64) KARCH=x86_64; CROSS=; HOSTM=x86_64 ;;
  arm64) KARCH=arm64; CROSS=aarch64-linux-gnu-; HOSTM=aarch64 ;;
  *) echo "nvidia open modules are built for amd64 and arm64 only"; exit 1 ;;
esac
[ "$(uname -m)" = "$HOSTM" ] && CROSS=
if [ "$FLAVOR" = apple ]; then KSRC="$BUILD/src/asahi-linux"; IMGPKG=kwick-kernel-asahi; else KSRC="$BUILD/src/linux-${KREL%%-*}"; IMGPKG=linux-image-kwick-$FLAVOR; fi
SYSSRC=${SYSSRC:-$KSRC}; SYSOUT=${SYSOUT:-$O}
[ -f "$SYSOUT/Module.symvers" ] || { echo "kernel tree $SYSOUT has no Module.symvers"; exit 1; }

NVSRC="$BUILD/src/open-gpu-kernel-modules-$NVIDIA_OPEN_TAG"
bash "$SRC/scripts/fetch-pinned.sh" "$NVIDIA_OPEN_REPO" "$NVIDIA_OPEN_TAG" "$NVIDIA_OPEN_COMMIT" "$NVSRC"
W="$BUILD/nvidia-$NVIDIA_OPEN_TAG-$ARCH-$FLAVOR"
rm -rf "$W"; mkdir -p "$W"
cp -a "$NVSRC/." "$W/"
rm -rf "$W/.git"
echo ">> nvidia open modules $NVIDIA_OPEN_TAG for $KREL ($ARCH)"
T0=$(date +%s)
TOOLS=()
if [ -n "$CROSS" ]; then TOOLS=(CC="${CROSS}gcc" CXX="${CROSS}g++" LD="${CROSS}ld" AR="${CROSS}ar" OBJCOPY="${CROSS}objcopy" HOST_CC=gcc HOST_CXX=g++); fi
make -C "$W" -j"$(nproc)" modules SYSSRC="$SYSSRC" SYSOUT="$SYSOUT" ARCH="$KARCH" CROSS_COMPILE="$CROSS" TARGET_ARCH="${HOSTM}" "${TOOLS[@]}" > "$W/build.log" 2>&1 || { tail -60 "$W/build.log"; exit 1; }
echo ">> built in $(( $(date +%s) - T0 ))s"
KOS=$(find "$W/kernel-open" -name '*.ko' | sort)
[ -n "$KOS" ] || { echo "no modules produced"; exit 1; }
for want in nvidia nvidia-modeset nvidia-drm nvidia-uvm; do
  echo "$KOS" | grep -q "/$want.ko\$" || { echo "missing $want.ko"; exit 1; }
done
echo "$KOS"

PKG=kwick-nvidia-kmod-$KREL
VER=$NVIDIA_DRIVER_VERSION-$NVIDIA_PKG_REVISION
P=$(mktemp -d)
mkdir -p "$P/DEBIAN" "$P/lib/modules/$KREL/updates/nvidia" "$P/etc/modprobe.d" "$P/usr/share/doc/$PKG"
for k in $KOS; do
  cp "$k" "$P/lib/modules/$KREL/updates/nvidia/"
  "${CROSS}strip" --strip-debug "$P/lib/modules/$KREL/updates/nvidia/$(basename "$k")" 2>/dev/null || true
done
xz -T0 -6 "$P"/lib/modules/"$KREL"/updates/nvidia/*.ko
cat > "$P/etc/modprobe.d/kwick-nvidia.conf" <<EOT
blacklist nouveau
options nouveau modeset=0
options nvidia-drm modeset=1 fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOT
cp "$W/COPYING" "$P/usr/share/doc/$PKG/copyright" 2>/dev/null || true
SIZE=$(du -sk "$P" | cut -f1)
cat > "$P/DEBIAN/control" <<EOT
Package: $PKG
Version: $VER
Architecture: $ARCH
Maintainer: KwickOS Developers <dev@kwickos.org>
Section: kernel
Priority: optional
Installed-Size: $SIZE
Depends: $IMGPKG (= $KVER-1), kmod
Provides: kwick-nvidia-kmod, nvidia-kernel-open-dkms (= $VER), nvidia-kernel-dkms-any (= $NVIDIA_DRIVER_VERSION), nvidia-kernel-$NVIDIA_DRIVER_VERSION
Recommends: firmware-nvidia-gsp (= $NVIDIA_DRIVER_VERSION)
Description: NVIDIA open GPU kernel modules $NVIDIA_DRIVER_VERSION for KwickOS kernel $KREL
 Prebuilt nvidia, nvidia-modeset, nvidia-drm, nvidia-uvm (and peermem when RDMA is
 available) from NVIDIA's open-gpu-kernel-modules, built against exactly this kernel.
 Satisfies the nvidia-kernel-open-dkms dependency of NVIDIA's userspace packages,
 so no DKMS and no compiler is needed on the target.
EOT
cat > "$P/DEBIAN/postinst" <<EOT
#!/bin/sh
set -e
if [ "\$1" = configure ]; then
	depmod -a $KREL || true
fi
exit 0
EOT
cp "$P/DEBIAN/postinst" "$P/DEBIAN/postrm"
sed -i 's/\[ "\$1" = configure \]/[ "$1" = remove ] || [ "$1" = purge ]/' "$P/DEBIAN/postrm"
chmod 755 "$P/DEBIAN/postinst" "$P/DEBIAN/postrm"
mkdir -p "$OUT/repo/pool/main"
dpkg-deb --root-owner-group -Zxz -b "$P" "$OUT/repo/pool/main/${PKG}_${VER}_${ARCH}.deb" >/dev/null
rm -rf "$P"
echo "packaged $PKG $VER ($ARCH)"
