#!/bin/bash
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}
. "$(cd "$(dirname "$0")" && pwd)/deb.sh"
VER=$(kwick_version)
P=$(mktemp -d); mkdir -p "$P/DEBIAN"
deb_stage_tree "$P" "$SRC/desktop/gaming/rootfs"
deb_control "$P" kwick-gaming "$VER" all games 120 <<EOF
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
deb_script "$P" postinst <<'EOF'
#!/bin/sh
[ "$1" = configure ] || exit 0
mkdir -p /var/lib/kwick-gaming
command -v sysctl >/dev/null 2>&1 && sysctl -q -p /etc/sysctl.d/20-kwick-gaming.conf >/dev/null 2>&1 || true
exit 0
EOF
deb_build "$P" kwick-gaming "$VER" all
