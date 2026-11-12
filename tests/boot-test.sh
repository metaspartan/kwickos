#!/bin/bash
# Boot KwickOS under QEMU and verify it reaches "ready" and powers off.
#   boot-test.sh <arch> <mode> [extra kwick.run command]
# modes: direct (kernel + GPT disk, auto root discovery)
#        efi    (UEFI firmware -> ESP -> kernel EFI stub, no bootloader)
#        iso    (UEFI live ISO, erofs + overlay)
#        ram    (kernel + whole-OS initramfs, no disk)
#        microvm (amd64: QEMU microvm machine, RAM boot)
# Prints: wall-clock ms from QEMU start to exit, and guest-reported ready ms.
set -uo pipefail
ARCH=${1:?arch}; MODE=${2:?mode}; RUN=${3:-}
OUT=${OUT:-/out}; D="$OUT/$ARCH"; K="$D/kernel-${FLAVOR:-virt}"
MEM=${MEM:-512}; SMP=${SMP:-2}; TIMEOUT=${TIMEOUT:-120}
LOG=$(mktemp); W=$(mktemp -d)
ACCEL=tcg; [ -w /dev/kvm ] && [ "$ARCH" = "$(dpkg --print-architecture)" ] && ACCEL=kvm
CMD="poweroff"; [ -n "$RUN" ] && CMD="$RUN;poweroff"
CMDLINE="kwick.run=$(echo "$CMD" | tr ' ' '+')"

case $ARCH in
  amd64)
    Q=(qemu-system-x86_64 -M q35,accel=$ACCEL -m $MEM -smp $SMP)
    [ $ACCEL = kvm ] && Q+=(-cpu host) || Q+=(-cpu max)
    FW_CODE=/usr/share/OVMF/OVMF_CODE_4M.fd; FW_VARS=/usr/share/OVMF/OVMF_VARS_4M.fd; CON=ttyS0 ;;
  arm64)
    Q=(qemu-system-aarch64 -M virt,accel=$ACCEL -m $MEM -smp $SMP)
    [ $ACCEL = kvm ] && Q+=(-cpu host) || Q+=(-cpu max)
    FW_CODE=/usr/share/AAVMF/AAVMF_CODE.fd; FW_VARS=/usr/share/AAVMF/AAVMF_VARS.fd; CON=ttyAMA0 ;;
  riscv64)
    Q=(qemu-system-riscv64 -M virt,accel=$ACCEL -m $MEM -smp $SMP -cpu rv64)
    FW_CODE=; CON=ttyS0 ;;
esac
Q+=(-nographic -no-reboot -nic user,model=virtio-net-pci -serial mon:stdio -monitor none)
Q=("${Q[@]/-serial/-serial}")
KIMG="$K/vmlinuz"; [ "$ARCH" != amd64 ] && [ -f "$K/vmlinuz" ] && KIMG="$K/vmlinuz"
case $MODE in
  direct)
    cp --sparse=always "$D/kwickos-$ARCH.img" "$W/disk.img"
    Q+=(-kernel "$KIMG" -append "console=$CON $CMDLINE" -drive file="$W/disk.img",if=virtio,format=raw) ;;
  ram)
    Q+=(-kernel "$KIMG" -initrd "$D/kwickos-$ARCH-initramfs.cpio.zst" -append "console=$CON $CMDLINE") ;;
  microvm)
    Q=(qemu-system-x86_64 -M microvm,accel=$ACCEL,x-option-roms=off,isa-serial=on,rtc=on -cpu host -m $MEM -smp $SMP -nodefaults -no-user-config
       -nographic -no-reboot -serial mon:stdio -kernel "$K/vmlinuz" -initrd "$D/kwickos-$ARCH-initramfs.cpio.zst"
       -append "console=ttyS0 reboot=t $CMDLINE"
       -netdev user,id=n0 -device virtio-net-device,netdev=n0) ;;
  efi|iso)
    cp "$FW_VARS" "$W/vars.fd"
    Q+=(-drive if=pflash,format=raw,readonly=on,file="$FW_CODE" -drive if=pflash,format=raw,file="$W/vars.fd")
    if [ $MODE = efi ]; then
      cp --sparse=always "$D/kwickos-$ARCH.img" "$W/disk.img"
      Q+=(-drive file="$W/disk.img",if=virtio,format=raw)
    else
      Q+=(-drive file="$D/kwickos-$ARCH.iso",media=cdrom,if=none,id=cd -device virtio-scsi-pci -device scsi-cd,drive=cd)
    fi ;;
esac

t0=$(date +%s%N)
"${Q[@]}" </dev/null >"$LOG" 2>&1 &
QPID=$!
ready=""
deadline=$(( $(date +%s) + TIMEOUT ))
while kill -0 $QPID 2>/dev/null; do
  if [ -z "$ready" ]; then
    ready=$(grep -ao 'ready in [0-9]* ms' "$LOG" 2>/dev/null | grep -o '[0-9]*' | head -1)
    t_ready=$(date +%s%N)
    # EFI/ISO boots have no kernel cmdline (no kwick.run=poweroff): stop here.
    if [ -n "$ready" ] && { [ $MODE = efi ] || [ $MODE = iso ]; }; then sleep 1; kill $QPID; break; fi
  fi
  [ "$(date +%s)" -ge $deadline ] && { kill $QPID; break; }
  sleep 0.05
done
wait $QPID; rc=$?
t1=$(date +%s%N)
wall=$(( (t1 - t0) / 1000000 ))
[ -n "$ready" ] || ready=$(grep -ao 'ready in [0-9]* ms' "$LOG" | grep -o '[0-9]*' | head -1)
echo "---- serial log ($ARCH/$MODE) ----"; tr -d '\r' < "$LOG" | grep -av '^$' | tail -${TAIL:-25}
if [ -n "$ready" ]; then
  echo "RESULT arch=$ARCH mode=$MODE accel=$ACCEL ok wall_ms=$wall guest_ready_ms=$ready qemu_rc=$rc"
  rm -rf "$W" "$LOG"; exit 0
fi
echo "RESULT arch=$ARCH mode=$MODE accel=$ACCEL FAIL wall_ms=$wall qemu_rc=$rc"
rm -rf "$W" "$LOG"; exit 1
