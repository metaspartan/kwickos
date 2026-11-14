tweaks_arch() { echo any; }
tweaks_desc() { echo "zram swap, VM sysctls, ntsync, I/O schedulers and earlyoom (the Bazzite performance defaults)"; }

tweaks_state() {
  a=$(pkgs_state systemd-zram-generator earlyoom)
  b=no
  [ -e /etc/sysctl.d/21-kwick-gaming-tweaks.conf ] && b=yes
  combine_state "$a" "$b"
}

tweaks_install() {
  apt_get systemd-zram-generator earlyoom || return 1
  put /etc/systemd/zram-generator.conf.d/kwick-gaming.conf <<'EOF'
[zram0]
zram-size = min(ram, 8192)
compression-algorithm = zstd
swap-priority = 100
EOF
  put /etc/sysctl.d/21-kwick-gaming-tweaks.conf <<'EOF'
vm.swappiness = 100
vm.page-cluster = 0
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 1024
EOF
  put /etc/modules-load.d/kwick-gaming-tweaks.conf <<'EOF'
zram
ntsync
EOF
  put /etc/udev/rules.d/60-kwick-ntsync.rules <<'EOF'
KERNEL=="ntsync", MODE="0660", TAG+="uaccess"
EOF
  put /etc/udev/rules.d/60-kwick-ioscheduler.rules <<'EOF'
ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="sd[a-z]*|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
EOF
  load_modules zram ntsync
  sysctl_apply
  reload_udev
  svc_enable earlyoom.service
  if [ -d /sys/kernel/sched_ext ]; then
    warn "sched_ext is present; install an scx scheduler yourself (none is packaged in Debian 13)"
  else
    say "This kernel has no sched_ext, so the scx_lavd/scx_bpfland schedulers Bazzite offers are not available."
  fi
  [ -e /dev/ntsync ] || say "ntsync: /dev/ntsync is missing; the running kernel lacks the ntsync module (needs Linux 6.14 or newer built with CONFIG_NTSYNC)."
  say "zram swap is created by systemd at the next boot (or: systemctl daemon-reload && systemctl start systemd-zram-setup@zram0)."
  return 0
}

tweaks_remove() {
  rm -f /etc/systemd/zram-generator.conf.d/kwick-gaming.conf /etc/sysctl.d/21-kwick-gaming-tweaks.conf /etc/modules-load.d/kwick-gaming-tweaks.conf /etc/udev/rules.d/60-kwick-ntsync.rules /etc/udev/rules.d/60-kwick-ioscheduler.rules
  svc_disable earlyoom.service
  apt_remove earlyoom systemd-zram-generator
  sysctl_apply
  reload_udev
  return 0
}
