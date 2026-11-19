#!/bin/bash
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}
. "$(cd "$(dirname "$0")" && pwd)/deb.sh"
VER=$(kwick_version)
P=$(mktemp -d); mkdir -p "$P/DEBIAN"
deb_stage_tree "$P" "$SRC/desktop/pen/rootfs"
deb_control "$P" kwick-pen "$VER" all utils 160 <<EOF
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
deb_script "$P" postinst <<'EOF'
#!/bin/sh
[ "$1" = configure ] || exit 0
mkdir -p /var/lib/kwick-pen
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q /usr/share/applications >/dev/null 2>&1 || true
exit 0
EOF
deb_build "$P" kwick-pen "$VER" all
