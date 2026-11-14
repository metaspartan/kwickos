#!/bin/sh
sync
if [ "$(id -u)" = 0 ]; then reboot; exit; fi
sudo -n reboot 2>/dev/null && exit 0
systemctl reboot 2>/dev/null && exit 0
loginctl reboot 2>/dev/null && exit 0
qdbus6 org.kde.Shutdown /Shutdown logoutAndReboot 2>/dev/null
