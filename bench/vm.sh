#!/bin/bash
# Usage: bench/vm.sh [RUNS]
# Boots each system under QEMU/KVM (one VM at a time, 2 vCPU, 512 MiB) and logs in on the serial console.
# REL: a directory with the release files kwickos-amd64.iso, kwickos-amd64.efi and kwickos-amd64-initramfs.cpio.zst.
# Prints one raw line per run, then a median table. Keep the whole output in bench/results/.
set -uo pipefail
RUNS=${1:-5}
REL=${REL:-/rel}
ALP_VER=${ALP_VER:-3.24.4}
CACHE=${CACHE:-/cache}; mkdir -p "$CACHE"
MEM=${MEM:-512}
ISO="$CACHE/alpine-virt-$ALP_VER-x86_64.iso"
if [ ! -f "$ISO" ]; then
  curl -fsSL -o "$ISO" "https://dl-cdn.alpinelinux.org/alpine/v${ALP_VER%.*}/releases/x86_64/alpine-virt-$ALP_VER-x86_64.iso"
fi
A=$(mktemp -d); xorriso -osirrox on -indev "$ISO" -extract /boot "$A" >/dev/null 2>&1
K=$(mktemp -d); xorriso -osirrox on -indev "$REL/kwickos-amd64.iso" -extract /kwick/vmlinuz "$K/vmlinuz" >/dev/null 2>&1
if [ ! -s "$K/vmlinuz" ]; then
  xorriso -osirrox on -indev "$REL/kwickos-amd64.iso" -extract /kwick/root.erofs "$K/root.erofs" >/dev/null 2>&1
  KV=$(dump.erofs --ls --path=/usr/lib/kwick/kernels "$K/root.erofs" | awk '/FILENAME/ {f=1; next} f && $3 ~ /^[0-9]/ {print $3}' | sort -V | tail -1)
  dump.erofs --cat --path="/usr/lib/kwick/kernels/$KV/vmlinuz" "$K/root.erofs" > "$K/vmlinuz"
  rm -f "$K/root.erofs"
fi

echo "# bench/vm.sh $(date -u +%Y-%m-%dT%H:%MZ) runs=$RUNS mem=${MEM}MiB smp=2"
echo "# host: $(uname -r) $(nproc) threads; $(qemu-system-x86_64 --version | head -1)"
sha256sum "$REL/kwickos-amd64.iso" "$REL/kwickos-amd64.efi" "$REL/kwickos-amd64-initramfs.cpio.zst" "$ISO" | sed 's/^/# /'

QEMU=(nice -n 19 qemu-system-x86_64)
BASE=("${QEMU[@]}" -M q35,accel=kvm -cpu host -m "$MEM" -smp 2 -nographic -no-reboot -monitor none
      -nic user,model=virtio-net-pci)
MICRO=("${QEMU[@]}" -M microvm,accel=kvm,isa-serial=on,rtc=on -cpu host -m "$MEM" -smp 2 -nodefaults -no-user-config
      -nographic -no-reboot -netdev user,id=n0 -device virtio-net-device,netdev=n0)
cd_dev() { echo -drive file="$1",media=cdrom,if=none,id=cd,readonly=on -device virtio-scsi-pci -device scsi-cd,drive=cd; }

MEASURE='echo __U=$(cut -d" " -f1 /proc/uptime); awk "/MemTotal/{t=\$2}/MemAvailable/{a=\$2}/^Shmem:/{s=\$2}END{print \"__M=\" t-a \" __S=\" s}" /proc/meminfo; echo __P=$(for p in /proc/[0-9]*; do readlink $p/exe >/dev/null 2>&1 && echo x; done | wc -l); echo __K=$(uname -r); poweroff'

results=$(mktemp)
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
  local u=$(grep -ao '__U=[0-9][0-9.]*' "$log" | head -1 | cut -d= -f2)
  local m=$(grep -ao '__M=[0-9][0-9]*' "$log" | head -1 | cut -d= -f2)
  local s=$(grep -ao '__S=[0-9][0-9]*' "$log" | head -1 | cut -d= -f2)
  local p=$(grep -ao '__P=[0-9][0-9]*' "$log" | head -1 | cut -d= -f2)
  local k=$(grep -ao '__K=[0-9][^ ]*' "$log" | head -1 | cut -d= -f2 | tr -d '\r')
  [ -n "$user" ] && [ -n "$u" ] && u=$(echo "$u - 1.5" | bc)
  local line="$name ${t1:+$(( (t1-t0)/1000000 ))} ${u:-?} ${m:-?} ${s:-?} ${p:-?} ${k:-?}"
  echo "run $line"
  echo "$line" >>"$results"
  [ -z "$t1" ] && tail -c 1500 "$log"
  rm -f "$log"
}

echo "# columns: system wall_ms_to_prompt guest_uptime_s mem_in_use_KiB shmem_KiB user_processes kernel"
for i in $(seq "$RUNS"); do
  run_login "kwickos-iso-generic" '# $' "" "${BASE[@]}" -kernel "$K/vmlinuz" -append "console=ttyS0" \
      $(cd_dev "$REL/kwickos-amd64.iso")
  run_login "alpine-$ALP_VER-iso-virt" 'login: *$' "root" "${BASE[@]}" -kernel "$A/vmlinuz-virt" -initrd "$A/initramfs-virt" \
      -append "console=ttyS0 modules=loop,squashfs,sd-mod,sr-mod,virtio_scsi alpine_dev=cdrom:iso9660 quiet" \
      $(cd_dev "$ISO")
  run_login "kwickos-microvm-virt" '# $' "" "${MICRO[@]}" -kernel "$REL/kwickos-amd64.efi" \
      -initrd "$REL/kwickos-amd64-initramfs.cpio.zst" -append "console=ttyS0 reboot=t"
done

echo
echo "## Boot to login shell + memory (QEMU/KVM, 2 vCPU, ${MEM} MiB, $RUNS runs: median [min-max])"
echo
echo "| system | QEMU start -> shell prompt | guest uptime at shell | memory in use | of which shmem (RAM-resident files) | user processes |"
echo "|---|---|---|---|---|---|"
for n in $(cut -d' ' -f1 "$results" | sort -u); do
  col() { grep "^$n " "$results" | awk -v c=$1 '{print $c}' | grep -v '?' | sort -n; }
  st() { col $1 | awk -v d="$2" -v f="$3" '{a[NR]=$1/d} END {printf "%" f " [%" f "-%" f "]", a[int((NR+1)/2)], a[1], a[NR]}'; }
  printf '| %s | %s ms | %s s | %s MiB | %s MiB | %s |\n' "$n" "$(st 2 1 .0f)" "$(st 3 1 .2f)" "$(st 4 1024 .1f)" "$(st 5 1024 .1f)" "$(col 6 | sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}')"
done
rm -rf "$A" "$K" "$results"
