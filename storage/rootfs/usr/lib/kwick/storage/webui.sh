webui_arch() { echo any; }
webui_desc() { echo "Cockpit web console on port 9090 with storage, VMs, Podman, files and the 45Drives file-sharing and identities modules"; }

webui_state() {
  a=$(pkgs_state cockpit cockpit-storaged)
  b=$(pkgs_state cockpit-file-sharing cockpit-identities)
  combine_state "$a" "$b"
}

webui_install() {
  backports_ready
  apt_get_bpo cockpit cockpit-storaged cockpit-podman cockpit-files || apt_get cockpit cockpit-storaged cockpit-podman || return 1
  if pkg_installed libvirt-daemon-system; then apt_get_bpo cockpit-machines || apt_get cockpit-machines; fi
  rc=0
  deb_from_pin cockpit-file-sharing "$COCKPIT_FILE_SHARING_URL" "$COCKPIT_FILE_SHARING_SHA256" || rc=1
  deb_from_pin cockpit-identities "$COCKPIT_IDENTITIES_URL" "$COCKPIT_IDENTITIES_SHA256" || rc=1
  if systemd_running; then
    svc_enable cockpit.socket
  else
    webui_kinit || rc=1
  fi
  say "Cockpit: $(webui_url)"
  return $rc
}

webui_kinit() {
  apt_get stunnel4 openssl || return 1
  pem=$CONF_DIR/cockpit.pem
  mkdir -p "$CONF_DIR"
  if [ ! -s "$pem" ]; then
    t=$(mktemp -d)
    openssl req -x509 -newkey rsa:3072 -nodes -days 3650 -subj "/CN=$(hostname)" \
      -addext "subjectAltName=DNS:$(hostname),DNS:$(hostname).local,DNS:localhost,IP:127.0.0.1" \
      -keyout "$t/key" -out "$t/cert" >/dev/null 2>&1 || { rm -rf "$t"; return 1; }
    cat "$t/cert" "$t/key" > "$pem"
    rm -rf "$t"
    chmod 600 "$pem"
  fi
  put "$CONF_DIR/cockpit-tls.conf" <<EOF
foreground = yes
pid =
[cockpit]
accept = :::9090
connect = 127.0.0.1:9091
cert = $pem
EOF
  wsuser=""
  getent passwd cockpit-ws >/dev/null && wsuser="User=cockpit-ws"
  put /etc/systemd/system/kwick-cockpit-ws.service <<EOF
[Unit]
Description=Cockpit web service behind the kwick-storage TLS proxy
After=network.target

[Service]
ExecStart=/usr/lib/cockpit/cockpit-ws --for-tls-proxy --address 127.0.0.1 --port 9091
$wsuser
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  put /etc/systemd/system/kwick-cockpit-tls.service <<EOF
[Unit]
Description=TLS for Cockpit on port 9090
After=kwick-cockpit-ws.service

[Service]
ExecStart=$(command -v stunnel4 || echo /usr/bin/stunnel4) $CONF_DIR/cockpit-tls.conf
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  svc_enable kwick-cockpit-ws kwick-cockpit-tls
  return 0
}

webui_remove() {
  svc_disable cockpit.socket kwick-cockpit-tls kwick-cockpit-ws
  rm -f /etc/systemd/system/kwick-cockpit-ws.service /etc/systemd/system/kwick-cockpit-tls.service
  apt_remove stunnel4
  apt_remove cockpit-identities cockpit-file-sharing cockpit-files cockpit-machines cockpit-podman cockpit-storaged cockpit-ws cockpit-bridge cockpit
  return 0
}

webui_url() {
  ip=$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \([0-9.]*\).*/\1/p' | head -n 1)
  echo "https://${ip:-$(hostname)}:9090"
}
