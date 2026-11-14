PROG=kwick-storage
LIBDIR=${LIBDIR:-/usr/lib/kwick/storage}
STATE_DIR=/var/lib/kwick-storage
CONF_DIR=/etc/kwick/storage
export CONF_DIR
BPO_SOURCES=/etc/apt/sources.list.d/kwick-backports.sources
BPO_PREF=/etc/apt/preferences.d/zz-kwick-backports
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

target_user() {
  u=${SUDO_USER:-}
  if [ -z "$u" ] && [ -n "${PKEXEC_UID:-}" ]; then u=$(getent passwd "$PKEXEC_UID" | cut -d: -f1); fi
  if [ -z "$u" ] || [ "$u" = root ]; then u=$(getent passwd 1000 | cut -d: -f1); fi
  echo "$u"
}

have() { command -v "$1" >/dev/null 2>&1; }
put() { mkdir -p "$(dirname "$1")" && cat > "$1"; }
mark() { mkdir -p "$STATE_DIR" && : > "$STATE_DIR/$1"; }
unmark() { rm -f "$STATE_DIR/$1"; }
marked() { [ -e "$STATE_DIR/$1" ]; }

pkg_installed() { dpkg-query -s "$1" 2>/dev/null | grep -q '^Status: install ok installed'; }

pkgs_state() {
  have=0; total=0
  for p; do
    total=$((total + 1))
    if pkg_installed "$p"; then have=$((have + 1)); fi
  done
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

backports_ready() {
  if [ ! -f "$BPO_SOURCES" ]; then
    put "$BPO_SOURCES" <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: $BPO_SUITE
Components: main contrib
EOF
    APT_READY=""
  fi
  [ -f "$BPO_PREF" ] || put "$BPO_PREF" <<EOF
Package: *
Pin: release n=$BPO_SUITE
Pin-Priority: 100
EOF
  apt_ready
}

apt_have_candidate() {
  apt_ready
  c=$(apt-cache policy "$1" 2>/dev/null | sed -n 's/^ *Candidate: //p' | head -n 1)
  [ -n "$c" ] && [ "$c" != "(none)" ]
}

apt_get() {
  apt_ready
  for p; do
    shift
    if apt_have_candidate "$p"; then set -- "$@" "$p"; else warn "Debian 13 has no package '$p' for $ARCH, skipped"; fi
  done
  [ $# -gt 0 ] || return 0
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

apt_get_bpo() {
  backports_ready
  DEBIAN_FRONTEND=noninteractive apt-get install -y -t "$BPO_SUITE" "$@"
}

apt_remove() {
  for p; do
    shift
    if pkg_installed "$p"; then set -- "$@" "$p"; fi
  done
  [ $# -gt 0 ] || return 0
  if apt-get -s remove "$@" 2>/dev/null | grep -q '^Remv kwick-storage'; then
    warn "removing $* would also remove kwick-storage, so they stay installed"
    return 0
  fi
  DEBIAN_FRONTEND=noninteractive apt-get remove -y "$@"
}

fetch_verify() {
  have curl || apt_get curl ca-certificates || return 1
  curl -fL --retry 3 -s -o "$3.part" "$1" || { rm -f "$3.part"; warn "download failed: $1"; return 1; }
  got=$(sha256sum "$3.part" | cut -d' ' -f1)
  if [ "$got" != "$2" ]; then
    warn "sha256 mismatch for $1 (got $got, want $2)"
    rm -f "$3.part"
    return 1
  fi
  mv "$3.part" "$3"
}

deb_from_pin() {
  pkg_installed "$1" && return 0
  t=$(mktemp -d /var/tmp/kwick-storage.XXXXXX)
  rc=0
  if fetch_verify "$2" "$3" "$t/$1.deb"; then
    apt_ready
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$t/$1.deb" || rc=1
  else
    rc=1
  fi
  rm -rf "$t"
  return $rc
}

svc_enable() {
  if have systemctl && systemctl daemon-reload >/dev/null 2>&1 && systemctl enable --now "$@" >/dev/null 2>&1; then return 0; fi
  warn "could not start $* now, it starts on the next boot"
  return 0
}

svc_disable() {
  have systemctl || return 0
  systemctl disable --now "$@" >/dev/null 2>&1
  return 0
}

svc_restart() {
  have systemctl || return 0
  systemctl restart "$@" >/dev/null 2>&1 || warn "could not restart $*"
  return 0
}

svc_active() { have systemctl && systemctl is-active -q "$1" 2>/dev/null; }

systemd_running() { [ "$(cat /proc/1/comm 2>/dev/null)" = systemd ]; }

CRONTAB=/var/spool/cron/crontabs/root

cron_reload() {
  echo root >> "$(dirname "$CRONTAB")/cron.update"
  if [ -f /usr/lib/systemd/system/crond.service ]; then svc_enable crond; fi
}

schedule_set() {
  id=$1; cal=$2; cron=$3
  shift 3
  schedule_clear "$id"
  if systemd_running; then
    put "/etc/systemd/system/kwick-storage-$id.service" <<EOF
[Unit]
Description=kwick-storage $id

[Service]
Type=oneshot
ExecStart=$*
EOF
    put "/etc/systemd/system/kwick-storage-$id.timer" <<EOF
[Unit]
Description=kwick-storage $id schedule

[Timer]
OnCalendar=$cal
RandomizedDelaySec=15min
Persistent=true

[Install]
WantedBy=timers.target
EOF
    svc_enable "kwick-storage-$id.timer"
  else
    mkdir -p "$(dirname "$CRONTAB")"
    touch "$CRONTAB"
    grep -v "KWICK_JOB=$id " "$CRONTAB" > "$CRONTAB.new" || true
    printf '%s KWICK_JOB=%s %s >/dev/null 2>&1\n' "$cron" "$id" "$*" >> "$CRONTAB.new"
    mv "$CRONTAB.new" "$CRONTAB"
    chmod 600 "$CRONTAB"
    cron_reload
  fi
}

schedule_clear() {
  if [ -f "/etc/systemd/system/kwick-storage-$1.timer" ]; then
    svc_disable "kwick-storage-$1.timer"
    rm -f "/etc/systemd/system/kwick-storage-$1.timer" "/etc/systemd/system/kwick-storage-$1.service"
    have systemctl && systemctl daemon-reload >/dev/null 2>&1
  fi
  if [ -f "$CRONTAB" ] && grep -q "KWICK_JOB=$1 " "$CRONTAB"; then
    grep -v "KWICK_JOB=$1 " "$CRONTAB" > "$CRONTAB.new" || true
    mv "$CRONTAB.new" "$CRONTAB"
    chmod 600 "$CRONTAB"
    cron_reload
  fi
  return 0
}

schedule_list() {
  for t in /etc/systemd/system/kwick-storage-*.timer; do
    [ -f "$t" ] || continue
    n=${t##*/kwick-storage-}
    printf '%s %s\n' "${n%.timer}" "$(sed -n 's/^OnCalendar=//p' "$t")"
  done
  [ -f "$CRONTAB" ] && sed -n 's/^\(.*\) KWICK_JOB=\([^ ]*\) .*/\2 \1/p' "$CRONTAB"
  return 0
}

load_modules() {
  for km; do modprobe "$km" 2>/dev/null; done
  return 0
}

whole_disk() {
  d=$1
  case $d in /dev/*) ;; *) d=/dev/$d ;; esac
  [ -b "$d" ] || die "$d is not a block device"
  n=${d#/dev/}
  [ -d "/sys/block/$n" ] || die "$d is a partition, give a whole disk"
  echo "$d"
}

disk_in_use() {
  n=${1#/dev/}
  grep -q "^/dev/$n" /proc/mounts 2>/dev/null && return 0
  grep -q "^/dev/$n" /proc/swaps 2>/dev/null && return 0
  if have lsblk && lsblk -no MOUNTPOINT "$1" 2>/dev/null | grep -q .; then return 0; fi
  return 1
}

disk_has_data() {
  for p in /sys/block/"${1#/dev/}"/"${1#/dev/}"*; do
    [ -e "$p/partition" ] && return 0
  done
  have blkid && blkid "$1" 2>/dev/null | grep -q 'TYPE='  && return 0
  [ -n "$(dd if="$1" bs=4096 count=1 2>/dev/null | tr -d '\000' | head -c 1)" ]
}

check_disks() {
  force=$1
  shift
  for d; do
    disk_in_use "$d" && die "$d is mounted or in use"
    if disk_has_data "$d" && [ "$force" != 1 ]; then
      die "$d has a partition table or filesystem, pass --force to wipe it"
    fi
  done
}

human() {
  awk -v b="$1" 'BEGIN { if (b >= 1099511627776) printf "%.1fT", b / 1099511627776; else if (b >= 1073741824) printf "%.1fG", b / 1073741824; else printf "%dM", b / 1048576 }'
}

fstab_set() {
  mp=$1
  line=$2
  if [ -f /etc/fstab ]; then
    awk -v m="$mp" '$2 != m' /etc/fstab > /etc/fstab.kwick-new
  else
    : > /etc/fstab.kwick-new
  fi
  [ -n "$line" ] && printf '%s\n' "$line" >> /etc/fstab.kwick-new
  cat /etc/fstab.kwick-new > /etc/fstab
  rm -f /etc/fstab.kwick-new
}

part_dev() {
  case $1 in
    *[0-9]) echo "${1}p$2" ;;
    *) echo "${1}$2" ;;
  esac
}

dev_size() { echo $(($(cat "/sys/class/block/${1#/dev/}/size" 2>/dev/null || echo 0) * 512)); }

fs_type() { blkid "$1" 2>/dev/null | sed -n 's/.* TYPE="\([^"]*\)".*/\1/p'; }
fs_uuid() { blkid "$1" 2>/dev/null | sed -n 's/.* UUID="\([^"]*\)".*/\1/p'; }

udev_running() { [ -S /run/udev/control ]; }

zfs_partition() {
  have sfdisk || apt_get fdisk >/dev/null || die "sfdisk is needed to partition $1"
  wipefs -aq "$1" >/dev/null 2>&1
  printf 'label: gpt\nstart=2048, type=6A898CC3-1DD2-11B2-99A6-080020736631, name="zfs"\n' | sfdisk -q --wipe always "$1" >/dev/null || die "partitioning $1 failed"
  have partprobe && partprobe "$1" 2>/dev/null
  p=$(part_dev "$1" 1)
  wait_dev "$p" || die "$p did not appear"
  echo "$p"
}

wait_dev() {
  i=0
  while [ ! -b "$1" ] && [ $i -lt 20 ]; do sleep 0.5; i=$((i + 1)); done
  s=/sys/class/block/${1#/dev/}/dev
  if [ ! -b "$1" ] && [ -r "$s" ]; then
    mknod "$1" b "$(cut -d: -f1 "$s")" "$(cut -d: -f2 "$s")"
  fi
  [ -b "$1" ]
}
