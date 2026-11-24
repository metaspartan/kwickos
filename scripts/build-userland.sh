#!/bin/sh
set -eu
ARCH=${1:?arch}
BB_VER=${BB_VER:-1.38.0}
BB_SHA256=${BB_SHA256:-34f9ea6ff8636f2c9241153b9114eefa9e65674a45318ae1ef95bb5f31c53bb2}
SRC=/src
OUT=/out/$ARCH/userland
CACHE=/cache
mkdir -p "$OUT" "$CACHE" /tmp/bb

apk add --no-cache build-base linux-headers perl bzip2 sed >/dev/null

rm -rf "$OUT/apk-keys"; mkdir -p "$OUT/apk-keys"; cp /etc/apk/keys/*.pub "$OUT/apk-keys/"

CFLAGS="-Os -pipe -static -fno-asynchronous-unwind-tables -ffunction-sections -fdata-sections -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wall -Wextra -Wno-unused-parameter -Wno-sign-compare -Wno-format-truncation -Wno-stringop-truncation"
gcc $CFLAGS -Wl,--gc-sections -Wl,-z,relro,-z,now -s -o "$OUT/kinit" "$SRC/src/kinit/kinit.c"
rm -rf /tmp/bb/busybox-*
echo "kinit: $(stat -c %s "$OUT/kinit") bytes"

TB="$CACHE/busybox-$BB_VER.tar.bz2"
bbok() { printf '%s  %s
' "$BB_SHA256" "$1" | sha256sum -c - >/dev/null 2>&1; }
if ! bbok "$TB"; then
	rm -f "$TB"
	for try in 1 2 3; do
		for u in "https://busybox.net/downloads/busybox-$BB_VER.tar.bz2" "https://sources.buildroot.net/busybox/busybox-$BB_VER.tar.bz2" "https://distfiles.alpinelinux.org/distfiles/edge/busybox-$BB_VER.tar.bz2"; do
			rm -f "$TB.part"
			wget -q -T 60 -O "$TB.part" "$u" && bbok "$TB.part" && break 2
		done
		sleep $((try * 30))
	done
	bbok "$TB.part" || { rm -f "$TB.part"; echo "busybox-$BB_VER.tar.bz2: no mirror served a file with the pinned checksum" >&2; exit 1; }
	mv "$TB.part" "$TB"
fi
cd /tmp/bb
tar xjf "$TB"
cd "busybox-$BB_VER"
sh "$SRC/config/busybox/patches.sh" "$PWD"
sed 's/\r$//' "$SRC/config/busybox/busybox.config" > .config
make olddefconfig >/dev/null 2>&1 || yes "" | make oldconfig >/dev/null
make -j"$(nproc)" busybox >/tmp/bb/build.log 2>&1 || { tail -50 /tmp/bb/build.log; exit 1; }
strip busybox
cp busybox "$OUT/busybox"
./busybox --list-full > "$OUT/busybox.links"
echo "busybox: $(stat -c %s "$OUT/busybox") bytes, $(wc -l < "$OUT/busybox.links") applets"
