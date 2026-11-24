#!/bin/bash
set -euo pipefail
ARCH=${1:?arch}; SRC=${SRC:-/src}; OUT=${OUT:-/out}
. "$(cd "$(dirname "$0")" && pwd)/deb.sh"
VER=$(kwick_version)
P=$(mktemp -d); mkdir -p "$P/DEBIAN"
cp -r --no-preserve=ownership "$SRC/desktop/rootfs/." "$P/"
find "$P" -type f \( -path '*/usr/lib/kwick/*' -o -path '*/usr/bin/kwick-*' \) -exec chmod 755 {} +
T="$P/usr/share/kwick/tiling"; K="$P/etc/skel/.config"
mkdir -p "$K/hypr" "$K/sway"
cp "$T/common/hyprland.conf" "$K/hypr/hyprland.conf"
cp "$T/macos/hyprland.conf" "$K/hypr/kwick-layout.conf"
: > "$K/hypr/kwick-effects.conf"; : > "$K/hypr/kwick-bars.conf"; : > "$K/hypr/kwick-touch.conf"
cp "$T/common/sway.conf" "$K/sway/config"
sed 's/@UI@/Inter/g' "$T/macos/sway.conf" > "$K/sway/kwick-layout.conf"
for wm in hyprland sway; do
  out="$K/$([ $wm = hyprland ] && echo hypr || echo sway)/kwick-keys.conf"
  KWICK_KEYS_DATA="$P/usr/share/kwick/keys" python3 -I "$P/usr/bin/kwick-keys" generate --session $wm --layout macos > "$out" 2>/dev/null || : > "$out"
done
for l in macos windows linux; do cp "$P/usr/share/kwick/plasma/$l.js" "$P/usr/share/plasma/look-and-feel/org.kwickos.$l/contents/layouts/org.kde.plasma.desktop-layout.js"; done
chmod 755 "$P/usr/lib/kwick/fetch-fonts"
"$P/usr/lib/kwick/fetch-fonts" "$P" all
kwin_plugin() {
  local name=$1 script=$2
  if [ -d "$OUT/kwin-$name-$ARCH/usr" ]; then
    cp -r --no-preserve=ownership "$OUT/kwin-$name-$ARCH/." "$P/"
  elif [ "$(dpkg --print-architecture)" = "$ARCH" ]; then
    bash "$SRC/scripts/$script" "$P"
  else
    echo "no prebuilt kwin-$name-$ARCH in $OUT and this host is $(dpkg --print-architecture)" >&2
    exit 1
  fi
}
kwin_plugin rounded mkroundedpkg.sh
kwin_plugin flip mkflippkg.sh
kwin_plugin liquidglass mkglasspkg.sh
kwin_plugin macstyle mkmacstylepkg.sh
kwin_plugin spotlight mkspotlightpkg.sh
kwin_plugin native mknativepkg.sh
kwin_plugin keyboard mkkeyboardpkg.sh
kwin_plugin settings mksettingspkg.sh
chmod 755 "$P/usr/lib/kwick/fetch-effects"
"$P/usr/lib/kwick/fetch-effects" "$P" all
mkdir -p "$P/etc/kinit"; printf 'tty1\n' > "$P/etc/kinit/no-getty"
deb_conffiles "$P"
deps=$(grep -hv '^#' "$SRC/desktop/packages.list" | tr -s ' \n' '\n' | grep -Ev '^(firmware-|intel-media-va-driver-non-free|intel-microcode|amd64-microcode)' | tr '\n' ',' | sed 's/,$//; s/^,//; s/,/, /g')
deps="linux-image-kwick-generic | linux-image-kwick-rpi, kwick-gpu, kwick-gaming, kwick-essentials, kwick-update, $deps"
deb_control "$P" kwick-desktop "$VER" "$ARCH" metapackages 40000 <<EOF
Depends: $deps
Description: KwickOS Desktop (KDE Plasma 6, Wayland)
 Turns a headless KwickOS into the desktop edition: Plasma, SDDM, PipeWire,
 NetworkManager, Mesa/GPU firmware, Flatpak, window effects and gaming tools.
EOF
deb_script "$P" postinst <<'EOF'
#!/bin/sh
set -e
[ "$1" = configure ] || exit 0
FIRST=0; ADOPT=0
if [ -z "${2:-}" ]; then
  if grep -qs Desktop /etc/kwick-edition; then ADOPT=1; else FIRST=1; fi
fi
H=/usr/share/kwick/conffiles.md5
if [ -f "$H" ] && [ -f /var/lib/dpkg/info/kwick-desktop.conffiles ]; then
  while read -r f; do
    [ -f "$f.dpkg-dist" ] && [ -f "$f" ] || continue
    if grep -qxF "$(md5sum < "$f" | cut -d' ' -f1)  $f" "$H"; then
      mv -f "$f.dpkg-dist" "$f"
    else
      echo "KwickOS Desktop: kept your changes to $f; the new version is $f.dpkg-dist"
    fi
  done < /var/lib/dpkg/info/kwick-desktop.conffiles
fi
if [ $FIRST = 1 ] && [ -f /etc/network/interfaces ] && grep -E '^[[:space:]]*iface[[:space:]]' /etc/network/interfaces | grep -qvE '^[[:space:]]*iface[[:space:]]+lo[[:space:]]'; then
  cp /etc/network/interfaces /etc/network/interfaces.kwick-headless
  printf 'auto lo\niface lo inet loopback\n\nsource-directory /etc/network/interfaces.d\n' > /etc/network/interfaces
fi
/usr/lib/kwick/desktop-units enable >/dev/null
install -d -m 1733 /var/lib/kwick/cores
[ -w /proc/sys/kernel/core_pattern ] && sed -n 's/^kernel.core_pattern = //p' /usr/lib/sysctl.d/60-kwick-cores.conf > /proc/sys/kernel/core_pattern 2>/dev/null || true
touch -r /usr /etc/.updated /var/.updated
command -v kwick-shell >/dev/null && kwick-shell --default zsh >/dev/null 2>&1 || true
if [ $FIRST = 1 ] && ! id kwick >/dev/null 2>&1; then
  adduser --disabled-password --gecos "KwickOS" --shell /bin/zsh kwick >/dev/null 2>&1 || true
  for g in sudo video render audio input netdev bluetooth plugdev users; do grep -q "^$g:" /etc/group && adduser kwick $g >/dev/null 2>&1 || true; done
  echo "kwick: set a password with 'passwd kwick' (no password = no login except autologin)"
fi
if [ -f /usr/share/kwick/faces/kwickos.png ]; then
  mkdir -p /var/lib/AccountsService/icons /var/lib/AccountsService/users
  awk -F: '$3 >= 1000 && $3 < 60000 { print $1 }' /etc/passwd | while read -r u; do
    h=$(getent passwd "$u" | cut -d: -f6)
    if [ -n "$h" ] && [ -f /etc/skel/.face ] && [ -f "$h/.face" ] && [ ! -L "$h/.face" ] && cmp -s /etc/skel/.face "$h/.face"; then
      cp /usr/share/kwick/faces/kwickos.png "$h/.face"
      chown "$u:" "$h/.face" 2>/dev/null || true
    fi
    [ -e "/var/lib/AccountsService/icons/$u" ] && continue
    cp /usr/share/kwick/faces/kwickos.png "/var/lib/AccountsService/icons/$u"
    chmod 644 "/var/lib/AccountsService/icons/$u"
    [ -e "/var/lib/AccountsService/users/$u" ] || { printf '[User]\nIcon=/var/lib/AccountsService/icons/%s\nSystemAccount=false\n' "$u" > "/var/lib/AccountsService/users/$u"; chmod 600 "/var/lib/AccountsService/users/$u"; }
  done
fi
if command -v locale-gen >/dev/null; then
  grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen 2>/dev/null || echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
  locale-gen >/dev/null 2>&1 || true
  grep -qs '^LANG=' /etc/default/locale || update-locale LANG=en_US.UTF-8 >/dev/null 2>&1 || true
fi
rm -f /usr/lib/*/qt6/plugins/discover/packagekit-backend.so /usr/lib/*/qt6/plugins/discover/kns-backend.so
for t in KwickOS KwickOS-Fluent KwickOS-Linux hicolor; do command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -f -t /usr/share/icons/$t >/dev/null 2>&1 || true; done
mkdir -p /etc/sddm.conf.d
[ $FIRST = 0 ] || [ -f /etc/sddm.conf.d/20-autologin.conf ] || printf '[Autologin]\nUser=kwick\nSession=plasma\nRelogin=false\n' > /etc/sddm.conf.d/20-autologin.conf
printf 'tty1\n' > /etc/kinit/no-getty
if [ -d /etc/sudoers.d ]; then
  printf 'kwick ALL=(root) NOPASSWD: /usr/sbin/kwick-gpu steam\n' > /etc/sudoers.d/kwick-steam
  chmod 440 /etc/sudoers.d/kwick-steam
fi
if awk -F: '$1=="root" && $2 ~ /^(\*|!.*|)$/ {f=1} END{exit !f}' /etc/shadow 2>/dev/null; then
  echo "KwickOS Desktop: root has no password, so the serial console keeps its root autologin. Set one with 'passwd root' and remove /etc/kinit/autologin to require a login."
else
  rm -f /etc/kinit/autologin
fi
echo "KwickOS Desktop $(cut -d' ' -f2 /etc/kwick-release)" > /etc/kwick-edition
command -v flatpak >/dev/null && flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
nohup setsid sh -c 'for i in $(seq 1 600); do flock -n /var/lib/dpkg/lock-frontend true 2>/dev/null && break; sleep 1; done; /usr/sbin/kwick-gpu install >/var/log/kwick-gpu.log 2>&1; /usr/bin/kwick-gaming install overlay >/var/log/kwick-gaming.log 2>&1' >/dev/null 2>&1 &
if [ -n "${2:-}" ]; then
  echo "KwickOS Desktop updated from $2. Restart to use the new desktop."
elif [ $ADOPT = 1 ]; then
  echo "KwickOS Desktop: the desktop already on this system is now the kwick-desktop package and gets updates with the rest of the system. Restart to use the new desktop."
else
  echo "KwickOS Desktop installed. Reboot to start the desktop (kernel: generic flavor via kwick-kernel-install)."
fi
EOF
deb_script "$P" prerm <<'EOF'
#!/bin/sh
set -e
[ "$1" = remove ] || exit 0
/usr/lib/kwick/desktop-units disable
EOF
deb_script "$P" postrm <<'EOF'
#!/bin/sh
set -e
case "$1" in remove|purge) ;; *) exit 0 ;; esac
W=/etc/systemd/system/multi-user.target.wants
rm -f /etc/systemd/system/display-manager.service /etc/kinit/no-getty /etc/kwick-edition
if [ -f /etc/network/interfaces.kwick-headless ] && ! grep -E '^[[:space:]]*iface[[:space:]]' /etc/network/interfaces 2>/dev/null | grep -qvE '^[[:space:]]*iface[[:space:]]+lo[[:space:]]'; then
  mv /etc/network/interfaces.kwick-headless /etc/network/interfaces
fi
if [ -f /usr/lib/systemd/system/networking.service ]; then
  mkdir -p $W
  ln -sf /usr/lib/systemd/system/networking.service $W/networking.service
fi
EOF
deb_build "$P" kwick-desktop "$VER" "$ARCH" "($ARCH)"