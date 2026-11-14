PROG=kwick-pen
LIBDIR=/usr/lib/kwick/pen
STATE_DIR=/var/lib/kwick-pen
OPT=/opt/kwick-pen
BINDIR=/usr/local/bin
KEYRING_DIR=/usr/share/keyrings
APT_READY=""
ASSUME_YES=""
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

is_root() { [ "$(id -u)" -eq 0 ]; }

need_root() {
  is_root && return 0
  if [ -t 0 ] || ! command -v pkexec >/dev/null 2>&1; then exec sudo -E "$SELF" "$@"; fi
  exec pkexec "$SELF" "$@"
}

put() { mkdir -p "$(dirname "$1")" && cat > "$1"; }
mark() { mkdir -p "$STATE_DIR" && : > "$STATE_DIR/$1"; }
unmark() { rm -f "$STATE_DIR/$1"; }
marked() { [ -e "$STATE_DIR/$1" ]; }

pv() { eval "printf '%s' \"\${$1_$ARCH:-}\""; }

has_arch() {
  case " $1 " in *" $ARCH "*) return 0 ;; esac
  return 1
}

confirm() {
  [ -n "$ASSUME_YES" ] && return 0
  if [ ! -t 0 ]; then
    warn "$1"
    warn "non-interactive run: pass --yes to accept"
    return 1
  fi
  printf '%s [y/N] ' "$1"
  read -r ans
  case $ans in y|Y|yes|YES) return 0 ;; esac
  return 1
}

notice_file() { echo "${XDG_CONFIG_HOME:-${HOME:-/root}/.config}/kwick-pen/notice-1"; }

show_notice() {
  [ -n "${KWICK_PEN_NOTICE:-}" ] && return 0
  f=$(notice_file)
  [ -e "$f" ] && return 0
  cat >&2 <<EOF
kwick-pen: these tools are for authorized security testing only.
Use them on systems you own or have written permission to test. Unauthorized
access is illegal. You are responsible for how you use them.
EOF
  if mkdir -p "$(dirname "$f")" 2>/dev/null && : > "$f" 2>/dev/null; then :; fi
  KWICK_PEN_NOTICE=1
  export KWICK_PEN_NOTICE
  return 0
}

pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed'; }

apt_ready() {
  [ -n "$APT_READY" ] && return 0
  sed -i 's/^Components: main$/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources 2>/dev/null
  apt-get update -qq >/dev/null 2>&1
  APT_READY=1
  return 0
}

apt_refresh() {
  APT_READY=""
  apt_ready
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

ensure_tools() {
  for need; do
    command -v "$need" >/dev/null 2>&1 && continue
    case $need in
      curl) apt_get curl ca-certificates || return 1 ;;
      unzip) apt_get unzip || return 1 ;;
      gpg) apt_get gnupg || return 1 ;;
      git) apt_get git ca-certificates || return 1 ;;
      *) apt_get "$need" || return 1 ;;
    esac
  done
  return 0
}

fetch_verify() {
  ensure_tools curl || return 1
  curl -fsSL --retry 3 -o "$3.part" "$1" || { rm -f "$3.part"; warn "download failed: $1"; return 1; }
  got=$(sha256sum "$3.part" | cut -d' ' -f1)
  if [ "$got" != "$2" ]; then
    warn "sha256 mismatch for $1 (got $got, want $2)"
    rm -f "$3.part"
    return 1
  fi
  mv "$3.part" "$3"
}

mktmp() { mktemp -d /var/tmp/kwick-pen.XXXXXX; }

unpack() {
  case $1 in
    *.zip) ensure_tools unzip || return 1; unzip -q -o "$1" -d "$2" ;;
    *.tar.gz|*.tgz) tar -xzf "$1" -C "$2" ;;
    *) return 1 ;;
  esac
}

bin_archive() {
  n=$1
  url=$(pv "$2")
  sha=$(pv "$3")
  member=$4
  [ -n "$url" ] && [ -n "$sha" ] || { warn "$n: no release for $ARCH"; return 1; }
  t=$(mktmp)
  ar=$t/$(basename "$url")
  fetch_verify "$url" "$sha" "$ar" || { rm -rf "$t"; return 1; }
  mkdir "$t/x"
  unpack "$ar" "$t/x" || { rm -rf "$t"; warn "$n: could not unpack"; return 1; }
  f=$(find "$t/x" -type f -name "$member" | head -n 1)
  [ -n "$f" ] || { rm -rf "$t"; warn "$n: $member not found in archive"; return 1; }
  install -m 755 "$f" "$BINDIR/$n"
  rm -rf "$t"
  return 0
}

bin_plain() {
  n=$1
  url=$(pv "$2")
  sha=$(pv "$3")
  [ -n "$url" ] && [ -n "$sha" ] || { warn "$n: no release for $ARCH"; return 1; }
  t=$(mktmp)
  fetch_verify "$url" "$sha" "$t/$n" || { rm -rf "$t"; return 1; }
  install -m 755 "$t/$n" "$BINDIR/$n"
  rm -rf "$t"
  return 0
}

opt_archive() {
  n=$1
  url=$2
  sha=$3
  t=$(mktmp)
  ar=$t/$(basename "$url")
  fetch_verify "$url" "$sha" "$ar" || { rm -rf "$t"; return 1; }
  mkdir "$t/x"
  unpack "$ar" "$t/x" || { rm -rf "$t"; warn "$n: could not unpack"; return 1; }
  rm -rf "${OPT:?}/$n"
  mkdir -p "$OPT"
  d=$(find "$t/x" -mindepth 1 -maxdepth 1 | head -n 1)
  if [ "$(find "$t/x" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1 ] && [ -d "$d" ]; then mv "$d" "$OPT/$n"; else mv "$t/x" "$OPT/$n"; fi
  rm -rf "$t"
  return 0
}

link_bin() { ln -sf "$1" "$BINDIR/$2"; }

pipx_ready() {
  command -v pipx >/dev/null 2>&1 || apt_get pipx python3-venv || return 1
  ensure_tools git || return 1
  PIPX_HOME=$OPT/pipx
  PIPX_BIN_DIR=$BINDIR
  PIPX_MAN_DIR=/usr/local/share/man
  export PIPX_HOME PIPX_BIN_DIR PIPX_MAN_DIR
  mkdir -p "$OPT"
  return 0
}

pipx_add() {
  pipx_ready || return 1
  pipx install --force "$2"
}

pipx_del() {
  pipx_ready || return 1
  pipx uninstall "$1" >/dev/null 2>&1
  return 0
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

vendor_repo() {
  n=$1
  url=$2
  fpr=$3
  repo=$4
  suite=$5
  ensure_tools curl gpg || return 1
  t=$(mktmp)
  curl -fsSL --retry 3 -o "$t/key" "$url" || { rm -rf "$t"; warn "$n: key download failed"; return 1; }
  got=$(gpg --show-keys --with-colons "$t/key" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')
  if [ "$got" != "$fpr" ]; then
    warn "$n: signing key fingerprint mismatch (got $got, want $fpr)"
    rm -rf "$t"
    return 1
  fi
  mkdir -p "$KEYRING_DIR"
  gpg --dearmor < "$t/key" > "$KEYRING_DIR/kwick-pen-$n.gpg"
  chmod 644 "$KEYRING_DIR/kwick-pen-$n.gpg"
  rm -rf "$t"
  put "/etc/apt/sources.list.d/kwick-pen-$n.list" <<EOF
deb [arch=$ARCH signed-by=$KEYRING_DIR/kwick-pen-$n.gpg] $repo $suite main
EOF
  apt_refresh
  return 0
}

vendor_repo_drop() {
  rm -f "/etc/apt/sources.list.d/kwick-pen-$1.list" "$KEYRING_DIR/kwick-pen-$1.gpg"
  APT_READY=""
  apt-get update -qq >/dev/null 2>&1
  return 0
}
