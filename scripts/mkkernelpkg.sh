#!/bin/bash
set -euo pipefail
ARCH=${1:?arch}; FLAVOR=${2:?flavor}
OUT=${OUT:-/out}; K="$OUT/$ARCH/kernel-$FLAVOR"
KREL=$(cat "$K/version")
KVER=${KREL%-kwick}
P=$(mktemp -d)
mkdir -p "$P/DEBIAN" "$P/usr/lib/kwick/kernels/$KREL"
cp "$K/vmlinuz" "$K/config" "$P/usr/lib/kwick/kernels/$KREL/"
[ -f "$K/vmlinuz.efi" ] && cp "$K/vmlinuz.efi" "$P/usr/lib/kwick/kernels/$KREL/"
if [ -f "$K/modules.tar.zst" ]; then zstd -dc "$K/modules.tar.zst" | tar -C "$P/usr" -x; fi
SIZE=$(du -sk "$P" | cut -f1)
cat > "$P/DEBIAN/control" <<EOF
Package: linux-image-kwick-$FLAVOR
Version: $KVER-1
Architecture: $ARCH
Maintainer: KwickOS Developers <dev@kwickos.org>
Section: kernel
Priority: optional
Installed-Size: $SIZE
Provides: linux-image, linux-image-$KREL
Description: Linux $KVER kernel for KwickOS ($FLAVOR flavor)
 Self-contained UEFI kernel image with the kinit root finder embedded.
 Installing it makes it the next boot kernel; the previous one is kept
 for rollback (kwick-kernel-install --rollback).
EOF
cat > "$P/DEBIAN/postinst" <<EOF
#!/bin/sh
set -e
if [ "\$1" = configure ] && [ -x /usr/sbin/kwick-kernel-install ]; then
	/usr/sbin/kwick-kernel-install $KREL || true
fi
EOF
chmod 755 "$P/DEBIAN/postinst"
mkdir -p "$OUT/repo/pool/main"
dpkg-deb --root-owner-group -Zxz -b "$P" "$OUT/repo/pool/main/linux-image-kwick-${FLAVOR}_${KVER}-1_${ARCH}.deb" >/dev/null
rm -rf "$P"
echo "packaged linux-image-kwick-$FLAVOR $KVER-1 ($ARCH)"
