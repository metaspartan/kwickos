#!/bin/bash
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}; VER=$(tr -d '\r\n' < "$SRC/VERSION")
P=$(mktemp -d); mkdir -p "$P/DEBIAN"
cp -r --no-preserve=ownership "$SRC/desktop/gaming/rootfs/." "$P/"
find "$P" -type d -exec chmod 755 {} +
find "$P" -type f -exec chmod 644 {} +
chmod 755 "$P"/usr/bin/*
cat > "$P/DEBIAN/control" <<EOF
Package: kwick-gaming
Version: $VER
Architecture: all
Maintainer: KwickOS Developers <dev@kwickos.org>
Section: games
Priority: optional
Installed-Size: 120
Depends: curl, ca-certificates, kwick-gpu
Recommends: flatpak, sudo
Replaces: kwick-desktop (<= $VER)
Description: KwickOS gaming modules
 Modular Bazzite-style gaming setup. 'kwick-gaming install <module>' adds Steam,
 the Steam Game Mode (Gamescope) session, Proton-GE, Lutris/Heroic/Bottles,
 MangoHud/GameMode/vkBasalt, controller rules, HHD for handhelds, Waydroid,
 Decky Loader, Sunshine/Moonlight, OpenRGB and performance tweaks. Debian
 packages are used where they exist, Flathub next, and pinned upstream
 releases with sha256 only where neither does. x86-only modules refuse to
 install on arm64 and riscv64.
EOF
cat > "$P/DEBIAN/postinst" <<'EOF'
#!/bin/sh
[ "$1" = configure ] || exit 0
mkdir -p /var/lib/kwick-gaming
command -v sysctl >/dev/null 2>&1 && sysctl -q -p /etc/sysctl.d/20-kwick-gaming.conf >/dev/null 2>&1 || true
exit 0
EOF
chmod 755 "$P/DEBIAN/postinst"
mkdir -p "$OUT/repo/pool/main"
dpkg-deb --root-owner-group -Zxz -b "$P" "$OUT/repo/pool/main/kwick-gaming_${VER}_all.deb" >/dev/null
rm -rf "$P"; echo "packaged kwick-gaming $VER"
