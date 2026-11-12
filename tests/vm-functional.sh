#!/bin/bash
# End-to-end test inside a booted KwickOS VM (amd64, KVM):
#   networking -> apt install -> maintainer scripts enable+start the systemd
#   unit via kinit -> systemctl/journalctl -> HTTP request -> crash restart.
# The test script is passed over 9p; results come back on the serial console.
set -uo pipefail
OUT=${OUT:-/out}; D="$OUT/amd64"
W=$(mktemp -d)
cat > "$W/t.sh" <<'EOF'
set -x
ip -4 addr show eth0 | grep inet
cat /etc/resolv.conf
apt update
apt install -y nginx curl
systemctl is-enabled nginx
systemctl is-active nginx
systemctl status nginx | head -5
curl -sS -o /dev/null -w 'HTTP %{http_code}\n' http://127.0.0.1/
# crash recovery for Restart= units
cat > /etc/systemd/system/demo.service <<'U'
[Unit]
Description=demo crash-looping service
[Service]
ExecStart=/bin/sh -c 'echo started; sleep 1; exit 3'
Restart=always
[Install]
WantedBy=multi-user.target
U
systemctl daemon-reload
systemctl enable --now demo
sleep 4
journalctl -u demo -n 5
starts=$(grep -c started /var/log/kinit/demo.service.log)
echo "demo restarts: $starts"
[ "$starts" -ge 2 ] && echo DEMO_RESTART_OK
systemctl stop demo
echo "mem: $(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{print (t-a)/1024 " MiB used"}' /proc/meminfo)"
echo FUNCTIONAL_DONE
EOF
cp --sparse=always "$D/kwickos-amd64.img" "$W/disk.img"
timeout 600 qemu-system-x86_64 -M q35,accel=kvm -cpu host -m 1024 -smp 2 -nographic -no-reboot -monitor none -serial stdio \
  -kernel "$D/kernel-virt/vmlinuz" -drive file="$W/disk.img",if=virtio,format=raw \
  -nic user,model=virtio-net-pci -virtfs local,path="$W",mount_tag=t,security_model=none,readonly=on \
  -append "console=ttyS0 kwick.run=sleep+2;mkdir+-p+/mnt/t;mount+-t+9p+-o+trans=virtio+t+/mnt/t;sh+/mnt/t/t.sh;poweroff" \
  </dev/null 2>&1 | tr -d '\r' | tee "$W/log" | grep -E '^\+ |HTTP|active|enabled|restarts|RESTART_OK|mem:|FUNCTIONAL|ready in|Loaded|Active|inet |nameserver|E:' | head -60
ok=1
grep -q 'HTTP 200' "$W/log" || { echo "FAIL: nginx did not answer"; ok=0; }
grep -q '^enabled' "$W/log" || { echo "FAIL: nginx not enabled"; ok=0; }
grep -q 'DEMO_RESTART_OK' "$W/log" || { echo "FAIL: Restart=always"; ok=0; }
rm -rf "$W"
[ $ok = 1 ] && echo "VM FUNCTIONAL TEST: PASS" || { echo "VM FUNCTIONAL TEST: FAIL"; exit 1; }
