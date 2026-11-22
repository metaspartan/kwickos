#!/bin/bash
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}
. "$(cd "$(dirname "$0")" && pwd)/deb.sh"
VER=$(kwick_version)
P=$(mktemp -d); mkdir -p "$P/DEBIAN" "$P/usr/sbin" "$P/usr/lib/systemd/system" "$P/usr/lib/kwick" "$P/etc/apt/apt.conf.d"
for f in kwick-update kwick-kernel kwick-kernel-install kwick-bootctl kwick-snapshot; do
  sed 's/\r$//' "$SRC/rootfs/usr/sbin/$f" > "$P/usr/sbin/$f"; chmod 755 "$P/usr/sbin/$f"
done
for u in kwick-kernel-confirm crond kwick-boot-ok kwick-snapshot-boot; do
  sed 's/\r$//' "$SRC/rootfs/usr/lib/systemd/system/$u.service" > "$P/usr/lib/systemd/system/$u.service"; chmod 644 "$P/usr/lib/systemd/system/$u.service"
done
for f in boot-ok debsec; do
  sed 's/\r$//' "$SRC/rootfs/usr/lib/kwick/$f" > "$P/usr/lib/kwick/$f"; chmod 755 "$P/usr/lib/kwick/$f"
done
sed 's/\r$//' "$SRC/rootfs/etc/apt/apt.conf.d/80kwick-snapshot" > "$P/etc/apt/apt.conf.d/80kwick-snapshot"; chmod 644 "$P/etc/apt/apt.conf.d/80kwick-snapshot"
find "$P" -type d -exec chmod 755 {} +
deb_control "$P" kwick-update "$VER" all admin <<EOT
Replaces: kwick-base
Recommends: curl, ca-certificates
Description: KwickOS Software Update, kernel manager and system snapshots
 kwick-update (checks, upgrades, automatic updates through crond),
 kwick-kernel (install, try once, default, roll back) with the boot
 confirmation service that settles one-shot kernel trials, and
 kwick-snapshot (Btrfs system snapshots before and after every package
 change, an hourly timeline, file restore and whole-system rollback). New
 images carry these in the base system; this package brings them to systems
 installed from an older image and keeps them current.
EOT
deb_script "$P" postinst <<'EOT'
#!/bin/sh
set -e
[ "$1" = configure ] || exit 0
mkdir -p /etc/systemd/system/multi-user.target.wants
for u in kwick-kernel-confirm kwick-boot-ok; do
  [ -e "/etc/systemd/system/multi-user.target.wants/$u.service" ] || ln -s "/usr/lib/systemd/system/$u.service" "/etc/systemd/system/multi-user.target.wants/$u.service"
done
if awk '$2 == "/.snapshots" && $3 == "btrfs" { f = 1 } END { exit !f }' /proc/mounts 2>/dev/null; then
  [ -e /etc/systemd/system/multi-user.target.wants/kwick-snapshot-boot.service ] || ln -s /usr/lib/systemd/system/kwick-snapshot-boot.service /etc/systemd/system/multi-user.target.wants/kwick-snapshot-boot.service
fi
mkdir -p /var/lib/kwick/update /var/lib/kwick/kernel-state
chmod 755 /var/lib/kwick /var/lib/kwick/update /var/lib/kwick/kernel-state
exit 0
EOT
deb_build "$P" kwick-update "$VER" all
