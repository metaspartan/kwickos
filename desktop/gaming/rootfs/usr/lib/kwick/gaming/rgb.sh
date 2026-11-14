rgb_arch() { echo any; }
rgb_desc() { echo "OpenRGB lighting control (Flathub) with udev rules and I2C access, plus libratbag and Piper for mice"; }

rgb_state() {
  a=no; b=no
  fp_have org.openrgb.OpenRGB && a=yes
  [ -e /etc/udev/rules.d/60-openrgb.rules ] && b=yes
  combine_state "$a" "$b"
}

rgb_install() {
  fp_install org.openrgb.OpenRGB || return 1
  fetch_verify_commit "$OPENRGB_RULES_URL" /etc/udev/rules.d/60-openrgb.rules || return 1
  put /etc/udev/rules.d/60-kwick-i2c.rules <<'EOF'
KERNEL=="i2c-[0-9]*", TAG+="uaccess"
EOF
  put /etc/modules-load.d/kwick-gaming-rgb.conf <<'EOF'
i2c-dev
EOF
  load_modules i2c-dev
  apt_get i2c-tools ratbagd piper
  reload_udev
  say "Re-plug your devices or reboot once so the new udev rules apply."
  return 0
}

rgb_remove() {
  fp_remove org.openrgb.OpenRGB
  rm -f /etc/udev/rules.d/60-openrgb.rules /etc/udev/rules.d/60-kwick-i2c.rules /etc/modules-load.d/kwick-gaming-rgb.conf
  apt_remove piper ratbagd
  reload_udev
  return 0
}
