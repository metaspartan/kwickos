#!/bin/bash
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}; CACHE=${CACHE:-/cache}
. "$(cd "$(dirname "$0")" && pwd)/deb.sh"
. <(sed 's/\r$//' "$SRC/config/rpi-firmware.env")
VER="$RPI_FW_TAG-1"
P=$(mktemp -d); chmod 755 "$P"
L="$P/usr/lib/kwick/rpi-firmware"
mkdir -p "$P/DEBIAN" "$L" "$P/usr/sbin" "$P/usr/share/kwick/rpi" "$P/usr/share/doc/kwick-rpi-firmware" "$CACHE/rpi-firmware"
for e in $RPI_FW_FILES; do
  f=${e%%:*}; sum=${e#*:}
  c="$CACHE/rpi-firmware/$RPI_FW_COMMIT-$f"
  if [ ! -f "$c" ]; then
    curl -fsSL --retry 3 -o "$c.part" "$RPI_FW_URL/$RPI_FW_COMMIT/boot/$f"
    mv "$c.part" "$c"
  fi
  echo "$sum  $c" | sha256sum -c --quiet || { rm -f "$c"; echo "sha256 mismatch for $f"; exit 1; }
  install -m 644 "$c" "$L/$f"
done
cp "$L/LICENCE.broadcom" "$P/usr/share/doc/kwick-rpi-firmware/copyright"
echo "$RPI_FW_TAG $RPI_FW_COMMIT" > "$L/VERSION"
install -m 755 "$SRC/rpi/rootfs/usr/sbin/kwick-rpi-boot" "$P/usr/sbin/kwick-rpi-boot"
sed -i 's/\r$//' "$P/usr/sbin/kwick-rpi-boot"
for f in config.txt cmdline.txt; do sed 's/\r$//' "$SRC/rpi/boot/$f" > "$P/usr/share/kwick/rpi/$f"; done
deb_control "$P" kwick-rpi-firmware "$VER" arm64 non-free-firmware/kernel <<EOT
Description: Raspberry Pi 4 and 5 boot firmware and boot partition manager for KwickOS
 The Raspberry Pi 4 GPU firmware (start4.elf, fixup4.dat) from the raspberrypi/firmware
 release $RPI_FW_TAG, checksum-verified at build time, and kwick-rpi-boot, which keeps the
 FAT boot partition (/boot/firmware) in step with the installed kernel: kernel8.img, the
 bcm2711 and bcm2712 device trees and the overlays of linux-image-kwick-rpi. The Raspberry Pi 5
 boots from its EEPROM bootloader and only needs the kernel, device trees and config.txt.
EOT
deb_script "$P" postinst <<'PI'
#!/bin/sh
set -e
[ "$1" = configure ] || exit 0
if grep -qs raspberrypi /proc/device-tree/compatible; then
	/usr/sbin/kwick-rpi-boot firmware || echo "kwick-rpi-firmware: boot partition not updated (run kwick-rpi-boot firmware)"
fi
exit 0
PI
deb_build "$P" kwick-rpi-firmware "$VER" arm64
