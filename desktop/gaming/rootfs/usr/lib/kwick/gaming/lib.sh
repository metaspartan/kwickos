PROG=kwick-gaming
LIBDIR=/usr/lib/kwick/gaming
STATE_DIR=/var/lib/kwick-gaming
COMPAT_DIR=/usr/share/steam/compatibilitytools.d
APT_READY=""
. "$LIBDIR/pins.env"

say() { printf '%s\n' "$*"; }
warn() { printf '%s: %s\n' "$PROG" "$*" >&2; }
die() { warn "$*"; exit 1; }

host_arch() {
  a=$(dpkg --print-architecture 2>/dev/null)
  if [ -n "$a" ]; then echo "$a"; return 0; fi
  case $(uname -m) in
    x86_64) echo amd64 ;;
    aarch64) echo arm64 ;;
    riscv64) echo riscv64 ;;
    *) uname -m ;;
  esac
}
ARCH=$(host_arch)

is_x86() { [ "$ARCH" = amd64 ]; }
is_root() { [ "$(id -u)" -eq 0 ]; }

need_root() {
  is_root && return 0
  if [ -t 0 ] || ! command -v pkexec >/dev/null 2>&1; then exec sudo -E "$SELF" "$@"; fi
  exec pkexec "$SELF" "$@"
}

target_user() {
  u=${SUDO_USER:-}
  if [ -z "$u" ] && [ -n "${PKEXEC_UID:-}" ]; then u=$(getent passwd "$PKEXEC_UID" | cut -d: -f1); fi
  if [ -z "$u" ] || [ "$u" = root ]; then u=$(getent passwd 1000 | cut -d: -f1); fi
  [ -n "$u" ] || u=kwick
  echo "$u"
}

user_home() { getent passwd "$1" | cut -d: -f6; }

put() { mkdir -p "$(dirname "$1")" && cat > "$1"; }
mark() { mkdir -p "$STATE_DIR" && : > "$STATE_DIR/$1"; }
unmark() { rm -f "$STATE_DIR/$1"; }
marked() { [ -e "$STATE_DIR/$1" ]; }

pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }

pkgs_state() {
  total=$#
  have=$(dpkg-query -W -f='${Package} ${Status}\n' "$@" 2>/dev/null | awk '$NF == "installed" {print $1}' | sort -u | wc -l)
  if [ "$have" -eq "$total" ]; then echo yes; elif [ "$have" -gt 0 ]; then echo part; else echo no; fi
}

combine_state() {
  yes=0; no=0
  for s; do
    case $s in yes) yes=$((yes + 1)) ;; *) no=$((no + 1)) ;; esac
  done
  if [ "$no" -eq 0 ]; then echo yes; elif [ "$yes" -gt 0 ]; then echo part; else echo no; fi
}

apt_ready() {
  [ -n "$APT_READY" ] && return 0
  sed -i 's/^Components: main$/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources 2>/dev/null
  apt-get update -qq >/dev/null 2>&1
  APT_READY=1
  return 0
}

apt_have_candidate() {
  apt_ready
  c=$(apt-cache policy "$1" 2>/dev/null | sed -n 's/^ *Candidate: //p' | head -n 1)
  [ -n "$c" ] && [ "$c" != "(none)" ]
}

apt_get() {
  apt_ready
  list=""
  for p; do
    if apt_have_candidate "$p"; then list="$list $p"; else warn "Debian 13 has no package '$p', skipped"; fi
  done
  [ -n "$list" ] || return 0
  DEBIAN_FRONTEND=noninteractive apt-get install -y $list
}

apt_remove() {
  list=""
  for p; do
    if pkg_installed "$p"; then list="$list $p"; fi
  done
  [ -n "$list" ] || return 0
  if apt-get -s remove $list 2>/dev/null | grep -q '^Remv kwick-'; then
    warn "removing$list would also remove a kwick-* package, so they stay installed"
    return 0
  fi
  DEBIAN_FRONTEND=noninteractive apt-get remove -y $list
}

ensure_curl() {
  command -v curl >/dev/null 2>&1 && return 0
  apt_get curl ca-certificates
}

fetch_verify() {
  ensure_curl || return 1
  curl -fL --retry 3 -o "$3.part" "$1" || { rm -f "$3.part"; warn "download failed: $1"; return 1; }
  got=$(sha256sum "$3.part" | cut -d' ' -f1)
  if [ "$got" != "$2" ]; then
    warn "sha256 mismatch for $1 (got $got, want $2)"
    rm -f "$3.part"
    return 1
  fi
  mv "$3.part" "$3"
}

fetch_verify_commit() {
  ensure_curl || return 1
  mkdir -p "$(dirname "$2")"
  curl -fL --retry 3 -o "$2.part" "$1" || { rm -f "$2.part"; warn "download failed: $1"; return 1; }
  [ -s "$2.part" ] || { rm -f "$2.part"; warn "empty download: $1"; return 1; }
  mv "$2.part" "$2"
}

fp_have() { command -v flatpak >/dev/null 2>&1 && flatpak info "$1" >/dev/null 2>&1; }

fp_ready() {
  command -v flatpak >/dev/null 2>&1 || apt_get flatpak || return 1
  flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
}

fp_install() {
  fp_ready || return 1
  flatpak install --system -y --noninteractive flathub "$@"
}

fp_remove() {
  for a; do
    if fp_have "$a"; then flatpak uninstall -y --noninteractive "$a"; fi
  done
  return 0
}

reload_udev() {
  udevadm control --reload >/dev/null 2>&1
  udevadm trigger >/dev/null 2>&1
  return 0
}

load_modules() {
  for km; do modprobe "$km" 2>/dev/null; done
  return 0
}

sysctl_apply() {
  sysctl --system >/dev/null 2>&1
  return 0
}

svc_enable() {
  if command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload >/dev/null 2>&1 && systemctl enable --now "$@" >/dev/null 2>&1; then return 0; fi
  warn "could not start $* now, it starts on the next boot"
  return 0
}

svc_disable() {
  command -v systemctl >/dev/null 2>&1 || return 0
  systemctl disable --now "$@" >/dev/null 2>&1
  return 0
}

backports_ready() {
  grep -rqs 'trixie-backports' /etc/apt/sources.list.d /etc/apt/sources.list && return 0
  put /etc/apt/sources.list.d/kwick-backports.sources <<'SRC'
Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie-backports
Components: main contrib non-free non-free-firmware
SRC
  APT_READY=""
}

apt_get_backports() {
  backports_ready
  apt_ready
  DEBIAN_FRONTEND=noninteractive apt-get install -y -t trixie-backports "$@"
}
