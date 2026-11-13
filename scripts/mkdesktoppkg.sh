#!/bin/bash
set -euo pipefail
ARCH=${1:?arch}; SRC=${SRC:-/src}; OUT=${OUT:-/out}
VER=$(tr -d '\r\n' < "$SRC/VERSION")
P=$(mktemp -d); mkdir -p "$P/DEBIAN"
cp -r --no-preserve=ownership "$SRC/desktop/rootfs/." "$P/"
find "$P" -type f \( -path '*/usr/lib/kwick/*' -o -path '*/usr/bin/kwick-*' \) -exec chmod 755 {} +
chmod 755 "$P/usr/lib/kwick/fetch-fonts"
"$P/usr/lib/kwick/fetch-fonts" "$P" all
"$SRC/scripts/mkroundedpkg.sh" "$P"
chmod 755 "$P/usr/lib/kwick/fetch-gnome-effects"
"$P/usr/lib/kwick/fetch-gnome-effects" "$P" all
rm -f "$P/etc/kinit/no-getty"
deps=$(grep -hv '^#' "$SRC/desktop/packages.list" | tr -s ' \n' '\n' | grep -Ev '^(firmware-|intel-media-va-driver-non-free|intel-microcode|amd64-microcode)' | tr '\n' ',' | sed 's/,$//; s/^,//; s/,/, /g')
deps="linux-image-kwick-generic, kwick-gpu, $deps"
cat > "$P/DEBIAN/control" <<EOF
Package: kwick-desktop
Version: $VER
Architecture: $ARCH
Maintainer: KwickOS Developers <dev@kwickos.org>
Section: metapackages
Priority: optional
Installed-Size: 40000
Depends: $deps
Description: KwickOS Desktop (KDE Plasma 6, Wayland)
 Turns a headless KwickOS into the desktop edition: Plasma, SDDM, PipeWire,
 NetworkManager, Mesa/GPU firmware, Flatpak, window effects and gaming tools.
EOF
cat > "$P/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
[ "$1" = configure ] || exit 0
rm -f /etc/systemd/system/multi-user.target.wants/networking.service
W=/etc/systemd/system/multi-user.target.wants; mkdir -p $W
for u in dbus kwick-elogind systemd-udevd kwick-udev-trigger kwick-session-report NetworkManager bluetooth polkit sddm upower udisks2 power-profiles-daemon rtkit-daemon; do
  f=$(ls /usr/lib/systemd/system/$u.service 2>/dev/null || true); [ -n "$f" ] && ln -sf "$f" $W/$u.service
done
for u in NetworkManager bluetooth upower rtkit-daemon polkit udisks2 power-profiles-daemon; do
  mkdir -p /etc/systemd/system/$u.service.d
  printf '[Service]\nExecStartPre=/usr/lib/kwick/wait-for dbus\nRestart=on-failure\n' > /etc/systemd/system/$u.service.d/kwick.conf
done
if ! id kwick >/dev/null 2>&1; then
  adduser --disabled-password --gecos "KwickOS" kwick >/dev/null 2>&1 || true
  for g in sudo video render audio input netdev bluetooth plugdev users; do grep -q "^$g:" /etc/group && adduser kwick $g >/dev/null 2>&1 || true; done
  echo "kwick: set a password with 'passwd kwick' (no password = no login except autologin)"
fi
rm -f /usr/lib/*/qt6/plugins/discover/packagekit-backend.so /usr/lib/*/qt6/plugins/discover/kns-backend.so
mkdir -p /etc/sddm.conf.d
[ -f /etc/sddm.conf.d/20-autologin.conf ] || printf '[Autologin]\nUser=kwick\nSession=plasma\nRelogin=false\n' > /etc/sddm.conf.d/20-autologin.conf
rm -f /etc/kinit/autologin
echo "KwickOS Desktop $(cut -d' ' -f2 /etc/kwick-release)" > /etc/kwick-edition
command -v flatpak >/dev/null && flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
nohup setsid sh -c 'for i in $(seq 1 600); do flock -n /var/lib/dpkg/lock-frontend true 2>/dev/null && break; sleep 1; done; /usr/sbin/kwick-gpu install >/var/log/kwick-gpu.log 2>&1' >/dev/null 2>&1 &
echo "KwickOS Desktop installed. Reboot to start the desktop (kernel: generic flavor via kwick-kernel-install)."
EOF
chmod 755 "$P/DEBIAN/postinst"
mkdir -p "$OUT/repo/pool/main"
dpkg-deb --root-owner-group -Zxz -b "$P" "$OUT/repo/pool/main/kwick-desktop_${VER}_${ARCH}.deb" >/dev/null
rm -rf "$P"; echo "packaged kwick-desktop $VER ($ARCH)"