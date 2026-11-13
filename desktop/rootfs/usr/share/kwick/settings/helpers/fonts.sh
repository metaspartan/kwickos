#!/bin/sh
for l in macos windows linux; do
  names=$(kwick-fonts names "$l" 2>/dev/null) || continue
  u=$(printf '%s\n' "$names" | sed -n 1p)
  m=$(printf '%s\n' "$names" | sed -n 2p)
  fu=no; fm=no
  fc-list : family | grep -qiF "$u" && fu=yes
  fc-list : family | grep -qiF "$m" && fm=yes
  echo "$l|$u|$m|$fu|$fm"
done
