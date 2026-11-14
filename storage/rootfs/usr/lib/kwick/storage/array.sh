ARRAY_CONF=$CONF_DIR/array.conf
SNAPRAID_CONF=/etc/snapraid.conf
ARRAY_UNIT=/etc/systemd/system/kwick-array.service

array_arch() { echo any; }
array_desc() { echo "Unraid-style array: mergerfs pools data disks of any size, SnapRAID parity with a nightly sync and weekly scrub"; }

array_state() { pkgs_state mergerfs snapraid; }

array_install() {
  apt_get mergerfs snapraid xfsprogs e2fsprogs fdisk || return 1
  load_modules fuse
  say "Set up the array with: $PROG array setup --data <disk,...> --parity <disk> [--format --yes]"
  return 0
}

array_remove() {
  if [ -f "$ARRAY_CONF" ]; then
    warn "an array is configured in $ARRAY_CONF, run '$PROG array teardown' first"
    return 1
  fi
  apt_remove mergerfs snapraid
  return 0
}

array_prepare() {
  dev=$1; role=$2; idx=$3; fmt=$4; fs=$5; force=$6
  if [ "$fmt" = 1 ]; then
    d=$(whole_disk "$dev")
    disk_in_use "$d" && die "$d is mounted or in use"
    wipefs -aq "$d" >/dev/null 2>&1
    printf 'label: gpt\n,,L\n' | sfdisk -q --wipe always "$d" >/dev/null || die "partitioning $d failed"
    have partprobe && partprobe "$d" 2>/dev/null
    have udevadm && udevadm settle 2>/dev/null
    p=$(part_dev "$d" 1)
    wait_dev "$p" || die "$p did not appear"
    if [ "$role" = parity ]; then
      mkfs.ext4 -F -q -m 0 -T largefile4 -L "kwparity$idx" "$p" || die "mkfs on $p failed"
    elif [ "$fs" = ext4 ]; then
      mkfs.ext4 -F -q -m 0 -L "kwdisk$idx" "$p" || die "mkfs on $p failed"
    else
      mkfs.xfs -f -q -L "kwdisk$idx" "$p" || die "mkfs on $p failed"
    fi
    echo "$p"
    return 0
  fi
  case $dev in /dev/*) p=$dev ;; *) p=/dev/$dev ;; esac
  [ -b "$p" ] || die "$p is not a block device"
  t=$(fs_type "$p")
  [ -n "$t" ] || die "$p has no filesystem, pass --format --yes to create one"
  if disk_in_use "$p" && [ "$force" != 1 ]; then die "$p is mounted, unmount it or pass --force"; fi
  echo "$p"
}

array_setup() {
  data=""; parity=""; mnt=/mnt/storage; fmt=0; yes=0; fs=xfs; force=0; minfree=4G
  while [ $# -gt 0 ]; do
    case $1 in
      --data) data="$data $(echo "${2:?--data needs disks}" | tr ',' ' ')"; shift ;;
      --parity) parity="$parity $(echo "${2:?--parity needs a disk}" | tr ',' ' ')"; shift ;;
      --mount) mnt=${2:?--mount needs a directory}; shift ;;
      --fs) fs=${2:?--fs needs xfs or ext4}; shift ;;
      --minfree) minfree=${2:?--minfree needs a size such as 4G}; shift ;;
      --format) fmt=1 ;;
      --yes) yes=1 ;;
      --force) force=1 ;;
      *) die "unknown option $1" ;;
    esac
    shift
  done
  [ -n "$data" ] || die "usage: $PROG array setup --data <disk,disk,...> --parity <disk>[,<disk>] [--mount DIR] [--fs xfs|ext4] [--minfree 4G] [--format --yes]"
  case $fs in xfs | ext4) ;; *) die "--fs takes xfs or ext4" ;; esac
  [ -f "$ARRAY_CONF" ] && die "an array is already configured ($ARRAY_CONF), run '$PROG array teardown' first"
  [ "$fmt" = 1 ] && [ "$yes" != 1 ] && die "--format erases$data$parity, add --yes to confirm"
  np=0
  for p in $parity; do np=$((np + 1)); done
  [ "$np" -le 6 ] || die "SnapRAID supports up to 6 parity disks"
  [ "$np" -ge 1 ] || warn "no parity disk given: the pool works but nothing protects it"
  have mergerfs && have snapraid || array_install || die "mergerfs and snapraid could not be installed"
  [ "$fmt" = 1 ] && { have sfdisk || apt_get fdisk; }
  [ "$fs" = xfs ] && [ "$fmt" = 1 ] && { have mkfs.xfs || apt_get xfsprogs; }

  i=0; dparts=""; maxd=0
  for d in $data; do
    i=$((i + 1))
    p=$(array_prepare "$d" data "$i" "$fmt" "$fs" "$force") || exit 1
    dparts="$dparts $p"
    s=$(dev_size "$p")
    [ "$s" -gt "$maxd" ] && maxd=$s
  done
  i=0; pparts=""
  for d in $parity; do
    i=$((i + 1))
    p=$(array_prepare "$d" parity "$i" "$fmt" ext4 "$force") || exit 1
    pparts="$pparts $p"
    s=$(dev_size "$p")
    [ "$s" -ge "$maxd" ] || die "parity $p ($(human "$s")) is smaller than the largest data disk ($(human "$maxd"))"
  done

  mkdir -p "$CONF_DIR" /var/lib/snapraid "$mnt"
  branches=""; i=0
  for p in $dparts; do
    i=$((i + 1))
    m=/mnt/disk$i
    mkdir -p "$m"
    fstab_set "$m" "UUID=$(fs_uuid "$p") $m $(fs_type "$p") defaults,noatime,nofail 0 2"
    branches="$branches${branches:+:}$m"
  done
  i=0
  for p in $pparts; do
    i=$((i + 1))
    m=/mnt/parity$i
    mkdir -p "$m"
    fstab_set "$m" "UUID=$(fs_uuid "$p") $m $(fs_type "$p") defaults,noatime,nofail 0 2"
  done
  fstab_set "$mnt" ""
  mopts="allow_other,cache.files=off,category.create=mfs,func.getattr=newest,dropcacheonclose=true,moveonenospc=true,minfreespace=$minfree,fsname=kwick-array"
  put "$ARRAY_UNIT" <<EOF
[Unit]
Description=kwick-storage mergerfs array at $mnt
After=local-fs.target
RequiresMountsFor=$(echo "$branches" | tr ':' ' ')

[Service]
Type=simple
ExecStart=$(command -v mergerfs) -f -o $mopts $branches $mnt
ExecStopPost=-/bin/umount -l $mnt
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  {
    i=0
    for p in $pparts; do
      i=$((i + 1))
      if [ $i -eq 1 ]; then printf 'parity /mnt/parity1/snapraid.parity\n'; else printf '%s-parity /mnt/parity%s/snapraid.%s-parity\n' "$i" "$i" "$i"; fi
    done
    printf 'content /var/lib/snapraid/snapraid.content\n'
    i=0
    for p in $dparts; do
      i=$((i + 1))
      printf 'content /mnt/disk%s/.snapraid.content\n' "$i"
    done
    i=0
    for p in $dparts; do
      i=$((i + 1))
      printf 'data d%s /mnt/disk%s/\n' "$i" "$i"
    done
    printf 'exclude *.unrecoverable\nexclude /tmp/\nexclude /lost+found/\nexclude .Trash-*/\nexclude .snapraid.content\nautosave 500\n'
  } > "$SNAPRAID_CONF"

  {
    printf 'MOUNT=%s\n' "$mnt"
    printf 'DATA=%s\n' "$(echo "$dparts" | sed 's/^ //')"
    printf 'PARITY=%s\n' "$(echo "$pparts" | sed 's/^ //')"
  } > "$ARRAY_CONF"

  i=0
  for p in $dparts; do i=$((i + 1)); mountpoint -q "/mnt/disk$i" || mount "/mnt/disk$i" || die "mounting /mnt/disk$i failed"; done
  i=0
  for p in $pparts; do i=$((i + 1)); mountpoint -q "/mnt/parity$i" || mount "/mnt/parity$i" || die "mounting /mnt/parity$i failed"; done
  svc_enable kwick-array
  i=0
  while ! mountpoint -q "$mnt" && [ $i -lt 10 ]; do sleep 0.5; i=$((i + 1)); done
  mountpoint -q "$mnt" || mergerfs -o "$mopts" "$branches" "$mnt" || die "mounting the mergerfs pool at $mnt failed"
  if [ -n "$pparts" ]; then
    schedule_set array-sync "*-*-* 03:30:00" "30 3 * * *" /usr/bin/kwick-storage array sync
    schedule_set array-scrub "Sun *-*-* 05:00:00" "0 5 * * 0" /usr/bin/kwick-storage array scrub
  fi
  say "array ready: $mnt pools $(echo "$dparts" | wc -w | tr -d ' ') data disk(s), $np parity disk(s)"
  say "first parity build: $PROG array sync (nightly sync and weekly scrub are scheduled)"
}

array_teardown() {
  [ -f "$ARRAY_CONF" ] || die "no array is configured"
  mnt=$(sed -n 's/^MOUNT=//p' "$ARRAY_CONF")
  svc_disable kwick-array
  rm -f "$ARRAY_UNIT"
  umount "$mnt" 2>/dev/null
  fstab_set "$mnt" ""
  for m in /mnt/disk[0-9]* /mnt/parity[0-9]*; do
    [ -d "$m" ] || continue
    umount "$m" 2>/dev/null
    fstab_set "$m" ""
  done
  schedule_clear array-sync
  schedule_clear array-scrub
  mv "$SNAPRAID_CONF" "$SNAPRAID_CONF.old" 2>/dev/null
  rm -f "$ARRAY_CONF"
  say "array removed from fstab and schedules; the disks and their data are untouched"
}

array_status() {
  if [ ! -f "$ARRAY_CONF" ]; then say "no array configured"; return 0; fi
  mnt=$(sed -n 's/^MOUNT=//p' "$ARRAY_CONF")
  df -h "$mnt" /mnt/disk[0-9]* /mnt/parity[0-9]* 2>/dev/null
  echo
  have snapraid && snapraid -c "$SNAPRAID_CONF" status 2>&1 | tail -n 20
  echo
  schedule_list | grep '^array' || true
}

array_lock() {
  mkdir -p /run/kwick-storage
  if ! mkdir /run/kwick-storage/snapraid.lock 2>/dev/null; then die "another SnapRAID job is running"; fi
  trap 'rmdir /run/kwick-storage/snapraid.lock 2>/dev/null' EXIT INT TERM
}

array_sync() {
  [ -f "$SNAPRAID_CONF" ] || die "no array configured"
  array_lock
  snapraid -c "$SNAPRAID_CONF" sync
}

array_scrub() {
  [ -f "$SNAPRAID_CONF" ] || die "no array configured"
  array_lock
  snapraid -c "$SNAPRAID_CONF" scrub -p "${1:-8}" -o "${2:-10}"
}

cmd_array() {
  sub=${1:-status}
  [ $# -gt 0 ] && shift
  case $sub in
    status) array_status ;;
    setup) need_root array setup "$@"; array_setup "$@" ;;
    sync) need_root array sync "$@"; array_sync ;;
    scrub) need_root array scrub "$@"; array_scrub "$@" ;;
    fix) need_root array fix "$@"; array_lock; snapraid -c "$SNAPRAID_CONF" fix "$@" ;;
    teardown) need_root array teardown; array_teardown ;;
    *) die "usage: $PROG array status|setup|sync|scrub|fix|teardown" ;;
  esac
}
