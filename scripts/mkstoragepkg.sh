#!/bin/bash
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}; VER=$(tr -d '\r\n' < "$SRC/VERSION")
P=$(mktemp -d); chmod 755 "$P"; mkdir -p "$P/DEBIAN"
cp -r --no-preserve=ownership "$SRC/storage/rootfs/." "$P/"
find "$P" -type f -exec sed -i 's/\r$//' {} +
find "$P" -type d -exec chmod 755 {} +
find "$P" -type f -exec chmod 644 {} +
chmod 755 "$P"/usr/bin/*
SIZE=$(du -sk "$P" | cut -f1)
cat > "$P/DEBIAN/control" <<EOF
Package: kwick-storage
Version: $VER
Architecture: all
Maintainer: KwickOS Developers <dev@kwickos.org>
Section: admin
Priority: optional
Installed-Size: $SIZE
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
cat > "$P/DEBIAN/postinst" <<'EOF'
#!/bin/sh
[ "$1" = configure ] || exit 0
mkdir -p /var/lib/kwick-storage /etc/kwick/storage
exit 0
EOF
chmod 755 "$P/DEBIAN/postinst"
mkdir -p "$OUT/repo/pool/main"
dpkg-deb --root-owner-group -Zxz -b "$P" "$OUT/repo/pool/main/kwick-storage_${VER}_all.deb" >/dev/null
rm -rf "$P"; echo "packaged kwick-storage $VER"
