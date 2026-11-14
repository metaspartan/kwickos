iscsi_arch() { echo any; }
iscsi_desc() { echo "iSCSI target (LIO with targetcli-fb) to export zvols, LVs or image files as block devices"; }

iscsi_state() { pkgs_state targetcli-fb; }

iscsi_install() {
  apt_get targetcli-fb || return 1
  load_modules target_core_mod iscsi_target_mod target_core_iblock target_core_file
  for s in rtslib-fb-targetctl targetclid; do
    [ -f "/usr/lib/systemd/system/$s.service" ] && svc_enable "$s"
  done
  say "Configure targets with targetcli (saved to /etc/rtslib-fb-target/saveconfig.json)."
  return 0
}

iscsi_remove() {
  apt_remove targetcli-fb
  return 0
}
