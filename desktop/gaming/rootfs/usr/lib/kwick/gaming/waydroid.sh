waydroid_arch() { echo any; }
waydroid_desc() { echo "Waydroid: Android apps in a container (needs binder kernel support and the upstream package)"; }

waydroid_binder() {
  grep -qw binder /proc/filesystems 2>/dev/null || [ -d /dev/binderfs ] || modinfo binder_linux >/dev/null 2>&1
}

waydroid_state() {
  if command -v waydroid >/dev/null 2>&1; then echo yes; return 0; fi
  if waydroid_binder; then echo no; else echo na; fi
}

waydroid_why() { echo "the running kernel has no binder (Android IPC) support"; }

waydroid_install() {
  if ! waydroid_binder; then
    warn "Waydroid needs the kernel binder driver (CONFIG_ANDROID_BINDER_IPC and binderfs); this kernel has none"
    return 1
  fi
  apt_get lxc nftables dnsmasq-base iproute2 wl-clipboard || return 1
  if apt_have_candidate waydroid; then
    apt_get waydroid || return 1
    say "Run 'sudo waydroid init' once, then start the session with 'waydroid session start'."
    return 0
  fi
  warn "Debian 13 has no waydroid package. The prerequisites are installed; add the upstream repository from https://docs.waydro.id and run: apt install waydroid"
  return 1
}

waydroid_remove() {
  apt_remove waydroid
  return 0
}
