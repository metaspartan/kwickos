#!/bin/bash
set -euo pipefail
NAME=${1:?name}
W=${W:-/vm}
D=$W/$NAME
mkdir -p "$D"
RAM=${RAM:-6144}
SMP=${SMP:-6}
BIOS=${BIOS:-uefi}
GPU=${GPU:-virgl}
DISP=${DISP:-9}
XRES=${XRES:-1600}
YRES=${YRES:-900}
SSHPORT=${SSHPORT:-2222}
case $GPU in
  virgl)
    if [ ! -S "/tmp/.X11-unix/X$DISP" ]; then
      setsid Xvfb ":$DISP" -screen 0 "${XRES}x${YRES}x24" +extension GLX >/tmp/xvfb-$DISP.log 2>&1 </dev/null &
      for i in $(seq 50); do [ -S "/tmp/.X11-unix/X$DISP" ] && break; sleep 0.2; done
    fi
    export DISPLAY=":$DISP"
    VGA="-device virtio-vga-gl,xres=$XRES,yres=$YRES -display sdl,gl=on"
    ;;
  none) VGA="-device virtio-vga,xres=$XRES,yres=$YRES -display none" ;;
esac
FW=""
if [ "$BIOS" = uefi ]; then
  [ -f "$D/OVMF_VARS.fd" ] || cp /usr/share/OVMF/OVMF_VARS_4M.fd "$D/OVMF_VARS.fd"
  FW="-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd -drive if=pflash,format=raw,file=$D/OVMF_VARS.fd"
fi
EXTRA=${EXTRA:-}
exec qemu-system-x86_64 -name "$NAME" -M q35,accel=kvm -cpu host -m "$RAM" -smp "$SMP" \
  $FW $VGA ${DISK:+-drive file=$DISK,if=none,id=d0,format=${DISKFMT:-qcow2} -device virtio-blk-pci,drive=d0,bootindex=2} \
  ${CDROM:+-drive file=$CDROM,if=none,id=cd0,media=cdrom,readonly=on -device ide-cd,drive=cd0,bootindex=1} \
  -nic user,model=virtio-net-pci,hostfwd=tcp::$SSHPORT-:22 \
  -device qemu-xhci -device usb-kbd -device usb-tablet \
  -qmp unix:$D/qmp.sock,server=on,wait=off -chardev socket,id=ser0,path=$D/ser.sock,server=on,wait=off,logfile=$D/serial.log -serial chardev:ser0 -monitor none \
  -object rng-random,filename=/dev/urandom,id=rng0 -device virtio-rng-pci,rng=rng0 $EXTRA
