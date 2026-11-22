#!/bin/sh
. /etc/os-release 2>/dev/null
echo "name=${NAME:-KwickOS}"
echo "version=${VERSION:-${VERSION_ID:-}}"
echo "codename=${VERSION_CODENAME:-}"
echo "host=$(cat /proc/sys/kernel/hostname 2>/dev/null)"
echo "kernel=$(uname -r)"
echo "arch=$(uname -m)"
cpu=$(sed -n 's/^model name[[:space:]]*: *//p' /proc/cpuinfo | head -n 1)
[ -n "$cpu" ] || cpu=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null)
echo "cpu=$cpu"
echo "cores=$(grep -c '^processor' /proc/cpuinfo)"
echo "memory=$(awk '/^MemTotal/ {printf "%.0f", $2 / 1048576}' /proc/meminfo)"
gpu=$(LC_ALL=C lspci 2>/dev/null | sed -n 's/.*\(VGA compatible controller\|3D controller\|Display controller\): //p' | head -n 1)
[ -n "$gpu" ] || gpu=$(cat /sys/class/drm/card*/device/uevent 2>/dev/null | sed -n 's/^DRIVER=//p' | head -n 1)
echo "gpu=$gpu"
echo "display=$(cat /sys/class/drm/card*-*/modes 2>/dev/null | head -n 1 | sed 's/x/ × /')"
echo "plasma=$(plasmashell --version 2>/dev/null | sed -n 's/^plasmashell //p')"
echo "disk=$(df -H --output=avail,size / 2>/dev/null | awk 'NR == 2 { for (i = 1; i <= 2; i++) { sub(/T$/, " TB", $i); sub(/G$/, " GB", $i); sub(/M$/, " MB", $i) } print $1 " available of " $2 }')"
