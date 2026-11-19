#!/bin/bash
set -euo pipefail
ARCH=${1:?arch}; FLAVOR=${2:?flavor}
OUT=${OUT:-/out}; BUILD=${BUILD:-/build}; SRC=${SRC:-/src}
. "$(cd "$(dirname "$0")" && pwd)/deb.sh"
K="$OUT/$ARCH/kernel-$FLAVOR"; O="$BUILD/kernel-$ARCH-$FLAVOR"
KREL=$(cat "$K/version")
KVER=${KREL%%-kwick*}
case $ARCH in
  amd64) KARCH=x86_64; CROSS= ;;
  arm64) KARCH=arm64; CROSS=aarch64-linux-gnu- ;;
  riscv64) KARCH=riscv; CROSS=riscv64-linux-gnu- ;;
  *) echo "unknown arch $ARCH"; exit 1 ;;
esac
[ "$(uname -m)" = "$(case $ARCH in amd64) echo x86_64;; arm64) echo aarch64;; riscv64) echo riscv64;; esac)" ] && CROSS=
if [ "$FLAVOR" = apple ]; then
  KSRC="$BUILD/src/asahi-linux"; PKG=kwick-kernel-asahi-headers; IMGPKG=kwick-kernel-asahi
else
  KSRC="$BUILD/src/linux-${KREL%%-*}"; PKG=linux-headers-kwick-$FLAVOR; IMGPKG=linux-image-kwick-$FLAVOR
  GIT=; COMMIT=
  [ ! -f "$SRC/config/kernel/$FLAVOR.source" ] || . <(sed 's/\r$//' "$SRC/config/kernel/$FLAVOR.source")
  if [ -n "$GIT" ]; then KSRC="$BUILD/src/$FLAVOR-${COMMIT:0:12}"; O="$KSRC"; fi
fi
[ -f "$O/Module.symvers" ] || { echo "no Module.symvers in $O: the flavor must be built with modules"; exit 1; }
[ -f "$KSRC/Makefile" ] || { echo "no kernel source at $KSRC"; exit 1; }
P=$(mktemp -d)
D="$P/usr/src/linux-headers-$KREL"
mkdir -p "$P/DEBIAN" "$P/lib/modules/$KREL"
make -C "$KSRC" O="$O" ARCH="$KARCH" CROSS_COMPILE="$CROSS" run-command \
  KBUILD_RUN_COMMAND="\${srctree}/scripts/package/install-extmod-build $D" >/dev/null
cp "$O/.config" "$D/.config"
ln -s "../../usr/src/linux-headers-$KREL" "$P/lib/modules/$KREL/build"
deb_control "$P" "$PKG" "$KVER-1" "$ARCH" kernel <<EOT
Depends: $IMGPKG (= $KVER-1), make, gcc | gcc-14, libc6-dev
Provides: kwick-kernel-headers, linux-headers-$KREL
Description: Linux $KVER kernel build tree for out-of-tree modules ($FLAVOR flavor)
 Provides /lib/modules/$KREL/build so DKMS and external module builds
 (NVIDIA open modules, ZFS, v4l2loopback, ...) work against the KwickOS kernel.
EOT
deb_build "$P" "$PKG" "$KVER-1" "$ARCH" "($ARCH)"
