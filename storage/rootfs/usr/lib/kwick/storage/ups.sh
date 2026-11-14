ups_arch() { echo any; }
ups_desc() { echo "Network UPS Tools: detect a USB UPS and shut down cleanly on low battery"; }

ups_state() {
  s=$(pkgs_state nut-server nut-client)
  [ "$s" = yes ] && [ ! -s /etc/nut/ups.conf ] && s=part
  echo "$s"
}

ups_install() {
  apt_get nut-server nut-client || return 1
  ups_setup || warn "no UPS detected yet; plug it in and run: $PROG ups setup"
  return 0
}

ups_remove() {
  svc_disable nut-monitor nut-server nut-driver.target
  apt_remove nut-server nut-client nut
  return 0
}

ups_setup() {
  have nut-scanner || return 1
  scan=$(nut-scanner -U -q 2>/dev/null)
  drv=$(echo "$scan" | sed -n 's/^[[:space:]]*driver = "\{0,1\}\([^"]*\)"\{0,1\}/\1/p' | head -n 1)
  [ -n "$drv" ] || return 1
  port=$(echo "$scan" | sed -n 's/^[[:space:]]*port = "\{0,1\}\([^"]*\)"\{0,1\}/\1/p' | head -n 1)
  vid=$(echo "$scan" | sed -n 's/^[[:space:]]*vendorid = "\{0,1\}\([^"]*\)"\{0,1\}/\1/p' | head -n 1)
  pid=$(echo "$scan" | sed -n 's/^[[:space:]]*productid = "\{0,1\}\([^"]*\)"\{0,1\}/\1/p' | head -n 1)
  pw=$(head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 20)
  printf 'MODE=standalone\n' > /etc/nut/nut.conf
  {
    printf '[ups]\n\tdriver = %s\n\tport = %s\n' "$drv" "${port:-auto}"
    [ -n "$vid" ] && printf '\tvendorid = %s\n' "$vid"
    [ -n "$pid" ] && printf '\tproductid = %s\n' "$pid"
    printf '\tdesc = "KwickOS UPS"\n'
  } > /etc/nut/ups.conf
  printf 'LISTEN 127.0.0.1 3493\nLISTEN ::1 3493\n' > /etc/nut/upsd.conf
  printf '[kwickmon]\n\tpassword = %s\n\tupsmon primary\n' "$pw" > /etc/nut/upsd.users
  printf 'MONITOR ups@localhost 1 kwickmon %s primary\nMINSUPPLIES 1\nSHUTDOWNCMD "/sbin/shutdown -h +0"\nPOWERDOWNFLAG /etc/killpower\n' "$pw" > /etc/nut/upsmon.conf
  chown root:nut /etc/nut/upsd.users /etc/nut/upsmon.conf 2>/dev/null
  chmod 640 /etc/nut/upsd.users /etc/nut/upsmon.conf
  svc_enable nut-driver.target nut-server nut-monitor
  svc_restart nut-driver.target nut-server nut-monitor
  say "UPS found ($drv). Check it with: upsc ups@localhost"
}

cmd_ups() {
  case ${1:-status} in
    setup) need_root ups setup; ups_setup || die "no USB UPS found" ;;
    status) have upsc || die "NUT is not installed: $PROG install ups"; upsc ups@localhost 2>&1 | grep -E '^(battery\.charge|battery\.runtime|ups\.status|ups\.model|ups\.load):' ;;
    *) die "usage: $PROG ups setup|status" ;;
  esac
}
