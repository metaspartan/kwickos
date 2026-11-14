#!/bin/sh
tz=$(cat /etc/timezone 2>/dev/null)
[ -n "$tz" ] || tz=$(readlink /etc/localtime 2>/dev/null | sed -n 's|.*/zoneinfo/||p')
echo "timezone=$tz"
km=$(sed -n 's/^XKBLAYOUT="\{0,1\}\([^",]*\).*/\1/p' /etc/default/keyboard 2>/dev/null | head -n 1)
echo "keymap=$km"
echo "lang=${LANG:-}"
if [ -d /sys/firmware/efi ]; then echo firmware=uefi; else echo firmware=bios; fi
