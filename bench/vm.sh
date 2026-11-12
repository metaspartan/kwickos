#!/bin/bash
# VM benchmarks under identical QEMU/KVM settings (run inside kwick-builder
# with --device /dev/kvm). Boots each system, logs in on the serial console
# exactly like a user would, and records:
#   - wall time from QEMU start to the login shell prompt
#   - guest uptime at that moment (kernel + userspace boot time)
#   - memory in use (MemTotal - MemAvailable) and process count
#   bench/vm.sh [runs=5]
set -uo pipefail
RUNS=${1:-5}
OUT=${OUT:-/out}; D="$OUT/amd64"
ALP_VER=${ALP_VER:-3.24.4}
CACHE=${CACHE:-/cache}; mkdir -p "$CACHE"
ISO="$CACHE/alpine-virt-$ALP_VER-x86_64.iso"
if [ ! -f "$ISO" ]; then
  curl -fsSL -o "$ISO" "https://dl-cdn.alpinelinux.org/alpine/v${ALP_VER%.*}/releases/x86_64/alpine-virt-$ALP_VER-x86_64.iso"
fi
A=$(mktemp -d); xorriso -osirrox on -indev "$ISO" -extract /boot "$A" >/dev/null 2>&1
MEM=${MEM:-512}
BASE=(qemu-system-x86_64 -M q35,accel=kvm -cpu host -m $MEM -smp 2 -nographic -no-reboot -monitor none
      -nic user,model=virtio-net-pci)
MICRO=(qemu-system-x86_64 -M microvm,accel=kvm,isa-serial=on,rtc=on -cpu host -m $MEM -smp 2 -nodefaults -no-user-config
      -nographic -no-reboot -netdev user,id=n0 -device virtio-net-device,netdev=n0)
cd_dev() { echo -drive file="$1",media=cdrom,if=none,id=cd,readonly=on -device virtio-scsi-pci -device scsi-cd,drive=cd; }

MEASURE='echo __U=$(cut -d" " -f1 /proc/uptime); awk "/MemTotal/{t=\$2}/MemAvailable/{a=\$2}END{print \"__M=\" t-a}" /proc/meminfo; echo __P=$(ls -d /proc/[0-9]* | wc -l); poweroff'

# run_login <name> <prompt-regex> <login-user-or-empty> qemu args...
run_login() {
  local name=$1 prompt=$2 user=$3; shift 3
  local log=$(mktemp) fifo=$(mktemp -u); mkfifo "$fifo"
  exec 3<>"$fifo"
  local t0=$(date +%s%N)
  "$@" -serial stdio <&3 >"$log" 2>&1 &
  local pid=$! t1="" end=$(( $(date +%s) + 90 ))
  while kill -0 $pid 2>/dev/null && [ $(date +%s) -lt $end ]; do
    if [ -z "$t1" ] && grep -aqE "$prompt" "$log"; then
      t1=$(date +%s%N)
      if [ -n "$user" ]; then echo "$user" >&3; sleep 1.5; fi
      echo "$MEASURE" >&3
    fi
    sleep 0.02
  done
  kill $pid 2>/dev/null; wait $pid 2>/dev/null; exec 3>&-; rm -f "$fifo"
  local u=$(grep -ao '__U=[0-9.]*' "$log" | head -1 | cut -d= -f2)
  local m=$(grep -ao '__M=[0-9]*' "$log" | head -1 | cut -d= -f2)
  local p=$(grep -ao '__P=[0-9]*' "$log" | head -1 | cut -d= -f2)
  # the login step waits 1.5 s before measuring: don't count it
  [ -n "$user" ] && [ -n "$u" ] && u=$(echo "$u - 1.5" | bc)
  echo "$name ${t1:+$(( (t1-t0)/1000000 ))} ${u:-?} ${m:-?} ${p:-?}"
  rm -f "$log"
}

results=$(mktemp)
for i in $(seq "$RUNS"); do
  # KwickOS: RAM boot on QEMU microvm (agent-sandbox path)
  run_login "kwickos-microvm-ram" '# $' "" "${MICRO[@]}" -kernel "$D/kernel-virt/vmlinuz" \
      -initrd "$D/kwickos-amd64-initramfs.cpio.zst" -append "console=ttyS0 reboot=t" >>"$results"
  # KwickOS: live ISO root (erofs + overlay), same method as Alpine below
  run_login "kwickos-q35-live" '# $' "" "${BASE[@]}" -kernel "$D/kernel-virt/vmlinuz" -append "console=ttyS0" \
      $(cd_dev "$D/kwickos-amd64.iso") >>"$results"
  # KwickOS: installed on a virtio disk (ext4)
  cp --sparse=always "$D/kwickos-amd64.img" /tmp/k.img
  run_login "kwickos-q35-disk" '# $' "" "${BASE[@]}" -kernel "$D/kernel-virt/vmlinuz" -append "console=ttyS0" \
      -drive file=/tmp/k.img,if=virtio,format=raw >>"$results"
  # Alpine virt: live ISO root, kernel+initramfs from the ISO
  run_login "alpine-$ALP_VER-q35-live" 'login: *$' "root" "${BASE[@]}" -kernel "$A/vmlinuz-virt" -initrd "$A/initramfs-virt" \
      -append "console=ttyS0 modules=loop,squashfs,sd-mod,sr-mod,virtio_scsi alpine_dev=cdrom:iso9660 quiet" \
      $(cd_dev "$ISO") >>"$results"
done
rm -f /tmp/k.img
echo "## Boot to login shell + memory (QEMU/KVM, 2 vCPU, ${MEM} MiB, median of $RUNS)"
echo
echo "| system | QEMU start -> shell prompt | guest uptime at shell | memory in use | processes |"
echo "|---|---|---|---|---|"
for n in $(cut -d' ' -f1 "$results" | sort -u); do
  med() { grep "^$n " "$results" | awk -v c=$1 '{print $c}' | grep -v '?' | sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}'; }
  printf '| %s | %s ms | %s s | %s MiB | %s |\n' "$n" "$(med 2)" "$(med 3)" "$(med 4 | awk '{printf "%.1f", $1/1024}')" "$(med 5)"
done
rm -rf "$A" "$results"
