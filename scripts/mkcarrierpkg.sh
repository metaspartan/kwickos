#!/bin/bash
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}
PKG=${CARRIER:-zsh-autosuggestions}
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
grep -q '^VERSION_CODENAME=trixie$' /etc/os-release || { echo "mkcarrierpkg: run it in debian:trixie, it takes the package from Debian's archive" >&2; exit 1; }
apt-get update -qq
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
chown _apt "$W" 2>/dev/null || true
(cd "$W" && apt-get download -qq "$PKG")
DEB=$(ls "$W"/"$PKG"_*.deb)
DV=$(dpkg-deb -f "$DEB" Version)
[ "$(dpkg-deb -f "$DEB" Architecture)" = all ] || { echo "mkcarrierpkg: $PKG is not Architecture: all" >&2; exit 1; }
VER="$DV+kwick1"
dpkg-deb -R "$DEB" "$W/x"
C="$W/x/DEBIAN/control"
if grep -q '^Depends:' "$C"; then
  [ -z "$(sed -n '/^Depends:/{n;/^[ \t]/p}' "$C")" ] || { echo "mkcarrierpkg: multi-line Depends in $PKG" >&2; exit 1; }
  sed -i 's/^Depends: \(.*\)$/Depends: \1, kwick-update/' "$C"
else
  sed -i '/^Architecture:/a Depends: kwick-update' "$C"
fi
sed -i "s/^Version: .*/Version: $VER/" "$C"
sed -i '/^Description:/i X-Kwick-Carrier: Debian'"'"'s package unchanged plus a dependency on kwick-update, so desktops installed from images before 0.7.1, which have no other KwickOS package registered, receive KwickOS updates' "$C"
grep -q "^Version: $VER$" "$C" && grep -q '^Depends: .*kwick-update' "$C"
mkdir -p "$OUT/repo/pool/main"
dpkg-deb --root-owner-group -Zxz -b "$W/x" "$OUT/repo/pool/main/${PKG}_${VER}_all.deb" >/dev/null
echo "packaged $PKG $VER (Debian $DV + Depends: kwick-update)"
