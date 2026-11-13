#!/bin/bash
# Build the arch-independent `kwick-gpu` package: apt install kwick-gpu detects the GPU(s)
# (NVIDIA / AMD / Intel / Apple Silicon / virtio) and installs the matching drivers + firmware.
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}; VER=$(tr -d '\r\n' < "$SRC/VERSION")
P=$(mktemp -d); mkdir -p "$P/DEBIAN" "$P/usr/sbin"
install -m 755 "$SRC/rootfs/usr/sbin/kwick-gpu" "$P/usr/sbin/kwick-gpu"
cat > "$P/DEBIAN/control" <<EOF
Package: kwick-gpu
Version: $VER
Architecture: all
Maintainer: KwickOS Developers <dev@kwickos.org>
Section: metapackages
Priority: optional
Installed-Size: 20
Depends: pciutils
Description: KwickOS GPU driver selector
 Detects NVIDIA, AMD, Intel, Apple Silicon and virtio GPUs and installs the matching
 Mesa/Vulkan drivers and firmware. Re-run 'kwick-gpu install' after hardware changes.
EOF
printf '#!/bin/sh\nset -e\n[ "$1" = configure ] && /usr/sbin/kwick-gpu install || true\n' > "$P/DEBIAN/postinst"; chmod 755 "$P/DEBIAN/postinst"
mkdir -p "$OUT/repo/pool/main"
dpkg-deb --root-owner-group -Zxz -b "$P" "$OUT/repo/pool/main/kwick-gpu_${VER}_all.deb" >/dev/null
rm -rf "$P"; echo "packaged kwick-gpu $VER"