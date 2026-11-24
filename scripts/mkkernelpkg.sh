#!/bin/bash
set -euo pipefail
ARCH=${1:?arch}; FLAVOR=${2:?flavor}
OUT=${OUT:-/out}; SRC=${SRC:-/src}; K="$OUT/$ARCH/kernel-$FLAVOR"
. "$(cd "$(dirname "$0")" && pwd)/deb.sh"
DEP=
[ ! -f "$SRC/config/kernel/$FLAVOR.source" ] || DEP=$(sed -n "s/^PKG_DEPENDS=//p" "$SRC/config/kernel/$FLAVOR.source" | tr -d "\r\"")
KREL=$(cat "$K/version")
KVER=${KREL%%-kwick*}; KDEBV=$(kernel_deb_version "$KVER")
P=$(mktemp -d)
mkdir -p "$P/DEBIAN" "$P/usr/lib/kwick/kernels/$KREL"
cp "$K/vmlinuz" "$K/config" "$P/usr/lib/kwick/kernels/$KREL/"
[ -f "$K/vmlinuz.efi" ] && cp "$K/vmlinuz.efi" "$P/usr/lib/kwick/kernels/$KREL/"
[ -d "$K/dtbs" ] && cp -r "$K/dtbs" "$P/usr/lib/kwick/kernels/$KREL/"
for f in Image.itb initrd.img load-address uboot.txt; do [ -f "$K/$f" ] && cp "$K/$f" "$P/usr/lib/kwick/kernels/$KREL/"; done
if [ -f "$K/modules.tar.zst" ]; then zstd -dc "$K/modules.tar.zst" | tar -C "$P/usr" -x; fi
echo "$FLAVOR" > "$P/usr/lib/kwick/kernels/$KREL/flavor"
deb_control "$P" "linux-image-kwick-$FLAVOR" "$KDEBV" "$ARCH" kernel <<EOF
Provides: linux-image, linux-image-$KREL
Pre-Depends: kwick-update (>= $(kwick_version))
${DEP:+Depends: $DEP
}Description: Linux $KVER kernel for KwickOS ($FLAVOR flavor)
 Self-contained UEFI kernel image with the kinit root finder embedded.
 Installing it makes it the next boot kernel; the previous one is kept
 for rollback and can be chosen again (kwick-kernel list, default, try, rollback).
EOF
deb_script "$P" preinst <<EOF
#!/bin/sh
set -e
if [ -x /usr/sbin/kwick-kernel ]; then
	/usr/sbin/kwick-kernel _retain || true
fi
EOF
deb_script "$P" postinst <<EOF
#!/bin/sh
set -e
if [ "\$1" = configure ] && [ -x /usr/sbin/kwick-kernel-install ]; then
	/usr/sbin/kwick-kernel-install $KREL || true
fi
EOF
deb_build "$P" "linux-image-kwick-$FLAVOR" "$KDEBV" "$ARCH" "($ARCH)"
