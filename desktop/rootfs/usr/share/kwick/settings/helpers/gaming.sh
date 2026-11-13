#!/bin/sh
for id in com.valvesoftware.Steam net.davidotek.pupgui2 com.heroicgameslauncher.hgl net.lutris.Lutris; do
  if flatpak info "$id" >/dev/null 2>&1; then echo "$id|yes"; else echo "$id|no"; fi
done
