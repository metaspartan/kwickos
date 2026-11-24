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
for f in usr/bin/kwick-shell usr/bin/kwick-vpn usr/bin/kfetch usr/lib/kwick/shell-helper usr/lib/kwick/shell-env; do
  mkdir -p "$P/$(dirname "$f")"; sed 's/\r$//' "$SRC/rootfs/$f" > "$P/$f"; chmod 755 "$P/$f"
done
mkdir -p "$P/usr/lib/kwick/base"
for f in add-shell remove-shell; do
  sed 's/\r$//' "$SRC/rootfs/usr/sbin/$f" > "$P/usr/lib/kwick/base/$f"; chmod 755 "$P/usr/lib/kwick/base/$f"
done
for f in usr/share/kwick/shell/prompt.sh usr/share/kwick/shell/starship.toml usr/share/kwick/shell/kwick.ps1 usr/share/kwick/zsh/kwick.zsh \
  usr/share/fish/vendor_conf.d/kwick.fish usr/share/elvish/lib/kwick.elv usr/share/nushell/vendor/autoload/kwick.nu \
  etc/xonsh/rc.d/kwick.xsh etc/ashrc etc/profile.d/30-kwick-shells.sh etc/skel/.zshrc etc/skel/.config/elvish/rc.elv; do
  mkdir -p "$P/$(dirname "$f")"; sed 's/\r$//' "$SRC/rootfs/$f" > "$P/$f"; chmod 644 "$P/$f"
done
find "$P" -type d -exec chmod 755 {} +
deb_control "$P" kwick-update "$VER" all admin <<EOT
Replaces: kwick-base
Depends: kwick-core (>= $VER)
Recommends: curl
Description: KwickOS Software Update, kernel manager and system snapshots
 kwick-update (checks, upgrades, automatic updates through crond),
 kwick-kernel (install, try once, default, roll back) with the boot
 confirmation service that settles one-shot kernel trials, and
 kwick-snapshot (Btrfs system snapshots before and after every package
 change, an hourly timeline, file restore and whole-system rollback), plus
 the base tools the desktop calls (kwick-shell with its prompt presets,
 kwick-vpn, kfetch). New images carry these in the base system; this package
 brings them to systems installed from an older image and keeps them current.
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
for f in add-shell remove-shell; do
  [ -e /usr/sbin/$f ] || [ -L /usr/sbin/$f ] || cp /usr/lib/kwick/base/$f /usr/sbin/$f
done
if [ -f /etc/profile ] && ! grep -q ashrc /etc/profile; then
  printf '%s\n' 'if [ -z "${BASH_VERSION:-}${ZSH_VERSION:-}" ]; then ENV=/etc/ashrc; export ENV; fi' \
    'case $- in *i*) [ -z "${ZSH_VERSION:-}" ] && [ -r /etc/ashrc ] && . /etc/ashrc ;; esac' >> /etc/profile
fi
if [ -d /usr/share/kwick/settings ] && grep -qs Desktop /etc/kwick-edition; then
  case $(dpkg-query -W -f='${Status}' kwick-desktop 2>/dev/null) in
    *" installed") ;;
    *)
      echo "kwick-update: this desktop was installed from an image that did not register kwick-desktop; it is installed as soon as this apt run ends, so desktop updates arrive (progress: kwick-update log)"
      nohup setsid /usr/sbin/kwick-update adopt-desktop --wait >/dev/null 2>&1 &
      ;;
  esac
fi
exit 0
EOT
deb_build "$P" kwick-update "$VER" all
