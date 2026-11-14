#!/bin/bash
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}; VER=$(tr -d '\r\n' < "$SRC/VERSION")
P=$(mktemp -d); mkdir -p "$P/DEBIAN"
cp -r --no-preserve=ownership "$SRC/desktop/pen/rootfs/." "$P/"
find "$P" -type d -exec chmod 755 {} +
find "$P" -type f -exec chmod 644 {} +
chmod 755 "$P"/usr/bin/*
cat > "$P/DEBIAN/control" <<EOF
Package: kwick-pen
Version: $VER
Architecture: all
Maintainer: KwickOS Developers <dev@kwickos.org>
Section: utils
Priority: optional
Installed-Size: 160
Depends: curl, ca-certificates
Recommends: flatpak, sudo, pipx
Description: KwickOS security toolkit modules
 Optional Kali-style toolkit. 'kwick-pen install <module>' adds recon, web,
 network, passwords, wireless, exploit, ad, re, forensics, mobile, cloud, osint
 or defense tools. Debian 13 packages are used first, then Flathub, vendor
 repositories and pinned upstream releases with sha256. Kali repositories are
 never added, because mixing archives breaks Debian systems. Tools that do not
 exist for the machine architecture are skipped. Adds a Security menu folder.
 For authorized security testing only.
EOF
cat > "$P/DEBIAN/postinst" <<'EOF'
#!/bin/sh
[ "$1" = configure ] || exit 0
mkdir -p /var/lib/kwick-pen
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications >/dev/null 2>&1 || true
exit 0
EOF
chmod 755 "$P/DEBIAN/postinst"
mkdir -p "$OUT/repo/pool/main"
dpkg-deb --root-owner-group -Zxz -b "$P" "$OUT/repo/pool/main/kwick-pen_${VER}_all.deb" >/dev/null
rm -rf "$P"; echo "packaged kwick-pen $VER"
