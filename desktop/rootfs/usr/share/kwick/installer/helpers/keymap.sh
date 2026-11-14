#!/bin/sh
km=${1:-us}
base=$(printf '%s' "$km" | sed 's/[-:(_].*//')
variant=$(printf '%s' "$km" | sed -n 's/^[^:(]*[:(]\([^)]*\))\{0,1\}$/\1/p')
case $base in uk) base=gb ;; ''|*[!a-z]*) exit 0 ;; esac
case ${XDG_CURRENT_DESKTOP:-} in
  *KDE*)
    kwriteconfig6 --file kxkbrc --group Layout --key Use true
    kwriteconfig6 --file kxkbrc --group Layout --key LayoutList "$base"
    kwriteconfig6 --file kxkbrc --group Layout --key VariantList "$variant"
    dbus-send --session --type=signal /Layouts org.kde.keyboard.reloadConfig >/dev/null 2>&1 ;;
  *GNOME*)
    if [ -n "$variant" ]; then s="$base+$variant"; else s=$base; fi
    gsettings set org.gnome.desktop.input-sources sources "[('xkb', '$s')]" ;;
  *Hyprland*)
    hyprctl keyword input:kb_layout "$base" >/dev/null 2>&1
    hyprctl keyword input:kb_variant "$variant" >/dev/null 2>&1 ;;
esac
exit 0
