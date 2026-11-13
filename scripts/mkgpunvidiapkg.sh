#!/bin/bash
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}
. "$SRC/config/nvidia.env"
VER=$(tr -d '\r\n' < "$SRC/VERSION")
P=$(mktemp -d)
mkdir -p "$P/DEBIAN" "$P/usr/lib/kwick"
install -m 755 "$SRC/nvidia/rootfs/usr/lib/kwick/gpu-nvidia" "$P/usr/lib/kwick/gpu-nvidia"
sed -i "s|^VERSION=.*|VERSION=\${KWICK_NVIDIA_DRIVER_VERSION:-$NVIDIA_DRIVER_VERSION}|; s|^REVISION=.*|REVISION=\${KWICK_NVIDIA_PKG_REVISION:-$NVIDIA_PKG_REVISION}|; s|^FPR=.*|FPR=\${KWICK_NVIDIA_KEY_FPR:-$NVIDIA_CUDA_KEY_FPR}|; s|^BASE=.*|BASE=\${KWICK_NVIDIA_REPO_BASE:-$NVIDIA_CUDA_REPO_BASE}|" "$P/usr/lib/kwick/gpu-nvidia"
SIZE=$(du -sk "$P" | cut -f1)
cat > "$P/DEBIAN/control" <<EOT
Package: kwick-gpu-nvidia
Version: $VER
Architecture: all
Maintainer: KwickOS Developers <dev@kwickos.org>
Section: admin
Priority: optional
Installed-Size: $SIZE
Depends: ca-certificates, curl, gnupg
Description: NVIDIA proprietary driver stack helper for kwick-gpu
 Adds NVIDIA's official Debian 13 CUDA repository (x86_64 or sbsa) with a signed-by keyring whose
 fingerprint is verified, pins the driver userspace to $NVIDIA_DRIVER_VERSION, and installs the
 matching prebuilt open kernel modules (kwick-nvidia-kmod-<kernel>) plus driver libraries,
 nvidia-smi, the Vulkan and EGL ICDs and 32-bit libraries where enabled.
EOT
mkdir -p "$OUT/repo/pool/main"
dpkg-deb --root-owner-group -Zxz -b "$P" "$OUT/repo/pool/main/kwick-gpu-nvidia_${VER}_all.deb" >/dev/null
rm -rf "$P"
echo "packaged kwick-gpu-nvidia $VER"
