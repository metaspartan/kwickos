#!/bin/bash
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}
. "$(cd "$(dirname "$0")" && pwd)/deb.sh"
ARCH=arm64; FLAVOR=apple
K="$OUT/$ARCH/kernel-$FLAVOR"
KREL=$(cat "$K/version")
KVER=${KREL%-kwick}
VER=$(kwick_version)

P=$(mktemp -d)
mkdir -p "$P/DEBIAN" "$P/usr/lib/kwick/kernels/$KREL"
cp "$K/vmlinuz" "$K/config" "$P/usr/lib/kwick/kernels/$KREL/"
zstd -dc "$K/modules.tar.zst" | tar -C "$P/usr" -x
zstd -dc "$K/dtbs.tar.zst" | tar -C "$P/usr/lib/kwick/kernels/$KREL" -x
deb_control "$P" kwick-kernel-asahi "$KVER-1" arm64 kernel <<EOT
Depends: kwick-apple-boot, kmod
Provides: linux-image, linux-image-$KREL
Conflicts: linux-image-kwick-generic, linux-image-kwick-gb10
Description: Linux $KVER Asahi kernel for Apple Silicon Macs (16K pages)
 Built from the pinned AsahiLinux/linux tree with the KwickOS kinit root finder embedded.
 Includes the Apple SoC drivers built in for boot (NVMe, DART, SART, AIC, PCIe, USB) and
 the Asahi GPU, display, audio and Wi-Fi/Bluetooth drivers as modules.
EOT
deb_script "$P" postinst <<EOT
#!/bin/sh
set -e
if [ "\$1" = configure ] && [ -x /usr/sbin/kwick-apple-boot ]; then
	/usr/sbin/kwick-apple-boot install $KREL || true
fi
exit 0
EOT
deb_build "$P" kwick-kernel-asahi "$KVER-1" arm64

P=$(mktemp -d)
mkdir -p "$P/DEBIAN" "$P/usr/sbin" "$P/usr/lib/kwick" "$P/etc"
install -m 755 "$SRC/apple/rootfs/usr/sbin/kwick-apple-boot" "$P/usr/sbin/kwick-apple-boot"
install -m 755 "$SRC/apple/rootfs/usr/lib/kwick/gpu-apple" "$P/usr/lib/kwick/gpu-apple"
install -m 644 "$SRC/apple/rootfs/etc/m1n1.conf" "$P/etc/m1n1.conf"
install -m 755 "$SRC/apple/rootfs/usr/sbin/kwick-apple-grow-root" "$P/usr/sbin/kwick-apple-grow-root"
mkdir -p "$P/usr/lib/systemd/system" "$P/etc/systemd/system/multi-user.target.wants"
install -m 644 "$SRC/apple/rootfs/usr/lib/systemd/system/kwick-apple-grow-root.service" "$P/usr/lib/systemd/system/"
ln -s /usr/lib/systemd/system/kwick-apple-grow-root.service "$P/etc/systemd/system/multi-user.target.wants/kwick-apple-grow-root.service"
deb_control "$P" kwick-apple "$VER" arm64 metapackages <<EOT
Depends: kwick-kernel-asahi, kwick-apple-boot, asahi-fwextract, e2fsprogs, kwick-gpu
Recommends: speakersafetyd, pipewire, wireplumber, alsa-ucm-conf-asahi, asahi-audio
Description: Apple Silicon support for KwickOS
 The Asahi kernel, m1n1 + U-Boot boot chain tooling, vendor firmware extraction, and the
 GPU/audio helper used by kwick-gpu (Mesa with the asahi driver, asahi-audio, speakersafetyd).
EOT
echo /etc/m1n1.conf > "$P/DEBIAN/conffiles"
deb_script "$P" postinst <<EOT
#!/bin/sh
set -e
if [ "\$1" = configure ] && [ ! -e /etc/kwick-edition-apple ]; then
	echo kwick-apple > /etc/kwick-edition-apple
fi
exit 0
EOT
deb_build "$P" kwick-apple "$VER" arm64
