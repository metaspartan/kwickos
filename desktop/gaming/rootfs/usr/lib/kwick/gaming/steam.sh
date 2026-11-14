steam_arch() { echo x86; }
steam_desc() { echo "Steam client with Proton, 32-bit graphics libraries and Steam Input udev rules"; }

steam_state() {
  if [ -x /usr/games/steam ] || fp_have com.valvesoftware.Steam; then echo yes; else echo no; fi
}

steam_install() {
  if command -v kwick-gpu >/dev/null 2>&1; then
    kwick-gpu steam
  else
    apt_get steam-installer steam-devices
  fi
  [ -x /usr/games/steam ] && return 0
  warn "native Steam could not be installed, using the Flathub build"
  fp_install com.valvesoftware.Steam || return 1
  flatpak override --system --device=all --filesystem=xdg-run/gamemode com.valvesoftware.Steam
  return 0
}

steam_remove() {
  apt_remove steam-installer
  fp_remove com.valvesoftware.Steam
  return 0
}
