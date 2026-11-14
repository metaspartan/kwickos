PROG=kwick-agents
LIBDIR=/usr/lib/kwick/agents
STATE_DIR=/var/lib/kwick-agents
BINDIR=/usr/local/bin
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

is_root() { [ "$(id -u)" -eq 0 ]; }

need_root() {
  is_root && return 0
  if [ -t 0 ] || ! command -v pkexec >/dev/null 2>&1; then exec sudo -E "$SELF" "$@"; fi
  exec pkexec "$SELF" "$@"
}

mark() { mkdir -p "$STATE_DIR" && : > "$STATE_DIR/$1"; }
unmark() { rm -f "$STATE_DIR/$1"; }
marked() { [ -e "$STATE_DIR/$1" ]; }

has_arch() {
  case " $1 " in *" $ARCH "*) return 0 ;; esac
  return 1
}

pv() { eval "printf '%s' \"\${$1_$ARCH:-}\""; }

apt_ready() {
  [ -n "$APT_READY" ] && return 0
  apt-get update -qq >/dev/null 2>&1
  APT_READY=1
  return 0
}

ensure_curl() {
  command -v curl >/dev/null 2>&1 && return 0
  apt_ready
  DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates
}

fetch_verify() {
  ensure_curl || return 1
  if [ -t 2 ]; then pb=--progress-bar; else pb=-sS; fi
  curl -fL --retry 3 "$pb" -o "$3.part" "$1" || { rm -f "$3.part"; warn "download failed: $1"; return 1; }
  got=$(sha256sum "$3.part" | cut -d' ' -f1)
  if [ "$got" != "$2" ]; then
    warn "sha256 mismatch for $1 (got $got, want $2)"
    rm -f "$3.part"
    return 1
  fi
  mv "$3.part" "$3"
}
