raid_arch() { echo any; }
raid_desc() { echo "Linux software RAID (mdadm) and LVM with thin provisioning, dm-cache and bcache tools"; }

raid_state() { pkgs_state mdadm lvm2; }

raid_install() {
  apt_get mdadm lvm2 thin-provisioning-tools bcache-tools || return 1
  load_modules md_mod raid0 raid1 raid10 raid456 dm_mod dm_raid dm_cache dm_thin_pool
  say "Create an array with: $PROG raid create <name> 0|1|5|6|10 <disk...>"
  return 0
}

raid_remove() {
  if grep -q '^md' /proc/mdstat 2>/dev/null; then
    warn "md arrays are active, mdadm stays installed"
    apt_remove thin-provisioning-tools bcache-tools
    return 0
  fi
  apt_remove mdadm thin-provisioning-tools bcache-tools
  return 0
}

raid_create() {
  have mdadm || die "mdadm is not installed: $PROG install raid"
  name=${1:-}; level=${2:-}
  [ -n "$name" ] || die "usage: $PROG raid create <name> 0|1|5|6|10 <disk...> [--force]"
  [ -n "$level" ] || die "usage: $PROG raid create <name> 0|1|5|6|10 <disk...> [--force]"
  shift 2
  printf '%s' "$name" | grep -Eq '^[A-Za-z0-9_-]{1,32}$' || die "invalid array name: $name"
  case $level in 0 | 1 | 5 | 6 | 10) ;; *) die "level must be 0, 1, 5, 6 or 10" ;; esac
  force=0
  for a; do
    shift
    case $a in
      --force) force=1 ;;
      -*) die "unknown option $a" ;;
      *) set -- "$@" "$(whole_disk "$a")" ;;
    esac
  done
  case $level in
    0 | 1) min=2 ;;
    5) min=3 ;;
    6 | 10) min=4 ;;
  esac
  [ $# -ge "$min" ] || die "RAID $level needs at least $min disks"
  [ -e "/dev/md/$name" ] && die "/dev/md/$name already exists"
  check_disks "$force" "$@"
  for d; do wipefs -aq "$d" 2>/dev/null; done
  mdadm --create "/dev/md/$name" --name="$name" --level="$level" --raid-devices=$# --metadata=1.2 --bitmap=internal --run "$@" || die "mdadm --create failed"
  mkdir -p /etc/mdadm
  touch /etc/mdadm/mdadm.conf
  uuid=$(mdadm --detail --export "/dev/md/$name" | sed -n 's/^MD_UUID=//p')
  grep -q "$uuid" /etc/mdadm/mdadm.conf 2>/dev/null || mdadm --detail --brief "/dev/md/$name" >> /etc/mdadm/mdadm.conf
  have update-initramfs && update-initramfs -u >/dev/null 2>&1
  say "/dev/md/$name is building in the background (cat /proc/mdstat). Format it, for example: mkfs.xfs /dev/md/$name"
}

cmd_raid() {
  sub=${1:-list}
  [ $# -gt 0 ] && shift
  case $sub in
    list | status) cat /proc/mdstat 2>/dev/null || die "no md support in this kernel" ;;
    create) need_root raid create "$@"; raid_create "$@" ;;
    *) die "usage: $PROG raid list|create" ;;
  esac
}
