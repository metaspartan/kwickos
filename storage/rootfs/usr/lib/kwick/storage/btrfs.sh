btrfs_arch() { echo any; }
btrfs_desc() { echo "Btrfs tools, snapper snapshots and btrfsmaintenance scrub and balance timers"; }

btrfs_state() { pkgs_state btrfs-progs snapper; }

btrfs_install() {
  apt_get btrfs-progs snapper btrfsmaintenance || return 1
  load_modules btrfs
  for t in btrfs-scrub.timer btrfs-balance.timer btrfs-trim.timer; do
    [ -f "/usr/lib/systemd/system/$t" ] && svc_enable "$t"
  done
  say "Snapshots for a btrfs mount: snapper -c <name> create-config <mountpoint>"
  return 0
}

btrfs_remove() {
  if awk '$3 == "btrfs" { f = 1 } END { exit !f }' /proc/mounts; then
    warn "btrfs filesystems are mounted, btrfs-progs stays installed"
    apt_remove snapper btrfsmaintenance
    return 0
  fi
  apt_remove snapper btrfsmaintenance btrfs-progs
  return 0
}
