#!/bin/sh
[ "$(id -u)" = 0 ] || { echo "run as root in a throwaway container (it writes /usr/local/bin)"; exit 2; }
SRC=${SRC:-$(cd "$(dirname "$0")/.." && pwd)}
R=$SRC/desktop/rootfs
W=$(mktemp -d)
trap 'rm -rf "$W" /usr/local/bin/flatpak' EXIT
fail=0
ok() { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }

B=$W/bin; mkdir -p "$B"
cat > "$B/kwick-layout" <<'EOF'
#!/bin/sh
echo "kwick-layout $*" >> "$LOG"
case $* in "") echo macos ;; appearance) cat "$HOME/appearance" 2>/dev/null || echo dark ;; accent) echo orange ;; "appearance "*) echo "$2" > "$HOME/appearance" ;; esac
EOF
cat > "$B/kwick-keys" <<'EOF'
#!/bin/sh
echo "kwick-keys $*" >> "$LOG"
EOF
cat > "$B/xdg-user-dir" <<'EOF'
#!/bin/sh
case $1 in DOCUMENTS) echo "$HOME/Documents" ;; MUSIC) echo "$HOME/Music" ;; PICTURES) echo "$HOME/Pictures" ;; VIDEOS) echo "$HOME/Videos" ;; DOWNLOAD) echo "$HOME/Down loads" ;; *) echo "$HOME" ;; esac
EOF
chmod 755 "$B"/*
H=$W/home; mkdir -p "$H/Documents" "$H/Music" "$H/Pictures" "$H/Videos" "$H/Down loads"
export HOME=$H LOG=$W/log XDG_CONFIG_HOME= XDG_DATA_HOME=
mkdir -p "$W/lib"; cp "$R/usr/lib/kwick/session-init" "$R/usr/lib/kwick/user-dirs" "$R/usr/lib/kwick/appearance-watch" "$W/lib/"
sed -i "s|/usr/lib/kwick/user-dirs|$W/lib/user-dirs|" "$W/lib/session-init"
chmod 755 "$W/lib"/*

PATH=$B:$PATH sh "$W/lib/session-init" gnome
grep -q '^kwick-layout macos$' "$LOG" && ok "a first login applies the layout" || bad "the first login did not run kwick-layout"
grep -q '^kwick-keys apply --session gnome --if-needed --quiet$' "$LOG" && ok "GNOME logins make sure the shortcuts are applied" || bad "kwick-keys --if-needed was not run for GNOME"
[ -f "$H/.local/share/gnome-shell/lock-warning-shown" ] && ok "the GNOME 'Screen Lock disabled' notice is marked as shown" || bad "lock-warning-shown missing"
[ "$(stat -c %a "$H/.local/share/gnome-shell")" = 700 ] && ok "the gnome-shell data folder keeps mode 700" || bad "gnome-shell folder mode $(stat -c %a "$H/.local/share/gnome-shell")"
bm=$H/.config/gtk-3.0/bookmarks
[ "$(sed -n 1p "$bm")" = "file://$H/Documents" ] && [ "$(sed -n 5p "$bm")" = "file://$H/Down%20loads" ] && ok "Files bookmarks are seeded with quoted folder URIs" || bad "bookmarks: $(tr '\n' ' ' < "$bm" 2>/dev/null)"
: > "$LOG"
PATH=$B:$PATH sh "$W/lib/session-init" gnome
! grep -q '^kwick-layout macos$' "$LOG" && ok "later logins skip the layout" || bad "kwick-layout ran again with an unchanged state"
echo "file:///elsewhere" > "$bm"
PATH=$B:$PATH sh "$W/lib/user-dirs"
[ "$(cat "$bm")" = "file:///elsewhere" ] && ok "existing bookmarks are left alone" || bad "user-dirs overwrote bookmarks"
: > "$LOG"
PATH=$B:$PATH sh "$W/lib/session-init" kde
! grep -q 'kwick-keys' "$LOG" && ok "KDE leaves the shortcuts to the autostart that runs after KWin" || bad "session-init ran kwick-keys in the KDE env stage"
grep -q '^Exec=kwick-keys apply --session kde --if-needed --quiet$' "$R/etc/xdg/autostart/kwick-keys.desktop" && grep -q '^OnlyShowIn=KDE;$' "$R/etc/xdg/autostart/kwick-keys.desktop" \
  && ok "KDE applies the shortcuts from an autostart entry" || bad "kwick-keys.desktop autostart is missing or wrong"
[ -f "$R/etc/skel/.local/share/gnome-shell/lock-warning-shown" ] && ok "new users never see the GNOME lock notice" || bad "skel marker missing"

cat > "$B/gsettings" <<'EOF'
#!/bin/sh
case $1 in
  monitor) printf "color-scheme: 'prefer-light'\ncolor-scheme: 'prefer-dark'\ncolor-scheme: 'prefer-light'\ncolor-scheme: 'prefer-dark'\n" ;;
  get) echo "'prefer-dark'" ;;
esac
EOF
chmod 755 "$B/gsettings"
echo dark > "$H/appearance"; : > "$LOG"
PATH=$B:$PATH timeout 10 sh "$W/lib/appearance-watch"
! grep -q 'appearance light' "$LOG" && ok "stale Dark Style events don't flip the appearance back and forth" || bad "appearance-watch acted on stale events: $(tr '\n' ' ' < "$LOG")"

cat > "$B/qml6" <<'EOF'
#!/bin/sh
echo "args=$* page=$KWICK_SETTINGS_PAGE"
EOF
chmod 755 "$B/qml6"
if [ ! -x /usr/lib/kwick/kwick-settings-app ]; then
  out=$(PATH=$B:$PATH sh "$R/usr/bin/kwick-settings" local-models)
  case $out in *"-- --page local-models page=local-models") ok "kwick-settings passes the page as an argument" ;; *) bad "launcher: $out" ;; esac
  out=$(KWICK_SETTINGS_PAGE=nearby PATH=$B:$PATH sh "$R/usr/bin/kwick-settings")
  case $out in *"--page nearby page=nearby") ok "KWICK_SETTINGS_PAGE=nearby is kept when no page is given" ;; *) bad "launcher dropped KWICK_SETTINGS_PAGE: $out" ;; esac
fi

cat > /usr/local/bin/flatpak <<EOF
#!/bin/sh
echo "flatpak \$*" >> "$LOG"
case \$1 in remotes) echo flathub ;; esac
EOF
chmod 755 /usr/local/bin/flatpak
: > "$LOG"
out=$(XDG_CACHE_HOME=$W/cache python3 -I "$R/usr/lib/kwick/store/backend" appstream --check)
case $out in *'"stale":["flathub"]'*) ok "the store notices a missing Flathub catalog" ;; *) bad "appstream --check: $out" ;; esac
! grep -q 'update' "$LOG" && ok "--check does not download" || bad "--check ran flatpak update"
XDG_CACHE_HOME=$W/cache python3 -I "$R/usr/lib/kwick/store/backend" appstream >/dev/null
grep -q '^flatpak update --appstream --noninteractive flathub$' "$LOG" && ok "first launch refreshes the Flathub catalog" || bad "no appstream refresh: $(tr '\n' ' ' < "$LOG")"

L=$R/usr/bin/kwick-layout
! grep -q '> "[^"]*\.new" && mv' "$L" && ok "kwick-layout writes no fixed .new temp files" || bad "kwick-layout still writes NAME.new then mv"
grep -q 'rm -f "$f/gtk.css.new"' "$L" && ok "stray gtk.css.new files from older versions are removed" || bad "no cleanup of gtk.css.new"
grep -q 'libsecret-tools' "$SRC/desktop/packages.list" && ok "the desktop installs libsecret-tools so agent keys go to the keystore" || bad "libsecret-tools missing from packages.list"
exit $fail
