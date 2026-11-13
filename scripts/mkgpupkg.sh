#!/bin/bash
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
 Detects NVIDIA, AMD, Intel, Apple Silicon and virtual GPUs (PCI vendor IDs, device tree) and
 installs the matching Mesa/Vulkan drivers and firmware, plus 32-bit Mesa/Vulkan for Steam where
 the package manager supports i386. Commands: detect, install, status, rocm, steam. Re-run
 'kwick-gpu install' after hardware changes.
EOF
cat > "$P/DEBIAN/postinst" <<'PI'
#!/bin/sh
# apt holds the dpkg lock while this runs, so the vendor-specific install is deferred:
# a detached job waits for the lock to be released, then runs `kwick-gpu install`.
[ "$1" = configure ] || exit 0
[ -n "${KWICK_GPU_NO_AUTO:-}" ] && exit 0
nohup setsid sh -c '
  for i in $(seq 1 600); do
    flock -n /var/lib/dpkg/lock-frontend true 2>/dev/null && break; sleep 1
  done
  /usr/sbin/kwick-gpu install >/var/log/kwick-gpu.log 2>&1' >/dev/null 2>&1 &
echo "kwick-gpu: detected-hardware drivers install right after apt finishes (log: /var/log/kwick-gpu.log)"
exit 0
PI
chmod 755 "$P/DEBIAN/postinst"
mkdir -p "$OUT/repo/pool/main"
dpkg-deb --root-owner-group -Zxz -b "$P" "$OUT/repo/pool/main/kwick-gpu_${VER}_all.deb" >/dev/null
rm -rf "$P"; echo "packaged kwick-gpu $VER"