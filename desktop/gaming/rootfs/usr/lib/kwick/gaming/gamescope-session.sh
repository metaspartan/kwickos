gamescope_session_arch() { echo x86; }
gamescope_session_desc() { echo "Steam Game Mode session (Gamescope and Big Picture) on the login screen, with optional boot to Game Mode"; }

gamescope_available() {
  command -v gamescope >/dev/null 2>&1 || fp_have com.valvesoftware.Steam.Utility.gamescope
}

gamescope_session_state() {
  if [ -e "$SESSION_FILE" ] && gamescope_available; then echo yes
  elif [ -e "$SESSION_FILE" ] || gamescope_available; then echo part
  else echo no
  fi
}

gamescope_session_install() {
  if [ "$(steam_state)" != yes ]; then steam_install || return 1; fi
  if ! gamescope_available; then
    if apt_have_candidate gamescope; then
      apt_get gamescope || return 1
    else
      warn "Debian 13 has no gamescope package, using the Flathub Steam gamescope extension"
      fp_have com.valvesoftware.Steam || fp_install com.valvesoftware.Steam || return 1
      fp_install com.valvesoftware.Steam.Utility.gamescope || return 1
    fi
  fi
  put "$SESSION_FILE" <<EOF
[Desktop Entry]
Name=Steam Game Mode
Comment=Steam Big Picture in Gamescope, like a Steam Deck
Exec=/usr/bin/kwick-gamescope-session
Type=Application
DesktopNames=gamescope
EOF
  u=$(target_user)
  put /etc/sudoers.d/kwick-gamemode <<EOF
$u ALL=(root) NOPASSWD: /usr/bin/kwick-gaming session-select desktop, /usr/bin/kwick-gaming session-select game
EOF
  chmod 440 /etc/sudoers.d/kwick-gamemode
  if command -v visudo >/dev/null 2>&1 && ! visudo -cf /etc/sudoers.d/kwick-gamemode >/dev/null 2>&1; then
    rm -f /etc/sudoers.d/kwick-gamemode
    warn "sudoers entry for Switch to Desktop was invalid and was removed"
  fi
  say "Pick 'Steam Game Mode' on the login screen, or run: kwick-gaming session boot-on"
  return 0
}

gamescope_session_remove() {
  session_boot_off
  rm -f "$SESSION_FILE" /etc/sudoers.d/kwick-gamemode
  apt_remove gamescope
  fp_remove com.valvesoftware.Steam.Utility.gamescope
  return 0
}
