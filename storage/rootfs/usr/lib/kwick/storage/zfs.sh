ZFS_PREF=/etc/apt/preferences.d/kwick-zfs
SANOID_CONF=/etc/sanoid/sanoid.conf
SNAP_LIST=$CONF_DIR/snapshots.list

zfs_arch() { echo any; }
zfs_desc() { echo "OpenZFS: prebuilt modules for the KwickOS kernel, Debian userland, zed, sanoid snapshots and a monthly scrub"; }

zfs_why() {
  if [ ! -e /proc/modules ]; then echo "this kernel cannot load modules, install linux-image-kwick-generic"; return 0; fi
  echo "unavailable"
}

zfs_mods_present() {
  modinfo zfs >/dev/null 2>&1 && return 0
  [ -n "$(find "/usr/lib/modules/$(uname -r)" -name 'zfs.ko*' 2>/dev/null | head -n 1)" ]
}

zfs_state() {
  [ -e /proc/modules ] || { echo na; return 0; }
  a=no; b=no; c=no
  zfs_mods_present && a=yes
  have zpool && b=yes
  pkg_installed sanoid && c=yes
  combine_state "$a" "$b" "$c"
}

zfs_pin() {
  put "$ZFS_PREF" <<EOF
Package: /^(zfsutils-linux|zfs-zed|zfs-initramfs|zfs-dracut|zfs-test|libzfs[0-9].*|libzpool[0-9].*|libnvpair[0-9].*|libuutil[0-9].*|libzfsbootenv[0-9].*|python3-pyzfs|pyzfs-doc)$/
Pin: release n=$BPO_SUITE
Pin-Priority: 990
EOF
}

zfs_install() {
  [ -e /proc/modules ] || { warn "$(zfs_why)"; return 1; }
  zfs_pin
  backports_ready
  kr=$(uname -r)
  set -- zfsutils-linux zfs-zed
  if apt_have_candidate kwick-zfs; then
    set -- "$@" kwick-zfs
  elif ! zfs_mods_present; then
    warn "the KwickOS package repository has no kwick-zfs, add it to /etc/apt/sources.list.d first"
    return 1
  fi
  if apt_have_candidate "kwick-zfs-modules-$kr"; then
    set -- "$@" "kwick-zfs-modules-$kr"
  elif ! zfs_mods_present; then
    warn "no prebuilt OpenZFS modules for the running kernel $kr; the ones for the newest KwickOS kernel are installed, reboot into it to use ZFS"
  fi
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" || return 1
  apt_get sanoid
  load_modules zfs
  systemd_running || zfs_kinit_import
  sanoid_write
  sanoid_schedule
  for p in $(zpool list -H -o name 2>/dev/null); do zfs_scrub_schedule "$p"; done
  say "OpenZFS $(cat /sys/module/zfs/version 2>/dev/null || echo installed). Create a pool with: $PROG pool create <name> mirror|raidz1|raidz2|stripe <disk...>"
  return 0
}

zfs_remove() {
  if awk '$2 == "/" && $3 == "zfs" { f = 1 } END { exit !f }' /proc/mounts; then
    warn "the root filesystem is on ZFS, the ZFS packages stay installed"
    return 1
  fi
  for p in $(zpool list -H -o name 2>/dev/null); do schedule_clear "zfs-scrub-$p"; done
  schedule_clear sanoid
  svc_disable kwick-zfs-import
  rm -f /etc/systemd/system/kwick-zfs-import.service
  set -- kwick-zfs zfs-zed zfsutils-linux sanoid
  for m in $(dpkg-query -W 'kwick-zfs-modules-*' 2>/dev/null | awk '{ print $1 }'); do set -- "$@" "$m"; done
  apt_remove "$@"
  rm -f "$ZFS_PREF"
  return 0
}

sanoid_write() {
  pkg_installed sanoid || return 0
  if [ -f "$SANOID_CONF" ] && ! marked sanoid-managed; then
    warn "$SANOID_CONF was written by someone else, automatic snapshots are left to it"
    return 0
  fi
  mkdir -p "$CONF_DIR"
  touch "$SNAP_LIST"
  {
    printf '[template_kwick]\n\tfrequently = 0\n\thourly = 24\n\tdaily = 30\n\tweekly = 8\n\tmonthly = 6\n\tyearly = 0\n\tautosnap = yes\n\tautoprune = yes\n'
    while IFS= read -r ds; do
      [ -n "$ds" ] || continue
      printf '\n[%s]\n\tuse_template = kwick\n\trecursive = yes\n' "$ds"
    done < "$SNAP_LIST"
  } | put "$SANOID_CONF"
  mark sanoid-managed
}

zfs_kinit_import() {
  put /etc/systemd/system/kwick-zfs-import.service <<'EOF'
[Unit]
Description=Import and mount ZFS pools (kwick-storage)
After=local-fs.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'modprobe zfs || exit 1; if [ -s /etc/zfs/zpool.cache ]; then zpool import -a -N -c /etc/zfs/zpool.cache; else zpool import -a -N; fi; zfs mount -a; pgrep -x zed >/dev/null || /usr/sbin/zed; exit 0'

[Install]
WantedBy=multi-user.target
EOF
  svc_enable kwick-zfs-import
}

sanoid_schedule() {
  pkg_installed sanoid || return 0
  if systemd_running; then
    svc_enable sanoid.timer
  else
    schedule_set sanoid "*:0/15" "*/15 * * * *" /usr/sbin/sanoid --cron
  fi
}

zfs_scrub_schedule() {
  schedule_set "zfs-scrub-$1" "*-*-01 03:00:00" "0 3 1 * *" /usr/sbin/zpool scrub "$1"
}

zfs_ready() {
  have zpool || die "ZFS is not installed: $PROG install zfs"
  [ -e /dev/zfs ] || modprobe zfs 2>/dev/null || die "the zfs module does not load for kernel $(uname -r)"
}

disk_by_id() {
  t=$(readlink -f "$1")
  for l in /dev/disk/by-id/*; do
    [ -e "$l" ] || continue
    if [ "$(readlink -f "$l")" = "$t" ]; then
      case ${l##*/} in wwn-* | nvme-eui.* | nvme-uuid.*) continue ;; esac
      echo "$l"
      return 0
    fi
  done
  echo "$1"
}

pool_create() {
  zfs_ready
  name=${1:-}
  layout=${2:-}
  [ -n "$name" ] || die "usage: $PROG pool create <name> stripe|mirror|raidz1|raidz2|raidz3 <disk...>"
  [ -n "$layout" ] || die "usage: $PROG pool create <name> stripe|mirror|raidz1|raidz2|raidz3 <disk...> [--mount DIR] [--ashift N] [--force]"
  shift 2
  printf '%s' "$name" | grep -Eq '^[A-Za-z][A-Za-z0-9_.-]{0,63}$' || die "invalid pool name: $name"
  case $name in mirror* | raidz* | draid* | spare* | log | cache | special | dedup) die "reserved pool name: $name" ;; esac
  force=0; mnt=/mnt/$name; ashift=12; disks=""
  while [ $# -gt 0 ]; do
    case $1 in
      --force) force=1 ;;
      --mount) mnt=${2:?--mount needs a directory}; shift ;;
      --ashift) ashift=${2:?--ashift needs a value}; shift ;;
      -*) die "unknown option $1" ;;
      *) disks="$disks $(whole_disk "$1")" ;;
    esac
    shift
  done
  set --
  for d in $disks; do set -- "$@" "$d"; done
  n=$#
  case $layout in
    stripe) vdev=""; min=1 ;;
    mirror) vdev=mirror; min=2 ;;
    raidz | raidz1) vdev=raidz1; min=2 ;;
    raidz2) vdev=raidz2; min=3 ;;
    raidz3) vdev=raidz3; min=4 ;;
    *) die "unknown layout $layout (stripe, mirror, raidz1, raidz2, raidz3)" ;;
  esac
  [ "$n" -ge "$min" ] || die "$layout needs at least $min disks"
  zpool list -H "$name" >/dev/null 2>&1 && die "pool $name already exists"
  check_disks "$force" "$@"
  ids=""
  for d; do
    if udev_running; then
      ids="$ids $(disk_by_id "$d")"
    else
      p=$(zfs_partition "$d") || exit 1
      ids="$ids $(disk_by_id "$p")"
    fi
  done
  set -- -o ashift="$ashift" -o autotrim=on \
    -O compression=lz4 -O atime=off -O xattr=sa -O acltype=posixacl -O dnodesize=auto -O normalization=formD \
    -m "$mnt" "$name"
  [ "$force" = 1 ] && set -- -f "$@"
  [ -n "$vdev" ] && set -- "$@" "$vdev"
  for d in $ids; do set -- "$@" "$d"; done
  say "creating $layout pool $name on$ids, mounted at $mnt"
  zpool create "$@" || die "zpool create failed"
  zpool set cachefile=/etc/zfs/zpool.cache "$name" 2>/dev/null
  zfs_scrub_schedule "$name"
  zpool list "$name"
  say "a scrub runs on the first of every month. Automatic snapshots: $PROG pool auto-snapshot $name on"
}

pool_autosnap() {
  ds=${1:-}; st=${2:-}
  [ -n "$ds" ] || die "usage: $PROG pool auto-snapshot <dataset> on|off"
  zfs_ready
  zfs list -H -o name "$ds" >/dev/null 2>&1 || die "no dataset $ds"
  pkg_installed sanoid || apt_get sanoid || die "sanoid could not be installed"
  mkdir -p "$CONF_DIR"
  touch "$SNAP_LIST"
  grep -vx "$ds" "$SNAP_LIST" > "$SNAP_LIST.new" || true
  case $st in
    on) echo "$ds" >> "$SNAP_LIST.new" ;;
    off) ;;
    *) rm -f "$SNAP_LIST.new"; die "usage: $PROG pool auto-snapshot <dataset> on|off" ;;
  esac
  mv "$SNAP_LIST.new" "$SNAP_LIST"
  sanoid_write
  sanoid_schedule
  say "automatic snapshots for $ds: $st (hourly 24, daily 30, weekly 8, monthly 6)"
}

pool_snapshot() {
  zfs_ready
  ds=${1:-}
  [ -n "$ds" ] || die "usage: $PROG pool snapshot <dataset> [name]"
  sn=${2:-kwick-$(date +%Y%m%d-%H%M%S)}
  zfs snapshot "$ds@$sn" || die "snapshot failed"
  say "$ds@$sn"
}

pool_rollback() {
  zfs_ready
  snap=${1:-}
  case $snap in *@*) ;; *) die "usage: $PROG pool rollback <dataset@snapshot> [--force]" ;; esac
  if [ "${2:-}" = --force ]; then
    zfs rollback -r "$snap" || die "rollback failed"
  else
    zfs rollback "$snap" || die "rollback failed; newer snapshots exist, --force destroys them"
  fi
  say "rolled back to $snap"
}

cmd_pool() {
  sub=${1:-list}
  [ $# -gt 0 ] && shift
  case $sub in
    list) zfs_ready; zpool list ;;
    status) zfs_ready; zpool status "$@" ;;
    create) need_root pool create "$@"; pool_create "$@" ;;
    scrub) need_root pool scrub "$@"; zfs_ready; zpool scrub "${1:?pool}" && say "scrub of $1 started: $PROG pool status $1" ;;
    snapshot) need_root pool snapshot "$@"; pool_snapshot "$@" ;;
    snapshots) zfs_ready; zfs list -t snapshot -o name,used,refer,creation ${1:+-r "$1"} ;;
    rollback) need_root pool rollback "$@"; pool_rollback "$@" ;;
    auto-snapshot) need_root pool auto-snapshot "$@"; pool_autosnap "$@" ;;
    *) die "usage: $PROG pool list|status|create|scrub|snapshot|snapshots|rollback|auto-snapshot" ;;
  esac
}
