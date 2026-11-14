vms_arch() { echo any; }
vms_desc() { echo "Virtual machines: QEMU/KVM with libvirt, UEFI firmware, virt-install, and virt-manager on the desktop"; }

vms_qemu() {
  case $ARCH in
    amd64) echo "qemu-system-x86 ovmf" ;;
    arm64) echo "qemu-system-arm qemu-efi-aarch64" ;;
    riscv64) echo "qemu-system-misc opensbi u-boot-qemu" ;;
    *) echo qemu-system ;;
  esac
}

vms_state() {
  a=no; b=no
  pkg_installed libvirt-daemon-system && a=yes
  for p in $(vms_qemu); do pkg_installed "$p" && b=yes && break; done
  combine_state "$a" "$b"
}

is_desktop() {
  grep -qi desktop /etc/kwick-edition 2>/dev/null && return 0
  pkg_installed kwick-desktop
}

vms_install() {
  set -- libvirt-daemon-system libvirt-clients qemu-utils virtinst dnsmasq-base swtpm-tools
  for p in $(vms_qemu); do set -- "$@" "$p"; done
  is_desktop && set -- "$@" virt-manager
  apt_get "$@" || return 1
  load_modules kvm vhost_net tun bridge macvtap
  case $ARCH in amd64) grep -q vmx /proc/cpuinfo && load_modules kvm_intel; grep -q svm /proc/cpuinfo && load_modules kvm_amd ;; esac
  svc_enable libvirtd virtlogd
  virsh -c qemu:///system net-autostart default >/dev/null 2>&1
  virsh -c qemu:///system net-start default >/dev/null 2>&1
  u=$(target_user)
  [ -n "$u" ] && usermod -aG libvirt,kvm "$u" 2>/dev/null && say "$u can manage VMs after the next login"
  [ -e /dev/kvm ] || warn "/dev/kvm is missing: enable virtualization in the firmware for hardware acceleration"
  say "Create VMs in Cockpit (Virtual machines) or with virt-install$(is_desktop && echo ' or virt-manager')."
  return 0
}

vms_remove() {
  if have virsh && [ -n "$(virsh -c qemu:///system list --all --name 2>/dev/null | tr -d '\n')" ]; then
    warn "virtual machines are defined, libvirt stays installed"
    return 1
  fi
  apt_remove virt-manager virtinst libvirt-daemon-system
  return 0
}
