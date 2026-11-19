#!/bin/bash
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}
. "$(cd "$(dirname "$0")" && pwd)/deb.sh"
VER=$(kwick_version)
P=$(mktemp -d); mkdir -p "$P/DEBIAN" "$P/usr/sbin"
install -m 755 "$SRC/rootfs/usr/sbin/kwick-gpu" "$P/usr/sbin/kwick-gpu"
deb_control "$P" kwick-gpu "$VER" all metapackages 20 <<EOF
Depends: pciutils
Description: KwickOS GPU driver selector
 Detects NVIDIA, AMD, Intel, Apple Silicon and virtual GPUs (PCI vendor IDs, device tree) and
 installs the matching Mesa/Vulkan drivers and firmware, plus 32-bit Mesa/Vulkan for Steam where
 the package manager supports i386. Commands: detect, install, status, rocm, steam. Re-run
 'kwick-gpu install' after hardware changes.
EOF
deb_script "$P" postinst <<'PI'
#!/bin/sh
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
deb_build "$P" kwick-gpu "$VER" all
