proton_arch() { echo x86; }
proton_desc() { echo "ProtonUp-Qt and the pinned GE-Proton build for Steam"; }

proton_ge_present() { ls -d "$COMPAT_DIR"/GE-Proton* >/dev/null 2>&1; }

proton_state() {
  a=no; b=no
  fp_have net.davidotek.pupgui2 && a=yes
  proton_ge_present && b=yes
  combine_state "$a" "$b"
}

proton_install() {
  fp_install net.davidotek.pupgui2 || warn "ProtonUp-Qt could not be installed from Flathub"
  if [ ! -d "$COMPAT_DIR/$GE_PROTON_TAG" ]; then
    say "Fetching $GE_PROTON_TAG (about 500 MB)"
    t=$(mktemp -d /var/tmp/kwick-gaming.XXXXXX)
    fetch_verify "$GE_PROTON_URL" "$GE_PROTON_SHA256" "$t/ge.tar.gz" || { rm -rf "$t"; return 1; }
    mkdir -p "$COMPAT_DIR"
    tar -xzf "$t/ge.tar.gz" -C "$COMPAT_DIR" || { rm -rf "$t"; return 1; }
    rm -rf "$t"
  fi
  u=$(target_user)
  fh=$(user_home "$u")/.var/app/com.valvesoftware.Steam
  if [ -d "$fh" ]; then
    mkdir -p "$fh/data/Steam/compatibilitytools.d"
    cp -a "$COMPAT_DIR/$GE_PROTON_TAG" "$fh/data/Steam/compatibilitytools.d/"
    chown -R "$u:" "$fh/data/Steam/compatibilitytools.d"
  fi
  say "Restart Steam, then pick $GE_PROTON_TAG under Settings, Compatibility."
  return 0
}

proton_remove() {
  rm -rf "$COMPAT_DIR"/GE-Proton*
  fp_remove net.davidotek.pupgui2
  return 0
}
