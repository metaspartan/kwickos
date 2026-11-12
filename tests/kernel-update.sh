#!/bin/bash
# End-to-end kernel update through apt (amd64, KVM, UEFI):
#   1. package kernel-generic as linux-image-kwick-generic, build a signed repo
#   2. UEFI-boot the disk (virt kernel on the ESP), add the repo, apt install
#   3. UEFI-boot again: the system must now run the generic kernel
#      (virt has CONFIG_MODULES=n, generic CONFIG_MODULES=y), with the previous
#      kernel kept for rollback.
set -uo pipefail
OUT=${OUT:-/out}; D="$OUT/amd64"; SRC=${SRC:-/src}
W=$(mktemp -d)
rm -rf "$OUT/repo"
bash "$SRC/scripts/mkkernelpkg.sh" amd64 generic
bash "$SRC/scripts/mkrepo.sh" stable >/dev/null
cp "$OUT/repo/kwickos-archive-keyring.asc" "$W/"
( cd "$OUT/repo" && python3 -m http.server 8080 >/dev/null 2>&1 ) & HTTP=$!
cp --sparse=always "$D/kwickos-amd64.img" "$W/disk.img"
cp /usr/share/OVMF/OVMF_VARS_4M.fd "$W/vars.fd"
cat > "$W/t.sh" <<'EOF'
mkdir -p /usr/share/keyrings && cp /mnt/t/kwickos-archive-keyring.asc /usr/share/keyrings/
printf 'Types: deb\nURIs: http://10.0.2.2:8080\nSuites: stable\nComponents: main\nSigned-By: /usr/share/keyrings/kwickos-archive-keyring.asc\n' > /etc/apt/sources.list.d/kwickos.sources
apt update 2>&1 | grep -E 'kwick|10.0.2.2|E:'
apt install -y linux-image-kwick-generic 2>&1 | grep -E 'Setting up|kwick-kernel-install|E:'
ls /boot/efi/EFI/BOOT /boot/efi/EFI/kwick
echo "current: $(cat /boot/efi/EFI/kwick/current)"
EOF
boot() { # $1 = commands to type at the shell
  local log=$W/log.$2 fifo=$W/fifo; rm -f "$fifo"; mkfifo "$fifo"; exec 3<>"$fifo"
  qemu-system-x86_64 -M q35,accel=kvm -cpu host -m 1024 -smp 2 -nographic -no-reboot -monitor none -serial stdio \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd -drive if=pflash,format=raw,file="$W/vars.fd" \
    -drive file="$W/disk.img",if=virtio,format=raw -nic user,model=virtio-net-pci \
    -virtfs local,path="$W",mount_tag=t,security_model=none,readonly=on <&3 >"$log" 2>&1 &
  local pid=$! sent=0 end=$(( $(date +%s) + 240 ))
  while kill -0 $pid 2>/dev/null && [ $(date +%s) -lt $end ]; do
    if [ $sent = 0 ] && grep -aq '# $' "$log"; then echo "$1" >&3; sent=1; fi
    sleep 0.2
  done
  kill $pid 2>/dev/null; wait $pid 2>/dev/null; exec 3>&-
  if [ -n "${DEBUG:-}" ]; then tr -d '\r' < "$log" | tail -60; else
  tr -d '\r' < "$log" | grep -avE '^\s*$' | grep -aE 'kinit|Setting up|kwick|current|BOOT|previous|MODULES|Linux version|E:' | tail -15; fi
}
echo "=== boot 1: virt kernel from ESP, install generic kernel via apt"
boot 'mkdir -p /mnt/t; mount -t 9p -o trans=virtio t /mnt/t; sh /mnt/t/t.sh; zcat /proc/config.gz | grep -c "^CONFIG_MODULES=y" | sed "s/^/MODULES=/"; poweroff' 1
echo "=== boot 2: firmware loads the newly installed kernel"
boot 'zcat /proc/config.gz | grep -c "^CONFIG_MODULES=y" | sed "s/^/MODULES=/"; ls /boot/efi/EFI/kwick 2>/dev/null || (mkdir -p /boot/efi && mount -t vfat /dev/vda1 /boot/efi && ls /boot/efi/EFI/kwick); poweroff' 2
kill $HTTP 2>/dev/null
ok=1
grep -aq 'MODULES=0' "$W/log.1" || { echo "FAIL: first boot was not the virt kernel"; ok=0; }
grep -aq 'MODULES=1' "$W/log.2" || { echo "FAIL: second boot did not run the updated kernel"; ok=0; }
grep -aq 'previous.efi' "$W/log.2" || grep -aq 'previous.efi' "$W/log.1" || { echo "FAIL: no rollback kernel kept"; ok=0; }
rm -rf "$W"
[ $ok = 1 ] && echo "KERNEL UPDATE TEST: PASS" || { echo "KERNEL UPDATE TEST: FAIL"; exit 1; }
