#!/bin/bash
set -euo pipefail
ARCH=${1:?arch}
SRC=${SRC:-/src}; OUT=${OUT:-/out}; BUILD=${BUILD:-/build}
VERSION=$(sed 's/\r$//' "$SRC/VERSION" 2>/dev/null || echo 0.1.0)
U="$OUT/$ARCH/userland"
R="$BUILD/rootfs-$ARCH"
for b in busybox kinit kpkg busybox.links; do [ -e "$U/$b" ] || { echo "missing $U/$b"; exit 1; }; done
rm -rf "$R"; mkdir -p "$R"; cd "$R"

mkdir -p usr/bin usr/sbin usr/lib usr/share/kwick usr/share/keyrings usr/local/bin usr/local/sbin usr/local/lib usr/local/share \
  etc/apt/apt.conf.d etc/apt/preferences.d etc/apt/trusted.gpg.d etc/apt/sources.list.d etc/ld.so.conf.d \
  etc/profile.d etc/kinit etc/systemd/system/multi-user.target.wants etc/network/if-up.d etc/network/if-down.d \
  etc/network/if-pre-up.d etc/network/if-post-down.d etc/sysctl.d etc/sysusers.d etc/tmpfiles.d etc/default etc/opt \
  var/lib/dpkg/info var/lib/dpkg/updates var/lib/dpkg/alternatives var/lib/dpkg/triggers var/lib/apt/lists/partial \
  var/cache/apt/archives/partial var/log var/tmp var/spool/cron/crontabs var/mail var/lib/misc var/local var/opt var/backups \
  root home tmp run proc sys dev mnt media opt srv boot
ln -s usr/bin bin; ln -s usr/sbin sbin; ln -s usr/lib lib
if [ "$ARCH" = amd64 ]; then mkdir -p usr/lib64; ln -s usr/lib64 lib64; fi
ln -s /run var/run; ln -s /run/lock var/lock
chmod 1777 tmp var/tmp; chmod 700 root

install -m 0755 "$U/busybox" usr/bin/busybox
: > usr/share/kwick/busybox.links
while IFS= read -r p; do
  p=${p#/}; [ -n "$p" ] || continue
  case "$p" in bin/*|sbin/*) p="usr/$p";; esac
  [ "$p" = usr/bin/busybox ] && continue
  [ -e "$p" ] || [ -L "$p" ] || ln -s /usr/bin/busybox "$p"
  echo "/$p" >> usr/share/kwick/busybox.links
done < <(sed 's/\r$//' "$U/busybox.links")

install -m 0755 "$U/kinit" usr/sbin/kinit
ln -s kinit usr/sbin/init
for l in poweroff reboot halt service invoke-rc.d update-rc.d; do ln -sf kinit usr/sbin/$l; done
for l in systemctl journalctl deb-systemd-helper deb-systemd-invoke systemd-sysusers systemd-tmpfiles; do ln -sf ../sbin/kinit usr/bin/$l; done

install -m 0755 "$U/kpkg" usr/bin/kpkg
for l in apt apt-get apt-cache apt-mark dpkg dpkg-query dpkg-deb dpkg-trigger dpkg-divert dpkg-maintscript-helper \
         dpkg-statoverride dpkg-architecture update-alternatives apk; do ln -sf kpkg usr/bin/$l; done

cp -r --no-preserve=mode,ownership,timestamps "$SRC/rootfs/." "$R/"
find "$R/etc" "$R/usr/lib/systemd" "$R/usr/share/udhcpc" "$R/usr/lib/kwick" -type f -exec sed -i 's/\r$//' {} +
chmod 0755 usr/share/udhcpc/default.script usr/lib/kwick/autologin usr/sbin/kwick-kernel-install usr/sbin/kwick-gpu usr/lib/kwick/bash-on-demand
rm -f usr/bin/bash && cp usr/lib/kwick/bash-on-demand usr/bin/bash && chmod 0755 usr/bin/bash

sed 's/\r$//' /usr/share/base-passwd/passwd.master > etc/passwd
sed 's/\r$//' /usr/share/base-passwd/group.master > etc/group
sed -i 's|^root:\(.*\):/bin/bash$|root:\1:/bin/sh|' etc/passwd
DAYS=$(( $(date +%s) / 86400 ))
awk -F: -v d="$DAYS" '{print $1":*:"d":0:99999:7:::"}' etc/passwd > etc/shadow
awk -F: '{print $1":*::"}' etc/group > etc/gshadow
chmod 0640 etc/shadow etc/gshadow; chgrp 42 etc/shadow etc/gshadow 2>/dev/null || true
grep -q '^shadow:' etc/group || echo 'shadow:x:42:' >> etc/group

echo kwick > etc/hostname
cat > etc/hosts <<'EOF'
127.0.0.1	localhost
127.0.1.1	kwick
::1		localhost ip6-localhost ip6-loopback
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters
EOF
mkdir -p usr/lib
cat > usr/lib/os-release <<EOF
PRETTY_NAME="KwickOS $VERSION"
NAME="KwickOS"
VERSION_ID="$VERSION"
VERSION="$VERSION (trixie-compatible)"
VERSION_CODENAME=trixie
ID=kwickos
ID_LIKE=debian
HOME_URL="https://github.com/metaspartan/kwickos"
SUPPORT_URL="https://github.com/metaspartan/kwickos/issues"
BUG_REPORT_URL="https://github.com/metaspartan/kwickos/issues"
EOF
ln -sf ../usr/lib/os-release etc/os-release
echo "KwickOS $VERSION" > etc/kwick-release
echo "13.0" > etc/debian_version
printf 'KwickOS %s \\n \\l\n\n' "$VERSION" > etc/issue
printf '/bin/sh\n/usr/bin/sh\n/bin/ash\n/bin/bash\n/usr/bin/bash\n' > etc/shells
printf '# <file system> <mount point> <type> <options> <dump> <pass>\n' > etc/fstab
printf 'include /etc/ld.so.conf.d/*.conf\n' > etc/ld.so.conf
: > etc/resolv.conf
ln -sf /proc/self/mounts etc/mtab
echo root > etc/kinit/autologin
cp /etc/apt/trusted.gpg.d/debian-archive-trixie-*.asc etc/apt/trusted.gpg.d/
KWICK_REPO_URL=${KWICK_REPO_URL:-http://metaspartan.github.io/kwickos}
KWICK_REPO_KEY=${KWICK_REPO_KEY:-$SRC/keys/kwickos-archive-keyring.asc}
if [ -n "$KWICK_REPO_URL" ] && [ -f "$KWICK_REPO_KEY" ]; then
  mkdir -p usr/share/keyrings
  cp "$KWICK_REPO_KEY" usr/share/keyrings/kwickos-archive-keyring.asc
  printf 'Types: deb\nURIs: %s\nSuites: stable\nComponents: main\nSigned-By: /usr/share/keyrings/kwickos-archive-keyring.asc\n' "$KWICK_REPO_URL" > etc/apt/sources.list.d/kwickos.sources
fi
ALPINE_BRANCH=${ALPINE_BRANCH:-v3.24}
case $ARCH in amd64) AARCH=x86_64;; arm64) AARCH=aarch64;; riscv64) AARCH=riscv64;; esac
mkdir -p etc/apk/keys usr/lib/apk/db var/cache/apk
cp "$U"/apk-keys/*.pub etc/apk/keys/ 2>/dev/null || echo "note: no Alpine keys for $ARCH"
echo "$AARCH" > etc/apk/arch
printf 'http://dl-cdn.alpinelinux.org/alpine/%s/main\nhttp://dl-cdn.alpinelinux.org/alpine/%s/community\n' "$ALPINE_BRANCH" "$ALPINE_BRANCH" > etc/apk/repositories
echo kwick-base > etc/apk/world
cat > usr/lib/apk/db/installed <<EOF
C:Q1AAAAAAAAAAAAAAAAAAAAAAAAAAA=
P:kwick-base
V:$VERSION-r0
A:$AARCH
S:0
I:0
T:KwickOS base system (virtual)
U:https://github.com/metaspartan/kwickos
L:MIT
o:kwick-base
t:1700000000
p:busybox=1.38.0-r0 busybox-binsh=1.38.0-r0 /bin/sh cmd:sh alpine-baselayout=3.7.2-r1 alpine-baselayout-data=3.7.2-r1 alpine-release=3.24.4-r0 alpine-keys=2.6-r0 apk-tools=3.0.9-r0 ssl_client=1.38.0-r0

EOF
for u in networking syslog; do ln -sf /usr/lib/systemd/system/$u.service etc/systemd/system/multi-user.target.wants/$u.service; done

PROVIDES="base-files (= 13.8), base-passwd (= 3.6.7), bash (= 5.2.37-2), bsdutils (= 1:2.41-5), coreutils (= 9.7-3), \
dash (= 0.5.12-12), debianutils (= 5.23.2), diffutils (= 1:3.10-4), dpkg (= $(grep -o 'dpkgCompatVersion = "[^"]*' $SRC/src/kpkg/main.go | cut -d'"' -f2)), \
findutils (= 4.10.0-3), grep (= 3.11-4), gzip (= 1.13-1), hostname (= 3.25), init-system-helpers (= 1.69~deb13u1), \
login (= 1:4.16.0-2+really2.41-5), mawk (= 1.3.4.20250131-1), awk, ncurses-bin (= 6.5+20250216-2), sed (= 4.9-2), \
sysvinit-utils (= 3.14-4), lsb-base (= 11.6), tar (= 1.35+dfsg-3.1), util-linux (= 2.41-5), mount (= 2.41-5), \
procps (= 2:4.0.4-9), usr-is-merged (= 39), usrmerge (= 39), apt (= 3.0.3), ifupdown (= 0.8.44), iproute2 (= 6.15.0-1), \
systemd-sysusers (= 257.9-1), systemd-tmpfiles (= 257.9-1), cron-daemon, logrotate-daemon-dummy, \
busybox (= 1:1.38.0-1), kinit, kpkg"
ISZ=$(du -sk --exclude=./var/lib/dpkg . | awk '{print $1}')
cat > var/lib/dpkg/status <<EOF
Package: kwick-base
Status: install ok installed
Priority: required
Section: admin
Installed-Size: $ISZ
Maintainer: KwickOS Developers <dev@kwickos.org>
Architecture: $ARCH
Version: $VERSION
Essential: yes
X-Kwick-Base: yes
Provides: $PROVIDES
Description: KwickOS base system
 BusyBox userland, the kinit init/service manager and the kpkg
 apt/dpkg-compatible package manager. Satisfies Debian's Essential
 package set so packages from the Debian archive install unmodified.

EOF
find . -mindepth 1 \( -path ./var/lib/dpkg -o -path ./proc -o -path ./sys -o -path ./dev -o -path ./run -o -path ./tmp \) -prune -o -print \
  | sed 's|^\.||' | sort > var/lib/dpkg/info/kwick-base.list
touch var/lib/dpkg/available var/lib/apt/extended_states

bad=$(find "$R" -xdev -perm -0002 ! -type l ! \( -type d -perm -1000 \) | sed "s|^$R||")
[ -z "$bad" ] || { echo "!! world-writable paths in rootfs:"; echo "$bad"; exit 1; }
bad=$(find "$R" -xdev \( -perm -4000 -o -perm -2000 \) -type f | sed "s|^$R||")
[ -z "$bad" ] || echo "note: setuid/setgid files: $bad"

mkdir -p "$OUT/$ARCH"
tar --numeric-owner --sort=name --mtime=@0 -C "$R" -cf - . | gzip -9n > "$OUT/$ARCH/kwickos-rootfs-$ARCH.tar.gz"
echo ">> rootfs $ARCH: $(du -sk "$R" | awk '{print $1}') KiB on disk, $(du -s --apparent-size -B1 "$R" | awk '{print $1}') bytes apparent, tar.gz $(stat -c %s "$OUT/$ARCH/kwickos-rootfs-$ARCH.tar.gz") bytes"
