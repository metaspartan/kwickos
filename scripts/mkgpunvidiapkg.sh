#!/bin/bash
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}
. "$(cd "$(dirname "$0")" && pwd)/deb.sh"
. "$SRC/config/nvidia.env"
VER=$(kwick_version)
P=$(mktemp -d)
mkdir -p "$P/DEBIAN" "$P/usr/lib/kwick"
install -m 755 "$SRC/nvidia/rootfs/usr/lib/kwick/gpu-nvidia" "$P/usr/lib/kwick/gpu-nvidia"
sed -i "s|^VERSION=.*|VERSION=\${KWICK_NVIDIA_DRIVER_VERSION:-$NVIDIA_DRIVER_VERSION}|; s|^REVISION=.*|REVISION=\${KWICK_NVIDIA_PKG_REVISION:-$NVIDIA_PKG_REVISION}|; s|^FPR=.*|FPR=\${KWICK_NVIDIA_KEY_FPR:-$NVIDIA_CUDA_KEY_FPR}|; s|^BASE=.*|BASE=\${KWICK_NVIDIA_REPO_BASE:-$NVIDIA_CUDA_REPO_BASE}|" "$P/usr/lib/kwick/gpu-nvidia"
deb_control "$P" kwick-gpu-nvidia "$VER" all admin <<EOT
Depends: ca-certificates, curl, gnupg
Description: NVIDIA proprietary driver stack helper for kwick-gpu
 Adds NVIDIA's official Debian 13 CUDA repository (x86_64 or sbsa) with a signed-by keyring whose
 fingerprint is verified, pins the driver userspace to $NVIDIA_DRIVER_VERSION, and installs the
 matching prebuilt open kernel modules (kwick-nvidia-kmod-<kernel>) plus driver libraries,
 nvidia-smi, the Vulkan and EGL ICDs and 32-bit libraries where enabled.
EOT
deb_build "$P" kwick-gpu-nvidia "$VER" all
