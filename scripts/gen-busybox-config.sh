#!/bin/sh
# Regenerate config/busybox/busybox.config from upstream defconfig plus the
# KwickOS policy below.  Run inside an Alpine container with /src mounted.
set -eu
BB_VER=${BB_VER:-1.38.0}
apk add --no-cache build-base linux-headers perl bzip2 >/dev/null
mkdir -p /cache /tmp/g && cd /tmp/g
[ -f /cache/busybox-$BB_VER.tar.bz2 ] || wget -q -O /cache/busybox-$BB_VER.tar.bz2 https://busybox.net/downloads/busybox-$BB_VER.tar.bz2
tar xjf /cache/busybox-$BB_VER.tar.bz2 && cd busybox-$BB_VER
make defconfig >/dev/null
set_opt() { sed -i "/^CONFIG_$1=/d;/^# CONFIG_$1 is not set/d" .config; echo "CONFIG_$1=$2" >> .config; }
unset_opt() { sed -i "/^CONFIG_$1=/d;/^# CONFIG_$1 is not set/d" .config; echo "# CONFIG_$1 is not set" >> .config; }
set_opt STATIC y
unset_opt PIE
set_opt EXTRA_CFLAGS '"-Os -fno-asynchronous-unwind-tables"'
# kinit owns PID 1 and power management.
for o in INIT LINUXRC HALT FEATURE_INIT_SCTTY FEATURE_KILL_REMOVED RUNLEVEL; do unset_opt $o; done
# kpkg provides dpkg/apt; drop busybox's limited versions and rpm.
for o in DPKG DPKG_DEB RPM RPM2CPIO; do unset_opt $o; done
# tc does not build against modern kernel headers (CBQ removal).
unset_opt TC
# Old/unsafe or pointless on a server.
for o in TELNETD FTPD FTPGET FTPPUT TFTP TFTPD INETD RX LPD LPR LPQ SENDMAIL POPMAILDIR REFORMIME MAKEMIME \
         FBSET FBSPLASH CONSPY CHAT MICROCOM RUNSV RUNSVDIR SV SVC SVLOGD SVOK CHPST SETUIDGID ENVUIDGID ENVDIR SOFTLIMIT \
         LOADFONT SETFONT LOADKMAP DUMPKMAP KBD_MODE SHOWKEY SETKEYCODES OPENVT DEALLOCVT CHVT SETCONSOLE \
         NANDWRITE NANDDUMP UBIATTACH UBIDETACH UBIMKVOL UBIRMVOL UBIRSVOL UBIUPDATEVOL UBIRENAME FLASHCP FLASH_LOCK FLASH_UNLOCK FLASH_ERASEALL \
         HDPARM RAIDAUTORUN BOOTCHARTD MAKEDEVS DEVFSD SULOGIN ADD_SHELL REMOVE_SHELL; do unset_opt $o; done
# bash compatibility: /bin/bash -> ash for scripts that only need basic bashisms.
unset_opt BASH_IS_NONE
set_opt BASH_IS_ASH y
set_opt FEATURE_SH_IS_ASH y
set_opt FEATURE_BASH_IS_ASH y
make olddefconfig >/dev/null 2>&1 || yes "" | make oldconfig >/dev/null
mkdir -p /src/config/busybox
grep -v '^#.*Automatically generated\|^# Busybox version\|^# [A-Z][a-z]* [A-Z][a-z]* *[0-9]' .config > /src/config/busybox/busybox.config
echo "wrote busybox.config ($(grep -c '=y' .config) options enabled)"
