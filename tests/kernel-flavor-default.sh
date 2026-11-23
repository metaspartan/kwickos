#!/bin/sh
KK=${1:-$(cd "$(dirname "$0")/.." && pwd)/rootfs/usr/sbin/kwick-kernel}
[ "$(id -u)" = 0 ] || { echo "run as root in a throwaway privileged container (it mounts a tmpfs as the ESP)"; exit 2; }
fail=0
ok() { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }

run_case() {
	name=$1; shift
	T=$(mktemp -d)
	mkdir -p "$T/kernels" "$T/store" "$T/state" "$T/esp" "$T/modules"
	mount -t tmpfs tmpfs "$T/esp" || { echo "cannot mount a tmpfs"; exit 2; }
	export KWICK_KDIR="$T/kernels" KWICK_KSTORE="$T/store" KWICK_KSTATE="$T/state" KWICK_ESP="$T/esp" KWICK_MDIR="$T/modules"
	export KWICK_BOOT_PATH=efistub KWICK_KEEPFLAG="$T/keep" KWICK_KCONF="$T/kernel.conf" KWICK_ICONF="$T/install.conf" KWICK_RUNNING_REL=7.3.5-kwick
	mk() { mkdir -p "$T/kernels/$1"; echo "$1" >"$T/kernels/$1/vmlinuz.efi"; echo "$2" >"$T/kernels/$1/flavor"; }
	reg() { sh "$KK" _register "$1" >/dev/null 2>&1; }
	"$@"
	got=$(cat "$T/state/default" 2>/dev/null)
	umount "$T/esp"
	rm -rf "$T"
	[ "$got" = "$want" ] && ok "$name: default is $got" || bad "$name: default is '${got:-none}', expected $want"
}

desktop_on_headless() {
	mk 7.3.5-kwick-virt virt; reg 7.3.5-kwick-virt
	mk 7.3.5-kwick generic; reg 7.3.5-kwick
	want=generic-7.3.5
}

upgrade_generic_first() {
	desktop_on_headless
	rm -rf "$T/kernels/7.3.5-kwick" "$T/kernels/7.3.5-kwick-virt"
	mk 7.3.6-kwick generic; reg 7.3.6-kwick
	mk 7.3.6-kwick-virt virt; reg 7.3.6-kwick-virt
	want=generic-7.3.6
}

upgrade_virt_first() {
	desktop_on_headless
	rm -rf "$T/kernels/7.3.5-kwick" "$T/kernels/7.3.5-kwick-virt"
	mk 7.3.6-kwick-virt virt; reg 7.3.6-kwick-virt
	mk 7.3.6-kwick generic; reg 7.3.6-kwick
	want=generic-7.3.6
}

headless_upgrade() {
	mk 7.3.5-kwick-virt virt; reg 7.3.5-kwick-virt
	rm -rf "$T/kernels/7.3.5-kwick-virt"
	mk 7.3.6-kwick-virt virt; reg 7.3.6-kwick-virt
	want=virt-7.3.6
}

run_case "installing the desktop on headless switches to the generic flavor" desktop_on_headless
run_case "upgrading both flavors keeps the generic default (generic configured first)" upgrade_generic_first
run_case "upgrading both flavors keeps the generic default (virt configured first)" upgrade_virt_first
run_case "a headless upgrade moves to the new virt kernel" headless_upgrade
exit $fail
