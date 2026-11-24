#!/bin/sh
SRC=${SRC:-$(cd "$(dirname "$0")/.." && pwd)}
L=$SRC/desktop/rootfs/usr/bin/kwick-layout
fail=0
ok() { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }
body() { sed -n "/^$1() {\$/,/^}\$/p" "$L"; }

body files | grep -q 'dolphin_reload' && bad "files() reopens Dolphin while KWin is still switching decorations" || ok "files() only marks Dolphin for a reload"
k=$(body kde)
w=$(printf '%s\n' "$k" | grep -n 'kwin_deco_wait "\$LIB" "\$DECO"' | cut -d: -f1)
r=$(printf '%s\n' "$k" | grep -n 'dolphin_reload' | cut -d: -f1)
c=$(printf '%s\n' "$k" | grep -n 'org.kde.KWin /KWin reconfigure' | cut -d: -f1)
[ -n "$w" ] && [ -n "$r" ] && [ -n "$c" ] && [ "$c" -lt "$w" ] && [ "$w" -lt "$r" ] \
  && ok "the layout switch waits for KWin's new decoration before Dolphin windows are reopened" || bad "order of reconfigure ($c), kwin_deco_wait ($w) and dolphin_reload ($r) in kde()"

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cat > "$T/qdbus6" <<'EOF'
#!/bin/sh
n=$(cat "$QD_STATE" 2>/dev/null || echo 0); echo $((n + 1)) > "$QD_STATE"
if [ "$n" -lt 2 ]; then printf 'Decoration\n==========\nPlugin: org.kde.breeze\nTheme: \n\n'; else printf 'Decoration\n==========\nPlugin: org.kde.kwin.aurorae\nTheme: __aurorae__svg__KwickGlass\n\n'; fi
EOF
chmod 755 "$T/qdbus6"
body kwin_deco_wait > "$T/f.sh"
printf '%s\n' 'kwin_deco_wait org.kde.kwin.aurorae __aurorae__svg__KwickGlass && echo applied' >> "$T/f.sh"
out=$(PATH="$T:$PATH" QD_STATE=$T/n sh "$T/f.sh")
[ "$out" = applied ] && [ "$(cat "$T/n")" = 3 ] && ok "kwin_deco_wait polls until KWin reports the new plugin and theme" || bad "kwin_deco_wait: '$out' after $(cat "$T/n") polls"
exit $fail
