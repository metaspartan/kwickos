#!/bin/bash
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}; VER=$(tr -d '\r\n' < "$SRC/VERSION")
P=$(mktemp -d); mkdir -p "$P/DEBIAN"
cp -r --no-preserve=ownership "$SRC/desktop/agents/rootfs/." "$P/"
find "$P" -type d -exec chmod 755 {} +
find "$P" -type f -exec chmod 644 {} +
chmod 755 "$P"/usr/bin/*
cat > "$P/DEBIAN/control" <<EOF
Package: kwick-agents
Version: $VER
Architecture: all
Maintainer: KwickOS Developers <dev@kwickos.org>
Section: utils
Priority: optional
Installed-Size: 40
Depends: curl, ca-certificates
Recommends: sudo
Description: KwickOS AI agent tooling modules
 Optional AI agent modules. 'kwick-agents install cybara' installs the Cybara
 self-hosted agent platform CLI from the official release, pinned to a version
 and verified against its sha256. Nothing is installed by default. amd64 and
 arm64 only for Cybara.
EOF
cat > "$P/DEBIAN/postinst" <<'EOF'
#!/bin/sh
[ "$1" = configure ] || exit 0
mkdir -p /var/lib/kwick-agents
exit 0
EOF
chmod 755 "$P/DEBIAN/postinst"
mkdir -p "$OUT/repo/pool/main"
dpkg-deb --root-owner-group -Zxz -b "$P" "$OUT/repo/pool/main/kwick-agents_${VER}_all.deb" >/dev/null
rm -rf "$P"; echo "packaged kwick-agents $VER"
