#!/bin/bash
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}
. "$(cd "$(dirname "$0")" && pwd)/deb.sh"
VER=$(kwick_version)
join() { local IFS=,; echo "$*" | sed 's/,/, /g'; }
ESS_DEPENDS=(
  kwick-update ca-certificates curl wget jq sudo
  bind9-dnsutils net-tools iproute2 iputils-ping traceroute openssh-client rsync
  git less nano vim-tiny htop
  unzip zip zstd xz-utils bzip2
  file lsof procps psmisc tree
  bash-completion man-db tzdata locales gnupg apt-transport-https
)
ESS_RECOMMENDS=(
  build-essential pkg-config python3 python3-venv tmux ncdu
  mtr-tiny nmap iperf3 ethtool pciutils usbutils
  e2fsprogs dosfstools parted smartmontools
)
DEV_DEPENDS=(
  build-essential pkg-config cmake ninja-build gdb clang
  golang rustc cargo nodejs npm python3 python3-dev python3-venv
)
pack() {
  local name=$1 size=$2 dep=$3 rec=$4 desc=$5
  local P; P=$(mktemp -d); mkdir -p "$P/DEBIAN" "$P/usr/share/doc/$name"
  {
    echo "Depends: $dep"
    [ -z "$rec" ] || echo "Recommends: $rec"
    printf '%s\n' "$desc"
  } | deb_control "$P" "$name" "$VER" all metapackages "$size"
  printf '%s\n' "$name is a metapackage: it ships no files, only dependencies." > "$P/usr/share/doc/$name/README"
  find "$P" -type d -exec chmod 755 {} +
  find "$P" -type f -exec chmod 644 {} +
  deb_build "$P" "$name" "$VER" all
}
pack kwick-essentials 12 "$(join "${ESS_DEPENDS[@]}")" "$(join "${ESS_RECOMMENDS[@]}")" "Description: KwickOS everyday command-line essentials
 The tools most people expect on a Linux box, one package away: curl, wget,
 jq, sudo, DNS and network utilities (dig, ip, ping, traceroute, ifconfig),
 ssh, rsync, git, editors, archivers, process tools, man pages, locales and
 gnupg. Recommends add build-essential, python3, tmux, nmap, iperf3, mtr and
 disk tools. KwickOS does not install Recommends by default, so use
 'apt install --install-recommends kwick-essentials' for the full set.
 Not preinstalled; install it with 'apt install kwick-essentials'."
pack kwick-essentials-dev 12 "$(join "${DEV_DEPENDS[@]}")" "" "Description: KwickOS developer toolchain
 build-essential, pkg-config, cmake, ninja, gdb, clang, Go, Rust (rustc and
 cargo), Node.js with npm, and Python headers with venv support. Large;
 install it with 'apt install kwick-essentials-dev' when you need to compile."
