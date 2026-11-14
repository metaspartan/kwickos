SMARTD_CONF=/etc/smartd.conf
HDIDLE_CONF=/etc/default/hd-idle

smart_arch() { echo any; }
smart_desc() { echo "SMART monitoring with smartd (log or email), drive temperatures, hdparm and hd-idle spindown"; }

smart_state() { pkgs_state smartmontools hdparm hd-idle; }

smartd_write() {
  mail=${1:-}
  line="DEVICESCAN -a -o on -S on -n standby,q -s (S/../.././02|L/../../6/03) -W 4,45,55"
  [ -n "$mail" ] && line="$line -m $mail -M exec /usr/share/smartmontools/smartd-runner"
  echo "$line" > "$SMARTD_CONF"
  if [ -n "$mail" ]; then echo "$mail" > "$CONF_DIR/smart-mail"; else rm -f "$CONF_DIR/smart-mail"; fi
}

smart_install() {
  apt_get smartmontools hdparm hd-idle || return 1
  mkdir -p "$CONF_DIR"
  smartd_write "$(cat "$CONF_DIR/smart-mail" 2>/dev/null)"
  load_modules drivetemp
  put /etc/modules-load.d/kwick-storage-drivetemp.conf <<EOF
drivetemp
EOF
  svc_enable smartd
  say "smartd checks every disk, runs a short self-test daily and a long one on Saturdays, and logs to the journal."
  say "Email alerts: $PROG smart email <address> (needs a mail transport such as msmtp-mta). Spindown: $PROG smart spindown <minutes>|off"
  return 0
}

smart_remove() {
  svc_disable smartd hd-idle
  rm -f /etc/modules-load.d/kwick-storage-drivetemp.conf
  apt_remove hd-idle smartmontools
  return 0
}

smart_spindown() {
  v=${1:?usage: $PROG smart spindown <minutes>|off}
  pkg_installed hd-idle || apt_get hd-idle || die "hd-idle could not be installed"
  if [ "$v" = off ]; then
    printf 'START_HD_IDLE=false\nHD_IDLE_OPTS="-i 0"\n' > "$HDIDLE_CONF"
    svc_disable hd-idle
    say "spindown off"
    return 0
  fi
  printf '%s' "$v" | grep -Eq '^[0-9]+$' || die "give the idle time in minutes"
  [ "$v" -ge 5 ] || die "give at least 5 minutes"
  opts="-i 0"
  for d in /sys/block/sd* /sys/block/hd*; do
    [ -e "$d/queue/rotational" ] || continue
    [ "$(cat "$d/queue/rotational")" = 1 ] || continue
    opts="$opts -a ${d##*/} -i $((v * 60))"
  done
  [ "$opts" != "-i 0" ] || die "no spinning disks found"
  printf 'START_HD_IDLE=true\nHD_IDLE_OPTS="%s"\n' "$opts" > "$HDIDLE_CONF"
  svc_enable hd-idle
  svc_restart hd-idle
  say "spinning disks stop after $v minutes idle"
}

cmd_smart() {
  sub=${1:-status}
  [ $# -gt 0 ] && shift
  case $sub in
    status)
      have smartctl || die "smartmontools is not installed: $PROG install smart"
      for d in /sys/block/*; do
        n=${d##*/}
        case $n in loop* | ram* | zram* | dm-* | md* | sr* | nbd*) continue ;; esac
        h=$(smartctl -H "/dev/$n" 2>/dev/null | sed -n 's/.*\(PASSED\|FAILED\|OK\).*/\1/p' | head -n 1)
        t=$(cat "$d"/device/hwmon/hwmon*/temp1_input 2>/dev/null | head -n 1)
        [ -n "$t" ] && t="$((t / 1000))C"
        printf '%-10s %-8s %s\n' "$n" "${h:-n/a}" "$t"
      done
      ;;
    email) need_root smart email "$@"; mkdir -p "$CONF_DIR"; smartd_write "${1:?usage: $PROG smart email <address>}"; svc_restart smartd; say "smartd mails $1 on failures" ;;
    log) need_root smart log; mkdir -p "$CONF_DIR"; smartd_write ""; svc_restart smartd; say "smartd logs to the journal only" ;;
    spindown) need_root smart spindown "$@"; smart_spindown "$@" ;;
    *) die "usage: $PROG smart status|email <address>|log|spindown <minutes>|off" ;;
  esac
}
