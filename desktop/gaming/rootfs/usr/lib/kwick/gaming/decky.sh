decky_arch() { echo x86; }
decky_desc() { echo "Decky Loader: plugins and themes for Steam Game Mode (pinned release)"; }

decky_user() { cat "$STATE_DIR/decky-user" 2>/dev/null; }

decky_state() {
  if marked decky && [ -e /etc/systemd/system/plugin_loader.service ]; then echo yes; else echo no; fi
}

decky_install() {
  if [ "$(steam_state)" != yes ]; then steam_install || return 1; fi
  u=$(target_user)
  h=$(user_home "$u")
  t=$(mktemp -d /var/tmp/kwick-gaming.XXXXXX)
  fetch_verify "$DECKY_URL" "$DECKY_SHA256" "$t/PluginLoader" || { rm -rf "$t"; return 1; }
  mkdir -p "$h/homebrew/services" "$h/homebrew/plugins" "$h/homebrew/settings" "$h/homebrew/data" "$h/homebrew/themes" "$h/homebrew/logs"
  svc_disable plugin_loader.service
  install -m 755 "$t/PluginLoader" "$h/homebrew/services/PluginLoader"
  rm -rf "$t"
  echo "$DECKY_VERSION" > "$h/homebrew/services/.loader.version"
  chown -R "$u:" "$h/homebrew"
  for d in "$h/.steam/steam" "$h/.var/app/com.valvesoftware.Steam/data/Steam"; do
    mkdir -p "$d" && : > "$d/.cef-enable-remote-debugging" && chown "$u:" "$d/.cef-enable-remote-debugging"
  done
  put /etc/systemd/system/plugin_loader.service <<EOF
[Unit]
Description=Decky Loader for Steam
After=network.target

[Service]
Type=simple
User=root
Restart=always
ExecStart=$h/homebrew/services/PluginLoader
WorkingDirectory=$h/homebrew/services
KillSignal=SIGKILL
Environment=UNPRIVILEGED_PATH=$h/homebrew
Environment=PRIVILEGED_PATH=$h/homebrew
Environment=LOG_LEVEL=INFO

[Install]
WantedBy=multi-user.target
EOF
  mark decky
  echo "$u" > "$STATE_DIR/decky-user"
  svc_enable plugin_loader.service
  say "Restart Steam (or Game Mode); the plug icon appears in the quick access menu."
  return 0
}

decky_remove() {
  u=$(decky_user)
  svc_disable plugin_loader.service
  rm -f /etc/systemd/system/plugin_loader.service
  if [ -n "$u" ]; then
    h=$(user_home "$u")
    rm -rf "$h/homebrew/services"
    rm -f "$h/.steam/steam/.cef-enable-remote-debugging" "$h/.var/app/com.valvesoftware.Steam/data/Steam/.cef-enable-remote-debugging"
    say "Plugins and settings stay in $h/homebrew; delete that folder to remove them."
  fi
  unmark decky
  rm -f "$STATE_DIR/decky-user"
  return 0
}
