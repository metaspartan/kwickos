overlay_arch() { echo any; }
overlay_desc() { echo "MangoHud, GameMode and vkBasalt (plus GOverlay) for in-game stats and performance"; }

overlay_state() { pkgs_state gamemode mangohud vkbasalt; }

overlay_install() {
  apt_get gamemode mangohud vkbasalt goverlay || return 1
  if is_x86 && dpkg --print-foreign-architectures 2>/dev/null | grep -qx i386; then
    apt_get libgamemode0:i386 libgamemodeauto0:i386 mangohud:i386
  fi
  say "Use 'gamemoderun %command%' or 'mangohud %command%' in Steam launch options."
  return 0
}

overlay_remove() {
  apt_remove goverlay vkbasalt mangohud gamemode
  return 0
}
