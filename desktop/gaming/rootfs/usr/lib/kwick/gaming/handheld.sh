HHD_DIR=/opt/kwick-hhd

handheld_arch() { echo x86; }
handheld_desc() { echo "Handheld Daemon (HHD): controller, gyro, TDP and button support for Steam Deck-class handhelds"; }

handheld_state() {
  if [ -x "$HHD_DIR/bin/hhd" ] && [ -e /etc/systemd/system/hhd@.service ]; then echo yes
  elif [ -x "$HHD_DIR/bin/hhd" ]; then echo part
  else echo no
  fi
}

handheld_install() {
  apt_get python3 python3-venv python3-setuptools python3-wheel python3-evdev python3-yaml python3-rich python3-xlib python3-serial python3-pyroute2 python3-gi python3-dbus || return 1
  rm -rf "$HHD_DIR"
  python3 -m venv --system-site-packages "$HHD_DIR" || return 1
  t=$(mktemp -d /var/tmp/kwick-gaming.XXXXXX)
  echo "hhd==$HHD_VERSION --hash=sha256:$HHD_SHA256" > "$t/req.txt"
  "$HHD_DIR/bin/pip" install --no-deps --no-build-isolation --require-hashes -r "$t/req.txt" || { rm -rf "$t" "$HHD_DIR"; return 1; }
  rm -rf "$t"
  put /etc/udev/rules.d/83-kwick-hhd.rules <<'EOF'
KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", TAG+="uaccess", GROUP="input", MODE="0660"
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", GROUP="input", MODE="0660", TAG+="uaccess"
KERNEL=="event*", SUBSYSTEM=="input", GROUP="input", MODE="0660"
EOF
  put /etc/modules-load.d/kwick-gaming-handheld.conf <<'EOF'
uinput
EOF
  put /etc/systemd/system/hhd@.service <<EOF
[Unit]
Description=Handheld Daemon for %i
After=local-fs.target

[Service]
Type=simple
ExecStart=$HHD_DIR/bin/hhd --user %i
Nice=-12
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  load_modules uinput
  reload_udev
  u=$(target_user)
  svc_enable "hhd@$u.service"
  mark handheld
  say "Hardware seen by HHD: $(cat /sys/class/dmi/id/sys_vendor 2>/dev/null) $(cat /sys/class/dmi/id/product_name 2>/dev/null)"
  say "HHD settings live in ~/.config/hhd. Per-model kernel drivers (Ally, Legion Go, OneXPlayer, AYANEO) depend on the running kernel."
  return 0
}

handheld_remove() {
  for unit in /etc/systemd/system/multi-user.target.wants/hhd@*.service; do
    [ -e "$unit" ] && svc_disable "$(basename "$unit")"
  done
  rm -rf "$HHD_DIR" /etc/systemd/system/hhd@.service /etc/udev/rules.d/83-kwick-hhd.rules /etc/modules-load.d/kwick-gaming-handheld.conf
  unmark handheld
  reload_udev
  return 0
}
