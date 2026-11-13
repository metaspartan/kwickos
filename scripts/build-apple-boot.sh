#!/bin/bash
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}; BUILD=${BUILD:-/build}
. "$SRC/config/apple.env"
VER=$(tr -d '\r\n' < "$SRC/VERSION")
if [ "$(uname -m)" = aarch64 ]; then CROSS=; else CROSS=aarch64-linux-gnu-; fi
mkdir -p "$BUILD/src" "$OUT/repo/pool/main" "$OUT/arm64/apple"

bash "$SRC/scripts/fetch-pinned.sh" "$M1N1_REPO" "$M1N1_TAG" "$M1N1_COMMIT" "$BUILD/src/m1n1"
bash "$SRC/scripts/fetch-pinned.sh" "$UBOOT_REPO" "$UBOOT_TAG" "$UBOOT_COMMIT" "$BUILD/src/u-boot-asahi"
bash "$SRC/scripts/fetch-pinned.sh" "$SPEAKERSAFETYD_REPO" "$SPEAKERSAFETYD_TAG" "$SPEAKERSAFETYD_COMMIT" "$BUILD/src/speakersafetyd"

M1="$BUILD/src/m1n1"
make -C "$M1" -j"$(nproc)" ARCH="$CROSS" RELEASE=1 CHAINLOADING=1 BUILDSTD=1 > "$BUILD/m1n1.log" 2>&1 || { tail -40 "$BUILD/m1n1.log"; exit 1; }
cp "$M1/build/m1n1.bin" "$OUT/arm64/apple/m1n1.bin"

UB="$BUILD/src/u-boot-asahi"
make -C "$UB" CROSS_COMPILE="$CROSS" apple_m1_defconfig > "$BUILD/uboot.log" 2>&1
make -C "$UB" CROSS_COMPILE="$CROSS" -j"$(nproc)" >> "$BUILD/uboot.log" 2>&1 || { tail -40 "$BUILD/uboot.log"; exit 1; }
cp "$UB/u-boot-nodtb.bin" "$OUT/arm64/apple/u-boot-nodtb.bin"
ls -l "$OUT/arm64/apple"

P=$(mktemp -d)
mkdir -p "$P/DEBIAN" "$P/usr/lib/asahi-boot"
cp "$OUT/arm64/apple/m1n1.bin" "$OUT/arm64/apple/u-boot-nodtb.bin" "$P/usr/lib/asahi-boot/"
SIZE=$(du -sk "$P" | cut -f1)
cat > "$P/DEBIAN/control" <<EOT
Package: kwick-apple-boot
Version: $VER
Architecture: arm64
Maintainer: KwickOS Developers <dev@kwickos.org>
Section: admin
Priority: optional
Installed-Size: $SIZE
Provides: m1n1, u-boot-asahi
Description: m1n1 $M1N1_TAG and Asahi U-Boot $UBOOT_TAG boot payloads for Apple Silicon
 Built from the pinned upstream Asahi Linux sources. kwick-apple-boot combines them
 with the kernel device trees into m1n1/boot.bin on the EFI System Partition.
EOT
dpkg-deb --root-owner-group -Zxz -b "$P" "$OUT/repo/pool/main/kwick-apple-boot_${VER}_arm64.deb" >/dev/null
rm -rf "$P"

SS="$BUILD/src/speakersafetyd"
( cd "$SS" && CARGO_HOME="$BUILD/cargo" cargo build --release --locked ) > "$BUILD/speakersafetyd.log" 2>&1 || { tail -40 "$BUILD/speakersafetyd.log"; exit 1; }
P=$(mktemp -d)
mkdir -p "$P/DEBIAN" "$P/usr/bin" "$P/usr/share/speakersafetyd" "$P/usr/lib/udev/rules.d" "$P/usr/lib/systemd/system" "$P/var/lib/speakersafetyd/blackbox"
install -m 755 "$SS/target/release/speakersafetyd" "$P/usr/bin/speakersafetyd"
cp -r "$SS/conf/." "$P/usr/share/speakersafetyd/"
cp "$SS"/speakersafetyd.service "$P/usr/lib/systemd/system/" 2>/dev/null || true
cp "$SS"/95-speakersafetyd.rules "$P/usr/lib/udev/rules.d/" 2>/dev/null || true
SIZE=$(du -sk "$P" | cut -f1)
cat > "$P/DEBIAN/control" <<EOT
Package: speakersafetyd
Version: $SPEAKERSAFETYD_TAG-kwick1
Architecture: arm64
Maintainer: KwickOS Developers <dev@kwickos.org>
Section: sound
Priority: optional
Installed-Size: $SIZE
Depends: libasound2t64, libc6
Description: Speaker protection daemon for Apple Silicon Macs
 Limits speaker excursion and temperature on Apple Silicon laptops and desktops.
 Required before the internal speakers can be used at normal volume.
EOT
dpkg-deb --root-owner-group -Zxz -b "$P" "$OUT/repo/pool/main/speakersafetyd_${SPEAKERSAFETYD_TAG}-kwick1_arm64.deb" >/dev/null
rm -rf "$P"
echo "packaged kwick-apple-boot and speakersafetyd"
