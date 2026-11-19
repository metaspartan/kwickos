#!/bin/bash
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}
. "$(cd "$(dirname "$0")" && pwd)/deb.sh"
VER=$(kwick_version)
P=$(mktemp -d); mkdir -p "$P/DEBIAN"
deb_stage_tree "$P" "$SRC/storage/rootfs"
find "$P" -type f -exec sed -i 's/\r$//' {} +
deb_control "$P" kwick-storage "$VER" all admin <<EOF
Depends: ca-certificates
Recommends: curl, sudo
Suggests: kwick-zfs
Description: KwickOS storage and NAS modules
 Modular NAS setup in the spirit of Unraid, TrueNAS and OpenMediaVault.
 'kwick-storage install <module>' adds OpenZFS (prebuilt modules for the
 KwickOS kernel plus the Debian userland), mdadm and LVM, btrfs with snapper,
 a mergerfs + SnapRAID parity array, Samba/NFS shares with Windows and macOS
 discovery, an iSCSI target, SMART monitoring and spindown, NUT for UPSes,
 Docker/Podman, libvirt VMs and the Cockpit web console. Debian packages are
 used first, official upstream repositories next, and pinned downloads with
 sha256 only where neither has the software. Nothing is installed until a
 module is requested.
EOF
deb_script "$P" postinst <<'EOF'
#!/bin/sh
[ "$1" = configure ] || exit 0
mkdir -p /var/lib/kwick-storage /etc/kwick/storage
exit 0
EOF
deb_build "$P" kwick-storage "$VER" all
