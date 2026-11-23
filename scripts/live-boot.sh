uki_build() {
	local arch=$1 kernel=$2 out=$3 cmdline=$4 sfx stub dir end=0 idx name size vma rest e v1 v2 v3 v4
	case $arch in amd64) sfx=x64;; arm64) sfx=aa64;; riscv64) sfx=riscv64;; *) return 1;; esac
	stub=/usr/lib/systemd/boot/efi/linux$sfx.efi.stub
	[ -f "$stub" ] && command -v objcopy >/dev/null && command -v objdump >/dev/null || return 1
	dir=$(dirname "$out")
	printf '%s' "$cmdline" > "$dir/uki-cmdline.txt"
	while read -r idx name size vma rest; do
		[[ $idx =~ ^[0-9]+$ ]] || continue
		e=$((0x$vma + 0x$size))
		[ "$e" -gt "$end" ] && end=$e
	done < <(objdump -h "$stub")
	v1=$(( (end + 4095) / 4096 * 4096 ))
	v2=$(( (v1 + $(stat -c %s /usr/lib/os-release) + 4095) / 4096 * 4096 ))
	v3=$(( (v2 + $(stat -c %s "$dir/uki-cmdline.txt") + 4095) / 4096 * 4096 ))
	objcopy --add-section .osrel=/usr/lib/os-release --change-section-vma .osrel=$v1 \
	  --add-section .cmdline="$dir/uki-cmdline.txt" --change-section-vma .cmdline=$v2 \
	  --add-section .linux="$kernel" --change-section-vma .linux=$v3 "$stub" "$out"
}

live_erofs() {
	local cfg=$1 img=$2 dir=$3 z=(-zlz4hc,12)
	grep -q '^CONFIG_EROFS_FS_ZIP_LZMA=y' "$cfg" 2>/dev/null && z=(-zlzma,level=109,dictsize=65536 -C65536)
	mkfs.erofs --quiet "${z[@]}" -T"${SOURCE_DATE_EPOCH:-$(date +%s)}" "$img" "$dir"
}

live_boot_prepare() {
	local arch=$1 kdir=$2 w=$3 efiname=$4
	local efi="$kdir/vmlinuz"
	[ -f "$kdir/vmlinuz.efi" ] && efi="$kdir/vmlinuz.efi"
	LIVE_BOOT=${LIVE_BOOT:-stub}
	if uki_build "$arch" "$efi" "$w/live-efi.efi" kwick.live; then efi="$w/live-efi.efi"; echo ">> EFI image carries kwick.live"; else echo "note: no systemd EFI stub or objcopy here, the EFI image has no kwick.live marker"; fi
	BIOSARGS=()
	mkdir -p "$w/live/kwick"
	cp "$kdir/vmlinuz" "$w/live/kwick/vmlinuz"
	if [ "$LIVE_BOOT" = grub ] && [ "$arch" = amd64 ] && command -v grub-mkstandalone >/dev/null \
	   && [ -d /usr/lib/grub/x86_64-efi ] && [ -d /usr/lib/grub/i386-pc ]; then
		cat > "$w/grub.cfg" <<'EOF'
set timeout=5
set default=0
serial --unit=0 --speed=115200
terminal_input console serial
terminal_output console serial
search --no-floppy --file --set=root /kwick/root.erofs
menuentry "KwickOS live" {
	linux /kwick/vmlinuz kwick.live
}
menuentry "KwickOS live, safe graphics (nomodeset)" {
	linux /kwick/vmlinuz kwick.live nomodeset
}
menuentry "Install KwickOS" {
	linux /kwick/vmlinuz kwick.live kwick.install
}
EOF
		local mods="part_gpt part_msdos iso9660 fat search search_fs_file normal linux echo serial terminal configfile"
		grub-mkstandalone -O x86_64-efi -o "$w/grubx64.efi" --modules="$mods all_video" --locales="" --themes="" --fonts="" "boot/grub/grub.cfg=$w/grub.cfg"
		mkdir -p "$w/live/boot/grub/i386-pc"
		grub-mkimage -O i386-pc-eltorito -o "$w/live/boot/grub/bios.img" -p /boot/grub biosdisk iso9660
		cp "$w/grub.cfg" "$w/live/boot/grub/grub.cfg"
		cp /usr/lib/grub/i386-pc/*.lst "$w/live/boot/grub/i386-pc/"
		local -A seen=()
		local queue=($mods vbe vga video video_fb) m d
		while [ ${#queue[@]} -gt 0 ]; do
			m=${queue[0]}; queue=("${queue[@]:1}")
			[ -n "${seen[$m]:-}" ] && continue
			seen[$m]=1
			[ -f "/usr/lib/grub/i386-pc/$m.mod" ] && cp "/usr/lib/grub/i386-pc/$m.mod" "$w/live/boot/grub/i386-pc/"
			for d in $(sed -n "s/^$m: *//p" /usr/lib/grub/i386-pc/moddep.lst); do queue+=("$d"); done
		done
		mkfs.vfat -n KWICK-ESP -C "$w/efiboot.img" $(( $(stat -c %s "$w/grubx64.efi") / 1024 + 512 )) >/dev/null
		mmd -i "$w/efiboot.img" ::/EFI ::/EFI/BOOT
		mcopy -i "$w/efiboot.img" "$w/grubx64.efi" "::/EFI/BOOT/$efiname"
		BIOSARGS=(-isohybrid-mbr /usr/lib/grub/i386-pc/boot_hybrid.img -c boot/grub/boot.cat -b boot/grub/bios.img -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info -eltorito-alt-boot)
		echo ">> live boot menu: GRUB (UEFI and BIOS)"
		return 0
	fi
	[ "$LIVE_BOOT" = grub ] && echo "note: LIVE_BOOT=grub needs amd64 and grub-efi-amd64-bin + grub-pc-bin in this builder, using the EFI stub"
	mkfs.vfat -n KWICK-ESP -C "$w/efiboot.img" $(( $(stat -c %s "$efi") / 1024 + 512 )) >/dev/null
	mmd -i "$w/efiboot.img" ::/EFI ::/EFI/BOOT
	mcopy -i "$w/efiboot.img" "$efi" "::/EFI/BOOT/$efiname"
	if [ "$arch" = amd64 ] && [ -f /usr/lib/ISOLINUX/isolinux.bin ] && [ -f /usr/lib/syslinux/modules/bios/ldlinux.c32 ]; then
		mkdir -p "$w/live/isolinux"
		cp /usr/lib/ISOLINUX/isolinux.bin /usr/lib/syslinux/modules/bios/ldlinux.c32 "$w/live/isolinux/"
		printf 'DEFAULT kwick\nPROMPT 0\nTIMEOUT 1\nLABEL kwick\n  KERNEL /kwick/vmlinuz\n  APPEND kwick.live\n' > "$w/live/isolinux/isolinux.cfg"
		BIOSARGS=(-isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin -c isolinux/boot.cat -b isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot)
	else
		echo "note: no isolinux in this builder, the ISO is UEFI only"
	fi
}
