#!/bin/sh
{ for d in "${XDG_DATA_HOME:-$HOME/.local/share}/applications" /usr/local/share/applications /usr/share/applications; do
  for f in "$d"/*.desktop; do
    [ -e "$f" ] || continue
    awk -F= -v id="$(basename "$f")" '
      /^\[/ { s = ($0 == "[Desktop Entry]") }
      s && $1 == "Name" && !n { n = substr($0, 6) }
      s && $1 == "Icon" && !i { i = $2 }
      s && $1 == "NoDisplay" && $2 == "true" { h = 1 }
      s && $1 == "Hidden" && $2 == "true" { h = 1 }
      s && $1 == "Type" { t = $2 }
      END { if (!h && t == "Application" && n) print id "|" n "|" i }' "$f"
  done
done; } | awk -F'|' '!s[$1]++' | sort -t'|' -k2 -f
