#!/bin/bash
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}
. "$(cd "$(dirname "$0")" && pwd)/deb.sh"
VER=$(kwick_version)
P=$(mktemp -d); mkdir -p "$P/DEBIAN"
deb_stage_tree "$P" "$SRC/desktop/arch/rootfs"
find "$P" -type f -exec sed -i 's/\r$//' {} +
printf '%s\n' "$VER" > "$P/usr/lib/kwick/arch/VERSION"
chmod 644 "$P/usr/lib/kwick/arch/VERSION"
chmod 755 "$P/usr/bin/kwick-arch"
if command -v python3 >/dev/null; then python3 -m py_compile "$P"/usr/lib/kwick/arch/kwickarch/*.py; fi
find "$P" -name __pycache__ -type d -exec rm -rf {} +
printf '/etc/kwick/arch.conf\n' > "$P/DEBIAN/conffiles"
deb_control "$P" kwick-arch "$VER" all utils <<EOF
Depends: python3 (>= 3.12), bubblewrap, zstd, gpgv, archlinux-keyring, ca-certificates
Recommends: desktop-file-utils, curl
Description: Arch Linux repositories and the AUR on KwickOS, security-gated
 kwick-arch runs Arch Linux (core, extra, multilib) and AUR packages in an
 Arch environment under /var/lib/kwick/arch, bootstrapped from the official
 Arch bootstrap tarball after checking its PGP signature against Debian's
 archlinux-keyring. Programs run with bubblewrap as the calling user and share
 the home directory, Wayland/X11, PipeWire, the GPU, fonts and D-Bus; installed
 apps appear in the host menu, Spotlight and PATH. Packages with open issues in
 the Arch Security Tracker are refused unless --allow-vulnerable is given; AUR
 packages are reviewed with a risk report, need confirmation, are built as an
 unprivileged user without network access and are pinned to the reviewed
 commit. x86_64 only.
EOF
deb_script "$P" postinst <<'EOF'
#!/bin/sh
[ "$1" = configure ] || exit 0
mkdir -p /var/lib/kwick/arch
chmod 755 /var/lib/kwick /var/lib/kwick/arch
exit 0
EOF
deb_script "$P" prerm <<'EOF'
#!/bin/sh
[ "$1" = remove ] || exit 0
[ -x /usr/bin/kwick-arch ] && /usr/bin/kwick-arch disable >/dev/null 2>&1
exit 0
EOF
deb_script "$P" postrm <<'EOF'
#!/bin/sh
[ "$1" = purge ] || exit 0
rm -rf /var/lib/kwick/arch /usr/local/lib/kwick-arch
exit 0
EOF
deb_build "$P" kwick-arch "$VER" all
