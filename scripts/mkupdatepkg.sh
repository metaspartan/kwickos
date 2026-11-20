#!/bin/bash
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}
. "$(cd "$(dirname "$0")" && pwd)/deb.sh"
VER=$(kwick_version)
P=$(mktemp -d); mkdir -p "$P/DEBIAN" "$P/usr/sbin" "$P/usr/lib/systemd/system" "$P/usr/lib/kwick"
for f in kwick-update kwick-kernel kwick-kernel-install kwick-bootctl; do
  sed 's/\r$//' "$SRC/rootfs/usr/sbin/$f" > "$P/usr/sbin/$f"; chmod 755 "$P/usr/sbin/$f"
done
for u in kwick-kernel-confirm crond kwick-boot-ok; do
  sed 's/\r$//' "$SRC/rootfs/usr/lib/systemd/system/$u.service" > "$P/usr/lib/systemd/system/$u.service"; chmod 644 "$P/usr/lib/systemd/system/$u.service"
done
sed 's/\r$//' "$SRC/rootfs/usr/lib/kwick/boot-ok" > "$P/usr/lib/kwick/boot-ok"; chmod 755 "$P/usr/lib/kwick/boot-ok"
find "$P" -type d -exec chmod 755 {} +
deb_control "$P" kwick-update "$VER" all admin <<EOF
Replaces: kwick-base
Description: KwickOS Software Update and kernel manager
 kwick-update (checks, upgrades, automatic updates through crond) and
 kwick-kernel (install, try once, default, roll back), with the boot
 confirmation service that settles one-shot kernel trials. New images carry
 these in the base system; this package brings them to systems installed
 from an older image and keeps them current.
EOF
deb_script "$P" postinst <<'EOF'
#!/bin/sh
set -e
[ "$1" = configure ] || exit 0
mkdir -p /etc/systemd/system/multi-user.target.wants
for u in kwick-kernel-confirm kwick-boot-ok; do
  [ -e "/etc/systemd/system/multi-user.target.wants/$u.service" ] || ln -s "/usr/lib/systemd/system/$u.service" "/etc/systemd/system/multi-user.target.wants/$u.service"
done
mkdir -p /var/lib/kwick/update /var/lib/kwick/kernel-state
chmod 755 /var/lib/kwick /var/lib/kwick/update /var/lib/kwick/kernel-state
exit 0
EOF
deb_build "$P" kwick-update "$VER" all
