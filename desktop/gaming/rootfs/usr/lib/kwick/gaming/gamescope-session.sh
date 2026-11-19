SESSION_DIR=/usr/share/wayland-sessions
GAME_SESSION=kwick-gamemode
DESK_SESSION=kwick-desktop-oneshot
SESSION_FILE=$SESSION_DIR/$GAME_SESSION.desktop
SDDM_DIR=/etc/sddm.conf.d
SWITCH_CONF=$SDDM_DIR/90-kwick-gamemode.conf
LEGACY_CONF=$SDDM_DIR/30-kwick-gamemode.conf
BOOT_FLAG=$STATE_DIR/boot-to-game-mode
QUICK_FLAG=$STATE_DIR/quick-switch
GM_USER_FILE=$STATE_DIR/gamemode-user
DESK_FILE=$STATE_DIR/desktop-session
GM_SUDOERS=/etc/sudoers.d/kwick-gamemode
RETURN_APP=/usr/share/applications/kwick-return-to-gamemode.desktop
NOTICE_APP=/etc/xdg/autostart/kwick-gamemode-notice.desktop
HUD_LEVELS="off fps compact full"

gamescope_session_arch() { echo x86; }
gamescope_session_desc() { echo "Gaming Mode: Steam's controller-first interface in Gamescope, on the login screen and as a boot target"; }

gamescope_bin() {
  command -v gamescope 2>/dev/null && return 0
  [ -x /usr/games/gamescope ] && echo /usr/games/gamescope
}

gamescope_available() {
  [ -n "$(gamescope_bin)" ] || fp_have com.valvesoftware.Steam.Utility.gamescope
}

gamescope_session_state() {
  if [ -e "$SESSION_FILE" ] && gamescope_available; then echo yes
  elif [ -e "$SESSION_FILE" ] || gamescope_available; then echo part
  else echo no
  fi
}

gamescope_install_binary() {
  gamescope_available && return 0
  backports_ready
  if apt_have_candidate gamescope; then
    apt_get_backports gamescope && return 0
  fi
  warn "no gamescope package from Debian 13 or trixie-backports, using the Flathub Steam gamescope extension"
  fp_have com.valvesoftware.Steam || fp_install com.valvesoftware.Steam || return 1
  fp_install com.valvesoftware.Steam.Utility.gamescope
}

desktop_entry() {
  put "$1" <<EOF
[Desktop Entry]
Type=Application
Name=$2
Comment=$3
Exec=$4
$5
EOF
}

gm_icon_path() { echo "$(user_home "$1")/Desktop/kwick-return-to-gamemode.desktop"; }

gamescope_session_install() {
  if [ "$(steam_state)" != yes ]; then steam_install || return 1; fi
  gamescope_install_binary || return 1
  session_sync
  u=$(target_user)
  icon=$(gm_icon_path "$u")
  if [ -d "$(dirname "$icon")" ]; then
    install -m 755 -o "$u" -g "$(id -gn "$u")" "$RETURN_APP" "$icon"
  fi
  say "Gaming Mode is on the login screen. Settings, Gaming can boot straight into it."
  return 0
}

session_sync() {
  [ -e "$STATE_DIR/boot-user" ] && mv -f "$STATE_DIR/boot-user" "$GM_USER_FILE"
  desktop_entry "$SESSION_FILE" "Gaming Mode" "Steam's controller-first interface in Gamescope, like a Steam Deck" /usr/bin/kwick-gamescope-session "DesktopNames=gamescope"
  desktop_entry "$SESSION_DIR/$DESK_SESSION.desktop" "Desktop" "The desktop, opened from Gaming Mode" "$LIBDIR/desktop-oneshot" "NoDisplay=true
Hidden=true"
  desktop_entry "$RETURN_APP" "Return to Gaming Mode" "Leave the desktop and start Steam in Gaming Mode" "steamos-session-select gamescope" "Icon=steam
Categories=Game;
NotShowIn=gamescope;"
  desktop_entry "$NOTICE_APP" "Gaming Mode notice" "Explains why the desktop opened instead of Gaming Mode" "kwick-gaming session notice" "NoDisplay=true
NotShowIn=gamescope;
X-KDE-autostart-phase=2"
  gm_sync
}

gamescope_session_remove() {
  rm -f "$BOOT_FLAG" "$QUICK_FLAG"
  gm_sync
  [ -r "$GM_USER_FILE" ] && rm -f "$(gm_icon_path "$(cat "$GM_USER_FILE")")"
  rm -f "$(gm_icon_path "$(target_user)")"
  rm -f "$SESSION_FILE" "$SESSION_DIR/$DESK_SESSION.desktop" "$RETURN_APP" "$NOTICE_APP" "$GM_USER_FILE" "$DESK_FILE"
  apt_remove gamescope
  fp_remove com.valvesoftware.Steam.Utility.gamescope
  return 0
}

flag() { if [ -e "$1" ]; then echo yes; else echo no; fi; }
gm_optin() { [ -e "$BOOT_FLAG" ] || [ -e "$QUICK_FLAG" ]; }
gm_user() { cat "$GM_USER_FILE" 2>/dev/null || target_user; }

gm_sudoers() {
  c=/usr/bin/kwick-gaming
  printf '%s ALL=(root) NOPASSWD: %s session-select game, %s session-select desktop, %s session-select desktop-persistent, %s session-select settle\n' "$1" "$c" "$c" "$c" "$c"
}

gm_sync() {
  if gm_optin; then
    gm_sudoers "$(gm_user)" | put "$GM_SUDOERS"
    chmod 440 "$GM_SUDOERS"
    if command -v visudo >/dev/null 2>&1 && ! visudo -cf "$GM_SUDOERS" >/dev/null 2>&1; then
      rm -f "$GM_SUDOERS"
      warn "the sudoers rule for switching sessions was invalid and was removed"
    fi
  else
    rm -f "$GM_SUDOERS"
  fi
  gm_settle
}

switch_conf() {
  rm -f "$LEGACY_CONF"
  put "$SWITCH_CONF" <<EOF
[Autologin]
User=$(gm_user)
Session=$1
Relogin=true
EOF
}

gm_settle() {
  if [ -e "$BOOT_FLAG" ]; then switch_conf "$GAME_SESSION"; else rm -f "$SWITCH_CONF" "$LEGACY_CONF"; fi
}

desktop_session() {
  s=""
  for f in "$SDDM_DIR"/*.conf; do
    case $f in "$SWITCH_CONF"|"$LEGACY_CONF") continue ;; esac
    v=$(sed -n 's/^Session=//p' "$f" 2>/dev/null | tail -n 1)
    [ -n "$v" ] && s=$v
  done
  s=${s##*/}
  s=${s%.desktop}
  case $s in ""|"$GAME_SESSION"|"$DESK_SESSION") s=plasma ;; esac
  echo "$s"
}

gm_require() {
  [ -e "$SESSION_FILE" ] || die "install Gaming Mode first: $PROG install gamescope-session"
  [ -d "$SDDM_DIR" ] || command -v sddm >/dev/null 2>&1 || die "switching without a password needs SDDM"
}

gm_enable() {
  gm_require
  mkdir -p "$STATE_DIR"
  gm_optin || target_user > "$GM_USER_FILE"
  : > "$1"
  gm_sync
}

gm_disable() {
  rm -f "$1"
  gm_optin || rm -f "$GM_USER_FILE"
  gm_sync
}

session_boot_on() { gm_enable "$BOOT_FLAG"; say "Gaming Mode starts at boot. Switch to Desktop in Steam's power menu opens the desktop."; }
session_boot_off() { gm_disable "$BOOT_FLAG"; say "The computer starts in the desktop."; }
session_quick_on() { gm_enable "$QUICK_FLAG"; say "Switching between Gaming Mode and the desktop skips the login screen."; }
session_quick_off() { gm_disable "$QUICK_FLAG"; say "Switching between Gaming Mode and the desktop goes through the login screen."; }

session_select() {
  is_root || die "session-select needs root"
  case ${1:-} in
    settle) gm_settle; return 0 ;;
    game|desktop|desktop-persistent) ;;
    *) die "session-select: game, desktop, desktop-persistent or settle" ;;
  esac
  gm_optin || return 0
  [ "${SUDO_USER:-$(gm_user)}" = "$(gm_user)" ] || return 0
  case $1 in
    game) switch_conf "$GAME_SESSION" ;;
    desktop-persistent) rm -f "$BOOT_FLAG"; : > "$QUICK_FLAG"; gm_sync; session_select desktop ;;
    desktop) desktop_session > "$DESK_FILE"; switch_conf "$DESK_SESSION" ;;
  esac
}

user_state() { echo "${XDG_STATE_HOME:-$HOME/.local/state}/kwick"; }
user_conf() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/kwick/gamescope.conf"; }

hud_level() {
  v=$(sed -n 's/^KWICK_GAMEMODE_HUD=//p' "$(user_conf)" 2>/dev/null | tail -n 1)
  echo "${v:-off}"
}

session_hud() {
  case " $HUD_LEVELS " in *" ${1:-} "*) ;; *) die "hud: one of $HUD_LEVELS" ;; esac
  f=$(user_conf)
  mkdir -p "$(dirname "$f")"
  touch "$f"
  sed -i '/^KWICK_GAMEMODE_HUD=/d' "$f"
  echo "KWICK_GAMEMODE_HUD=$1" >> "$f"
  say "Gaming Mode performance overlay: $1"
}

session_notice() {
  m=$(user_state)/gamemode-fallback
  [ -e "$m" ] || return 0
  rm -f "$m"
  msg="Steam or Gamescope stopped right after starting. Details: ~/.local/state/kwick/gamemode.log"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
      --method org.freedesktop.Notifications.Notify "Gaming Mode" 0 steam "Gaming Mode did not start" "$msg" "[]" "{'image-path': <'steam'>, 'desktop-entry': <'kwick-return-to-gamemode'>}" 0 >/dev/null 2>&1 && break
    sleep 2
  done
  say "$msg"
}

session_status() {
  printf 'boot|%s\n' "$(flag "$BOOT_FLAG")"
  printf 'quick|%s\n' "$(flag "$QUICK_FLAG")"
  printf 'hud|%s\n' "$(hud_level)"
  if command -v mangoapp >/dev/null 2>&1; then echo 'mangoapp|yes'; else echo 'mangoapp|no'; fi
  printf 'device|%s\n' "$(handheld_model)"
  printf 'desktop|%s\n' "$(desktop_session)"
}
