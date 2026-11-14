controllers_arch() { echo any; }
controllers_desc() { echo "Controller udev rules (Steam Input, uinput), joystick tools and Bluetooth pairing for gamepads"; }

controllers_state() {
  a=$(pkgs_state steam-devices joystick)
  b=no
  [ -e /etc/udev/rules.d/70-kwick-gaming-input.rules ] && b=yes
  combine_state "$a" "$b"
}

controllers_install() {
  apt_get steam-devices game-devices-udev joystick jstest-gtk || return 1
  put /etc/udev/rules.d/70-kwick-gaming-input.rules <<'EOF'
KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", TAG+="uaccess", GROUP="input", MODE="0660"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", TAG+="uaccess"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="057e", TAG+="uaccess"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="045e", TAG+="uaccess"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", TAG+="uaccess"
EOF
  put /etc/modules-load.d/kwick-gaming-controllers.conf <<'EOF'
uinput
hid_playstation
hid_nintendo
hid_steam
xpad
EOF
  load_modules uinput hid_playstation hid_nintendo hid_steam xpad
  if [ -f /etc/bluetooth/input.conf ]; then
    sed -i 's/^#\?ClassicBondedOnly=.*/ClassicBondedOnly=false/' /etc/bluetooth/input.conf
  fi
  reload_udev
  say "Kernel drivers xpad, hid-playstation, hid-nintendo and hid-steam cover Xbox, PlayStation, Switch and Steam controllers."
  say "xone and xpadneo are not packaged in Debian 13, so the Xbox wireless dongle and full Xbox Bluetooth rumble are not provided."
  return 0
}

controllers_remove() {
  rm -f /etc/udev/rules.d/70-kwick-gaming-input.rules /etc/modules-load.d/kwick-gaming-controllers.conf
  if [ -f /etc/bluetooth/input.conf ]; then
    sed -i 's/^ClassicBondedOnly=false/#ClassicBondedOnly=true/' /etc/bluetooth/input.conf
  fi
  apt_remove jstest-gtk joystick steam-devices
  reload_udev
  return 0
}
