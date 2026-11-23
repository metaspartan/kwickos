#!/bin/bash
set -euo pipefail
OUT=${OUT:-/out}; POOL="$OUT/repo/pool/main"
JOBS=${JOBS:-$(nproc)}
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
cat > /etc/apt/sources.list.d/kwick-curl-src.sources <<'EOF'
Types: deb-src
URIs: http://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main

Types: deb-src
URIs: http://deb.debian.org/debian-security
Suites: trixie-security
Components: main
EOF
apt-get update -qq
apt-get install -y -qq --no-install-recommends dpkg-dev ca-certificates >/dev/null
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
cd "$W"
apt-get source -qq curl >/dev/null
cd curl-*/
apt-get build-dep -y -qq -P nocheck . >/dev/null
DEBVER=$(dpkg-parsechangelog -S Version)
VER="$DEBVER+kwick1"
sed -i -e 's|--with-gssapi=/usr|--without-gssapi|' \
       -e 's|--without-libssh --with-libssh2|--without-libssh --without-libssh2 --without-librtmp --disable-ldap --disable-ldaps|' debian/rules
grep -q -- '--without-gssapi' debian/rules && grep -q -- '--without-libssh2 --without-librtmp --disable-ldap --disable-ldaps' debian/rules || {
  echo "debian/rules of curl $DEBVER changed; update scripts/mkleancurlpkg.sh" >&2; exit 1; }
{
  printf 'curl (%s) stable; urgency=medium\n\n' "$VER"
  printf '  * KwickOS lean build of Debian %s: no LDAP, RTMP, GSSAPI/Kerberos or SCP/SFTP (libssh2).\n' "$DEBVER"
  printf '    Everything else is unchanged; the full build stays available from Debian.\n\n'
  printf ' -- KwickOS <dev@kwickos.org>  %s\n\n' "$(date -R -d "@${SOURCE_DATE_EPOCH:-$(date +%s)}")"
  cat debian/changelog
} > debian/changelog.new
mv debian/changelog.new debian/changelog
DEB_BUILD_OPTIONS="nocheck noautodbgsym parallel=$JOBS" DEB_BUILD_PROFILES=nocheck \
  nice -n 19 dpkg-buildpackage -b -uc -us >"$W/build.log" 2>&1 || { tail -50 "$W/build.log"; exit 1; }
cd "$W"
for lib in libcurl4t64 libcurl3t64-gnutls; do
  dep=$(dpkg-deb -f ${lib}_*.deb Depends)
  echo "$lib: $dep"
  if echo "$dep" | grep -Eq 'libldap|librtmp|libssh2|libgssapi|libkrb5'; then
    echo "$lib still depends on a dropped library" >&2; exit 1
  fi
done
mkdir -p "$POOL"
cp ./*.deb "$POOL/"
ls -1 ./*.deb
