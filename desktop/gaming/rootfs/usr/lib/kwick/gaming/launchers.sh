launchers_arch() { echo any; }
launchers_desc() { echo "Lutris (Debian package), Heroic and Bottles (Flathub)"; }

launchers_state() {
  a=no; b=no; c=no
  pkg_installed lutris && a=yes
  fp_have com.heroicgameslauncher.hgl && b=yes
  fp_have com.usebottles.bottles && c=yes
  combine_state "$a" "$b" "$c"
}

launchers_install() {
  rc=0
  apt_get lutris || rc=1
  fp_install com.heroicgameslauncher.hgl com.usebottles.bottles || rc=1
  is_x86 || warn "Windows games need x86; on $ARCH these launchers only run native and emulator titles"
  return $rc
}

launchers_remove() {
  apt_remove lutris
  fp_remove com.heroicgameslauncher.hgl com.usebottles.bottles
  return 0
}
