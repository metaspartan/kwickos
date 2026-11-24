# Verification log

Everything here was run on a real machine (AMD Radeon 8060S, Windows 11, Docker Desktop on WSL2), inside KVM virtual machines with a
virgl GPU that renders on the host GPU. Every claim below has a screenshot, a log line or a command output behind it. What was not
verified is listed at the end.

## Lab

`tools/vmlab/` holds the lab. Start it with `bash tools/vmlab/run.sh` (builds the `kwick-vmlab` image and starts the privileged
container `kwlab` with `/dev/dxg`, `/usr/lib/wsl` and the repo mounted at `/src`; VM disks live in the `kwlab-vm` volume at `/vm`).

How the GPU path works:

* The container gets hardware OpenGL 4.6 through Mesa's `d3d12` driver (`GALLIUM_DRIVER=d3d12`, `LD_LIBRARY_PATH=/usr/lib/wsl/lib`).
  `glxinfo -B` on a plain `Xvfb` reports `D3D12 (AMD Radeon(TM) 8060S Graphics)`, accelerated.
* QEMU `-display egl-headless` does not work here (`egl: no drm render node available`, there is no DRM node in WSL2 containers).
  `-display sdl,gl=on` on an `Xvfb` display does: QEMU's virgl renders with the host d3d12 GL context.
* QMP `screendump` returns "no surface" once the guest uses a GL scanout, so screenshots and video are taken from the X display
  (`ffmpeg -f x11grab`, helper `grab`). Mouse and keyboard go in through QMP (`qmp`), shell access through a serial socket (`sh2`).
* VM command: `vm <name>` with `DISK=` / `CDROM=` / `BIOS=uefi|bios` / `RAM=` / `SMP=` / `DISP=` (see `tools/vmlab/vm.sh`).
  Verified in the guest: `OpenGL renderer string: virgl (D3D12 (AMD Radeon(TM) 8060S Graphics))`.

Helpers: `buildrepo` (packages and signs a repo from the working tree), `serve-repo`, `mkdisk` (grow the release qcow2),
`mountdisk` (loop-mount a raw image), `vmlogin`, `grab`, `mkgif`, `fx-wobbly`, `fx-lamp`, `fx-flame`, `shots-layouts`, `shots-tiling`.

## Second round: fixes and clean re-verification

Fixes made in the tree (each one re-verified in a VM unless marked):

| Item | Change | Verified by |
| --- | --- | --- |
| Base rootfs lacked `/usr/lib/lsb/init-functions` | real Debian `sysvinit-utils` 3.14-4 files shipped in `rootfs/usr/lib/lsb/init-functions`, `init-functions.d/00-verbose`, `rootfs/usr/lib/init/vars.sh` (13,345 bytes raw); base `Provides: sysvinit-utils, lsb-base` unchanged and now consistent | fresh image has `/lib/lsb`; `apt install kwick-desktop` finished with `APT_EXIT=0`, twice, no workaround |
| Windows tiling bar | `text-align` removed from `desktop/rootfs/usr/share/kwick/tiling/windows/style.css`; no other waybar CSS property is unsupported | `waybar` with each layout's config and CSS ran until killed (exit 124), no CSS error; Hyprland itself was not re-run |
| Steam launcher | `flatpak ... --user` for non-root (`--system` only as root); native first; GNU-tar shim `desktop/rootfs/usr/lib/kwick/steam-compat/tar` (busybox tar has no `--checkpoint`, Steam's runtime unpack failed with "Couldn't set up the Steam Runtime"); the desktop package adds `/etc/sudoers.d/kwick-steam` (NOPASSWD for `kwick-gpu steam` only) so the unprivileged launcher can set up native Steam | Steam login window, `docs/img/steam.png` |
| Console login after the desktop postinst | `/etc/kinit/no-getty` now contains `tty1` (SDDM keeps VT 1, the serial getty stays); root autologin on the serial console is kept while root has no password and removed once a root password exists; a message says so | clean install reboots to the desktop, serial shows `root@kwick` |
| GNOME dock listed Text Editor twice | favorites use `org.gnome.TextEditor.desktop` (visible, name "Text Editor"); `kwick-editor.desktop` is hidden in GNOME | `docs/img/vm-gnome-macos.png`: one editor entry |
| PS1 `#` for non-root | no change needed: `/etc/profile` already sets `$` for uid != 0; the `#` came from my harness (`su` inherited root's exported PS1). `su - kwick` prints the `$` prompt | `echo $PS1` as kwick |
| KDE autolock | none existed in the tree; the live ISO now ships `/etc/xdg/kscreenlockerrc` (`Autolock=false`) from `desktop/Dockerfile`; installed systems keep the KDE default | file present in the desktop image; the installed VM locked itself after idle |
| Desktop ISO in BIOS mode | `scripts/mkdesktop-iso.sh` adds isolinux (El Torito BIOS boot plus hybrid MBR) next to the EFI image; `docker/Dockerfile.builder` gains `isolinux syslinux-common`. The headless ISO from `mkimage.sh` is UEFI only too and was not changed | fresh ISO boots in UEFI and in SeaBIOS |
| Kernel | `CONFIG_IA32_EMULATION=y`, `CONFIG_CROSS_MEMORY_ATTACH=y`, `CONFIG_SECURITY_YAMA=y` with `lsm=...yama...` in the built `.config` (nothing to add for Darling); running guest: `ptrace_scope` = 1 | `zcat /proc/config.gz`, `/proc/sys/kernel/yama/ptrace_scope` |

Size: the base rootfs tarball grew from 2,772,056 to 2,821,074 bytes. About 6.7 KB of that is the lsb files; the rest is the newer kpkg binary
(+98 KB raw, multiarch) that the old image did not contain. The headless qcow2 is 10,289,152 bytes (was 10,223,616); the initramfs 2,444,209 (was 2,403,170).

Clean build from the current tree (HEAD `b831680` plus working tree, diff hash `0a7c40e3ade1505d`): kernel generic amd64 (`kbuild-generic.log`, 1600 s),
kpkg amd64, `mkrootfs.sh`, `mkimage.sh`, kernel .debs, `kwick-gpu`, `kwick-desktop` and a signed repo (`buildrepo`; the extra `hypr.deb` copied in was not found by apt, so Hyprland was not installed in this round),
a headless qcow2 grown to 24 GB. Then in the GL VM: `apt install -y kwick-desktop` (APT_EXIT=0), reboot, `KWICK-DESKTOP-UP uptime=10.60s`
(`vm-clean-install-desktop.png`). `dpkg --print-foreign-architectures` prints `i386` after the install, so native Steam is possible.

Results of the second round:

* **Steam**: `steam` as the normal user runs `kwick-gpu steam` through the sudoers rule, installs Debian's `steam-installer` natively, shows the installer notice,
  downloads the client (about 2.2 GB under `~/.steam`), unpacks the Steam runtime, and starts the 32-bit client (IA32 emulation works). The login
  window appeared and I did not sign in: `docs/img/steam.png`. Two things I had to do by hand because of the test harness, not the product: launching from a root
  serial shell needs `DISPLAY` and `XAUTHORITY` of the user's XWayland (`tools/vmlab/asuser.sh`), and I clicked "Install" on the installer notice. The shim and the
  new `steam` script were copied into the guest instead of reinstalled (the package rebuilt later contains both), so that exact package path was not re-run.
  A failed native attempt leaves `~/.local/state/kwick/steam-native-failed` for 24 hours, which silently sends the next launches to Flathub.
* **Cube**: Meta+Ctrl+Right (the Plasma default) rotates the desktop cube, `kwick_cubeslide`, 3D faces visible in `effects-cube.gif` and `effects-cube-frames.png`.
  Ctrl+Alt+Right is not bound in Plasma 6, nothing happened with it.
* **Desktop ISO**: built from the current tree (1,442,445,312 bytes, hybrid). UEFI: `KWICK-DESKTOP-UP uptime=15.01s` (`iso-uefi-desktop.png`).
  BIOS (SeaBIOS): `KWICK-DESKTOP-UP uptime=7.84s` (`iso-bios-desktop.png`). The ISO's rootfs came from a docker build on the pre-multiarch kpkg base, so its kpkg is older.
* **GNOME**: all three layouts re-run, macOS dock shows one editor entry. The `/usr/local` override of `org.gnome.TextEditor.desktop` now carries the `kwick-editor` icon (not re-captured).
* Not re-run in round two: Hyprland screenshots, sway, wobbly/lamp/flame captures.

## 0.7.1 update delivery

Lab: `integ-vmlab` container with `/dev/kvm`, one VM at a time (SMP 2). The repository was built from the working tree with
`VERSION` set to 0.7.1 (kernel packages, `kwick-core` with the new kinit, `kwick-update`, `kwick-desktop`, the
`zsh-autosuggestions` carrier) and signed with a dev key; the CI images of the 0.7.0 release candidate and the 0.6.5 release
were the starting points.

| Case | Result |
| --- | --- |
| 0.6.5 release qcow2, nothing but `kwick-base` and `linux-image-kwick-virt 7.3.5-1` registered | `apt upgrade` upgrades the kernel to `7.3.6-2` and installs `kwick-core` and `kwick-update` 0.7.1 first; `/usr/bin/kpkg` and `/usr/sbin/kinit` are the new ones, `/etc/kwick-release` says 0.7.1, the next boot runs the new kinit |
| CI headless qcow2 (0.7.0 RC), kernel already `7.3.6-1` | `apt upgrade`: "Installing dependencies: kwick-core kwick-update, Upgrading: linux-image-kwick-virt" (8.4 MB), the kernel stays the default |
| GPT growth | both images grown with `qemu-img resize +3G`: `kwick-growroot /` moved the backup header, grew partition 2 and ext4 online (1024 to 4096 MiB), a second run changes nothing, the disk boots again and `sfdisk --verify` reports no errors; `tests/growroot-gpt.sh` covers GPT, MBR and a damaged GPT on loop devices |
| Desktop installed from the 0.7.0 desktop ISO (only `kwick-base` registered), with a line added to `/etc/xdg/kwinrc` and `/etc/xdg/kdeglobals` set to an older shipped version | `apt upgrade` takes `zsh-autosuggestions 0.7.1-1+kwick1`, `kwick-core`, `kwick-update`; right after apt, `kwick-update adopt-desktop` installs `kwick-desktop 0.7.1`, `linux-image-kwick-generic`, `kwick-gpu`, `kwick-gaming`, `kwick-essentials` (logged task "Desktop registered"); `kwinrc` kept with `kwinrc.dpkg-dist` next to it, `kdeglobals` replaced by the new version, no `kwick` user and no autologin created, `dpkg -S /usr/bin/kwick-layout` names `kwick-desktop`; Plasma starts after the restart |
| Desktop ISO built by `mkdesktop-iso.sh` from the CI desktop root plus the essentials' Debian packages | the live system has all seven packages registered and `apt-get check` clean, `kpkg` hard-linked; installed with `kwick-install run` (btrfs, GRUB), then a `kwick-desktop 0.7.2` in the repository is a normal upgrade (the new `kwick-layout` lands, a user edit in `kwinrc` stays) |
| Layout switch with windows open | macOS, Windows, Linux and back: every open window has the new buttons; before the fix the Dolphin windows that `kwick-layout` reopens kept the previous plugin's decoration |

Not verified: the CI desktop workflow itself (the Docker build with the essentials' packages and the package step), arm64 and
riscv64, the Raspberry Pi image, the adoption through the Updates page (the CLI `apt upgrade` path was run), a desktop
installed from a 0.6.x ISO, and a GNOME session after the Lock Screen change (the defaults and the keymap were checked in the VM).

## Tree that was tested (first round)

HEAD `f1e0d43` plus the working tree for the first install; the effects, sessions and Steam runs used a repo rebuilt from HEAD
`6525b4f` plus the working tree (`diff` sha256 prefix `3ea7376e66be9285`, untracked-file hash `194239003e0a4c98`, built
2026-11-13 13:48 UTC; `/work/pkg2/tree-state.txt`). The VM base is the headless `kwickos-amd64.qcow2` from `out/amd64`
(KwickOS 0.4.0, kernel 7.3.4-kwick, built 2026-11-12, i.e. before the kpkg multiarch commit). The packages come from
`scripts/mkgpupkg.sh`, `scripts/mkdesktoppkg.sh`, `scripts/mkhyprlandpkg.sh` and `scripts/mkrepo.sh`; the CRLF line endings of the
Windows checkout are stripped in a copy first (`buildrepo`). The kernel .debs are the ones already in `out/repo`.

## Results

| Area | Result | Evidence |
| --- | --- | --- |
| Headless image boots under KVM (UEFI) | works, kernel start to prompt 0.9 to 1.9 s | `vm h1`, serial log |
| `apt install kwick-desktop` on headless | FAILS twice, then works with workarounds (bugs 1, 2) | below |
| Reboot into the upgraded desktop | works only after bug 2 is worked around | `docs/img/vm-apt-desktop.png` |
| KWin compositing | OpenGL on `virgl (D3D12 (AMD Radeon(TM) 8060S Graphics))`, GL 4.2 core | `qdbus6 org.kde.KWin /KWin org.kde.KWin.supportInformation` |
| `kwick-effects full` | wobblywindows, magiclamp, kwick_flame, cube, kwick_cubeslide, blur, contrast, translucency all load | `isEffectLoaded` returned true for each |
| Wobbly windows | visible: the window shears while dragged | `effects-wobbly.gif`, `effects-wobbly-frames.png` |
| Magic lamp | visible: genie shape while the window flies into the dock | `effects-magiclamp.gif`, `effects-magiclamp-frames.png` |
| Flame close | visible: fire burns the window away from the top edge | `effects-flame.gif`, `effects-flame-frames.png` |
| Blur / glass | glass theme on menu bar and dock; the static shot does not show the blur itself | `glass-blur.png` |
| Cube | loads; no rotation was driven or captured | `isEffectLoaded cube` true only |
| Burn My Windows 49 on KWin 6.3.6 | all 18 installed effects load and animate open and close; corners stay rounded under Liquid Glass; no blur box under a translucent Konsole | `effects-bmw-*.gif` |
| Open/close frame rate (virgl, in KWin, `Profile=1`) | Burn My Windows 44 to 51 fps, Dissolve 49, Flip 44, Flame 39, KWin's Scale 41; the VM tops out there | `kwick_liquidglass` profile log |
| GNOME 48 with Burn My Windows 49 | extension active; `kwick-effects open-close portal` writes the `kwickos.conf` profile and the portal plays; durations and presets apply | `gnome-extensions info`, `kwick-effects status`, frames of a closing Text Editor |
| GNOME, macOS / Windows / Linux layouts | runs, each layout visibly different | `vm-gnome-macos.png`, `vm-gnome-windows.png`, `vm-gnome-linux.png` |
| Hyprland 0.49.0 (`kwick-hyprland`), 3 layouts | runs, tiles three foot windows, bar and dock per layout; Windows layout has no bar (bug 3) | `vm-tiling-macos.png`, `vm-tiling-linux.png`, `vm-tiling-windows-nobar.png`, `vm-tiling-windows.png` |
| Desktop ISO, UEFI | boots to the desktop, `KWICK-DESKTOP-UP uptime=26.80s` | `iso-uefi-desktop.png` |
| Desktop ISO, BIOS | does not boot ("No bootable device"), the ISO has only an EFI image | `iso-bios-nobootable.png` |
| Steam first launch | Flatpak installs and starts, then stops on a missing 32-bit libc (bugs 4, 5) | `steam-ia32-error.png` |

The GIFs are jumpy. Under virgl on d3d12 the guest delivers only a few frames while a window animates (the minimize animation fell
between two frames), so each GIF shows one to three animation frames per transition. The animations themselves ran; the frame
rate of the capture path is the limit. Capturing with `AnimationDurationFactor` 3 did not raise it.

`vm-tiling-windows.png` was taken after deleting the `text-align` line from the generated `~/.config/waybar/style.css` by hand (bug 3).
`vm-tiling-windows-nobar.png` is the state the tree produces. The blue glow in the Windows layouts is the wallpaper.

## Bugs found (first round; items 1 to 6 are fixed, see the second-round section above; the Not verified list below is from round one)

1. `apt install kwick-desktop` on a headless 0.4.0 image fails: `x11-common` postinst runs `/etc/init.d/x11-common`, which sources
   `/lib/lsb/init-functions`, and the file does not exist (`E: x11-common postinst subprocess returned error exit status (exit status 1)`).
   Cause: the base package `kwickos-base` (`X-Kwick-Base: yes` in `/var/lib/dpkg/status`) `Provides: lsb-base, sysvinit-utils`, so kpkg never
   installs them, but nothing ships the files. In trixie `/usr/lib/lsb/init-functions`, `/usr/lib/lsb/init-functions.d/00-verbose` and
   `/usr/lib/init/vars.sh` come from `sysvinit-utils` (not `lsb-base`, which is an empty transitional package). `elogind` fails the same way.
   Proposed fix: ship those three paths in the base rootfs (`scripts/mkrootfs.sh`), or drop `sysvinit-utils` from the base `Provides`.
   Workaround used: extract `sysvinit-utils_3.14-4_amd64.deb` and copy those paths into the guest, then `dpkg --configure -a`.
2. After the upgrade the desktop never appears: black screen with a text cursor, `sddm-helper` opens and closes the session in a loop,
   and the kernel prints `KWICK-DESKTOP-TIMEOUT: plasma session did not start`. `kinit` still starts `getty` on tty1 and SDDM cannot
   take VT 1. `kinit` reads `/etc/kinit/no-getty` as a list of consoles ("tty1") to leave to the display manager. The ISO ships
   `/etc/kinit/no-getty` containing `tty1`, but the old `kwick-desktop` postinst did `rm -f /etc/kinit/no-getty`. Writing `tty1` into the file and
   rebooting brought up Plasma. The rebuilt package from HEAD `6525b4f` no longer removes the file, and a `--reinstall` left `tty1` in place;
   a fresh install of the new package on a fresh image was not repeated.
3. Windows layout under Hyprland (and sway, same CSS): `waybar` exits with status 1, so there is no taskbar.
   Log: `[error] style.css:91:12 'text-align' is not a valid property name`. File: `desktop/rootfs/usr/share/kwick/tiling/windows/style.css`,
   rule `#clock`, line `text-align: right;`. Proposed fix: delete that line (GTK CSS has no `text-align`). Deleting it made the taskbar appear.
4. Steam cannot run: the kernel is built without `CONFIG_IA32_EMULATION` (`# CONFIG_IA32_EMULATION is not set` in `out/amd64/kernel-generic/config`
   and `kernel-virt/config`, and in the running guest's `/proc/config.gz`). Steam's check reports `You are missing the following 32-bit libraries,
   and Steam may not run: libc.so.6`, and native i386 multiarch Steam cannot work either. Proposed fix: `CONFIG_IA32_EMULATION=y`
   in `scripts/build-kernel.sh` / the kernel config. Not rebuilt or re-tested, so the Steam UI was never seen.
5. `/usr/bin/steam` falls back to `flatpak install` without `--user` and fails for a normal user: `Failed to get revokefs-fuse socket from
   system-helper: Flatpak system operation GetRevokefsFd not allowed for user`. Proposed fix: `flatpak install --user` when not root.
   Also, on this base image `kwick-gpu steam` ends with `could not enable the i386 architecture`, which is expected for an image older than
   the kpkg multiarch change; not re-tested on a newer base.
6. Smaller: after the desktop postinst no login is possible on the serial console (`login: bad salt`, root is `*`, `kwick` is `!`) because
   `/etc/kinit/autologin` is removed; I set passwords from a loop mount to get a shell. KDE locks the screen after a few minutes idle
   (QEMU then shows "Display output is not active"); I disabled autolock for the captures.
   The Windows-layout GNOME shot shows a "Dash to Panel has been updated" toast on first start, and the GNOME macOS dock lists gedit twice
   (a pinned and a running entry).

## kwick-kernel (kernel switching)

`tests/kernel-switch.sh efistub` and `grub` run on amd64 under QEMU with OVMF (TCG, no KVM) against the shipped
`kwickos-amd64.img`. A signed test repository holds `linux-image-kwick-virt` 7.3.3 (built for this test), virt 7.3.4 and generic
7.3.4. Nine boots per boot path (ten for efistub): install both virt versions through apt, one-shot trial that boots the older
kernel and is confirmed, `default`, `rollback`, `try --promote` (the default changes only after confirmation), a trial that
boots but is not confirmed (recorded as failed, default boots again), on efistub also a trial image the firmware cannot load,
a switch to the generic flavor (modules loaded), `keep` removing a stale retained kernel, and `remove` refusing the running
kernel. Result: 21 of 21 checks pass on efistub and 19 of 19 on grub. The GRUB image is a layout equivalent to what
`kwick-install` writes (grub-mkimage core image, a single-kernel `grub.cfg`, `install.conf`) and exercises the adoption of that
layout; it was not produced by `kwick-install run`.

Not verified for `kwick-kernel`: systemd-boot (the `loader/entries` and `bootctl set-oneshot` code is untested), the U-Boot
(BPI-F3) and Apple paths, BIOS GRUB, installs that need a generated initramfs (btrfs, xfs, ZFS, LUKS), arm64 and riscv64,
the Settings page in a running KDE session, and `kwick-kernel-confirm.service` under real systemd (kinit ran it).

## Updates and kernel trials, end to end

Run on 2026-11-20 with KVM VMs (QEMU, OVMF or SeaBIOS) in a lab container. Everything came from this tree: kpkg,
BusyBox and kinit, the virt kernels 7.3.4 and 7.3.5 (`scripts/build-kernel.sh`), the generic kernel 7.3.5 (the generic
7.3.4 build in `out/amd64` was reused), the rootfs and the headless image (`mkrootfs.sh`, `mkimage.sh`), and the
packages (`mkkernelpkg.sh`, `mkstoragepkg.sh`, `mkagentspkg.sh`, `mkessentialspkg.sh`, `mkupdatepkg.sh`). A local signed
repository came in four stages: A has the 0.6.4 packages and the 7.3.4 kernels. B adds the 0.6.5 packages (`kwick-agents`
0.6.5 in a `stable-security` suite) and the 7.3.5 kernels. C adds a virt "7.3.6" whose init exits at once (kernel panic,
"Attempted to kill init"), and D adds a virt "7.3.7" whose init sleeps forever (a hang without a panic).

Installed systems were made with `kwick-install run` from the headless image: UEFI GRUB, systemd-boot, BIOS GRUB on
ext4 (installer booted through SeaBIOS) and BIOS GRUB on btrfs (installer running the generic kernel). Each one went
through: check, security-only upgrade, full upgrade with a kernel (trial armed, default unchanged), trial boot,
confirmation and promotion, reboot on the new default, the panicking trial, rollback, `default`, and the hanging trial.

| Boot path | Result |
| --- | --- |
| EFI stub (the image itself) | 14 of 14 |
| UEFI GRUB | 14 of 14 |
| systemd-boot (`bootctl` not installed, so `LoaderEntryOneShot` is set directly) | 14 of 14 |
| BIOS GRUB, ext4 | 14 of 14 |
| BIOS GRUB, btrfs | `try` refused with the btrfs message; the upgrade installed generic and virt 7.3.5 and left the default; `default 7.3.5` built its initramfs and booted; `rollback` booted 7.3.4 |
| U-Boot (BPI-F3) | the board's own `env_k1-x.txt` in the U-Boot 2022.10 sandbox, with `kwick-bootctl` and `kwick-kernel` writing the SD and eMMC FAT images: 17 of 17 (see below) |

The panicking trial comes back by itself on every path: "Kernel panic ... Rebooting in 10 seconds", then the default
kernel, and the next confirmation records "failed". Before the fix the same trial stopped at the panic until a power
cycle. A hanging trial still needs a power cycle (QMP `system_reset` in the test), after which the default boots and the
failure is recorded.

Automatic updates: `kwick-update auto on` and `auto set system on` write the crontab line and start `crond`. With the
guest clock set to 20 s before the chosen minute, `crond` ran `kwick-update scheduled` (syslog `USER root ... cmd
KWICK_JOB=update`), which checked and installed. `auto off` removed the line and stopped `crond`.

U-Boot sandbox: `sed` maps `mmc 0:1` and `mmc 2:1` to two host image files and replaces `bootm` with a marker plus
`poweroff`. U-Boot's `reset` relaunches the sandbox, which counts as the next power-on. Checked:
* a trial kernel that dies before confirmation: the next power-on finds `kwick-attempt`, restores `kwick.prv`, resets
  and boots the previous kernel, with no `kwick-mode-armbian` left;
* a trial kernel whose files cannot be loaded falls back in the same power-on;
* a confirmed trial is promoted, with `kwick.prv` holding the old kernel;
* `try --cancel` and `rollback` work;
* a later failure of a confirmed kernel still goes to Armbian, as before.

Desktop: an existing 0.4.0 desktop install (a qcow2 overlay on a lab disk) was upgraded with `apt-get upgrade` from
repository B. kpkg installed the new dependency `kwick-update` of `kwick-essentials` 0.6.5, which brought
`kwick-update` and `kwick-kernel` and enabled `kwick-kernel-confirm.service` and `kwick-boot-ok.service`. The Settings
Updates page from this tree, with the polkit policy and rule, was then checked:
* opening it with a stale check runs `pkexec kwick-update check` without a prompt, with progress;
* Update Now shows the KDE polkit dialog, installs the generic 7.3.5 kernel and arms its trial;
* the trial boot is confirmed and promoted;
* Roll Back asks, authorizes and shows Restart Required;
* closing Settings during an upgrade closes the window at once while the task finishes, trial setup included.

The kernel list (`kwick-kernel list --json`) took 31 to 39 s on that desktop, whose base still has the 0.4.0 kpkg
(about 5 s per `apt-cache` call there, and its `madison` prints the `policy` format). It now takes one `apt-cache` call
that understands both formats: 5.4 s there and about 1 s on a current image.

Not verified: real BPI-F3 hardware for the new trial fallback (sandbox only, `bootm` stubbed, no watchdog), a watchdog for
hanging trial kernels on PCs (none exists), the full Settings flow for app (Flatpak) updates, arm64 and riscv64 images.

## System snapshots, end to end

Run on 2026-11-21 in KVM VMs (QEMU, OVMF) in the lab container `snap-lab` (volume `snap-vm`). Installs came from the desktop
live ISO (`desktop-vm.iso`, KwickOS 0.4.0, generic kernel 7.3.4) running this tree's `kwick-install`, `kwick-snapshot`,
`kwick-kernel`, `kwick-update` and a kpkg built from this tree (`go vet` and `go test` pass, including the new hook tests). The
installed systems got the same files copied in, because the installer copies the ISO's own (older) root. The ISO lacks
`btrfs-progs`, GRUB and systemd-boot; the installer fetched them with apt, as designed.

| Check | Result |
|---|---|
| `kwick-install bootloaders --json` on the live ISO | `"fs":"btrfs","default":"grub"`, EFI stub listed as needing ext4 |
| Fresh install, UEFI GRUB, `--swap file:2G`, default file system | subvolumes `@ @home @root @srv @var_log @var_cache @var_tmp @snapshots @swap`; fstab with `compress=zstd:1`, `/.snapshots` `nosuid,nodev`; snapshot 1 "Fresh install"; crontab line and `kwick-snapshot-boot.service` enabled; `btrfs-progs` installed into the target |
| First boot | `/` mounted `subvol=/@` with `noatime,compress=zstd:1` (after `ROOT_FLAGS`); `kwick-snapshot status`: subvolumes layout, rollback available, snapshot entries in GRUB |
| `apt-get install sl` (kpkg `DPkg::Pre-Invoke`/`Post-Invoke`) | pre 2 and post 3, described "apt-get install sl"; `changes` lists `/usr/games/sl`, the docs and the dpkg files; `packages 2 3` shows `+ sl` |
| `kwick-update upgrade` (4 Debian security updates) | exactly one pair, 4/5 "System update (4 updates)", no extra apt pair; `packages 4 5` lists the four version changes |
| BusyBox `crond` | with the clock set before the job's minute, `crond` ran `kwick-snapshot timeline` (syslog line), which took root 6 and home 1 |
| `boot-once 7` (GRUB `next_entry`) | first attempt exposed that the installer's `grub.cfg` had no one-shot logic; fixed, and `boot-once` now runs `kwick-kernel sync` when `grub.cfg` lacks it. Then: booted `rootflags=subvol=@snapshots/root/7/snapshot kwick.snapshot=7`, `/` an overlay, a file changed after the snapshot shows its old content, `next_entry` cleared, `create` refused, apt worked without snapshots; the next boot was the normal system with nothing changed |
| Broken system (GRUB) | `/usr/sbin/kinit` replaced by garbage and `libc.so.6` deleted: every boot ends in "Kernel panic ... Attempted to kill init", "Rebooting in 10 seconds", in a loop |
| Recovery through the GRUB menu | F4 during the hidden one-second timeout shows the menu with **KwickOS snapshots** (`snapshots-grub.png`); snapshot 7 started read-only; `kwick-snapshot rollback 7 --yes` saved the broken system as snapshot 9; the next boot ran the restored system: kinit and libc back, the file as it was in 7, `@.rollback-*` deleted by `kwick-snapshot-boot.service`, `/var/lib/kwick/snapshot/rollback` written |
| Rescue from the live ISO | `kwick-snapshot --device auto list` (fetched `btrfs-progs` itself), `packages 2 3`, `restore 7 /etc/snaptest --to /tmp`, `rollback 8 --yes`; booting the disk gave snapshot 8's state, old root removed |
| Fresh install, systemd-boot, `--swap zram` | no `@swap`; entries `ksnap-NNNNNN.conf` written after every snapshot; `boot-once 4` through `LoaderEntryOneShot` booted snapshot 4 read-only and the variable was consumed |
| Broken system (systemd-boot) | same breakage, panic loop; Space shows the menu with the snapshots after the kernels, newest first (`snapshots-systemd-boot.png`); snapshot 4 started, `rollback 4` saved snapshot 5, the next boot was healthy |
| `kwick-kernel sync` on a Btrfs install | rewrote `grub.cfg` with per-kernel entries carrying `rootflags=subvol=@,noatime,compress=zstd:1`, the snapshot include line and initramfs images with the snapshot marker; `kwick-snapshot boot-sync` then pointed the snapshot entries at `/EFI/kwick/k/generic-7.3.4/` |
| ext4 install (`--fs ext4`, EFI stub) | `status` explains that snapshots need Btrfs (exit 0); `list --json` returns `{"ok":false,...}` (exit 1); `create`, `rollback`, `setup` refuse with the same message; `timeline` exits 0 silently; `apt-get install sl` works with no snapshot; no `/.snapshots`, no crontab line; nothing changed on disk |
| Settings, Snapshots page (KDE, virgl) | dark and light, macOS, Windows and Linux layouts; timeline grouped by day with the date ruler; a pair opens on **Changes** with the package versions and 66 changed files; **Files** browses `/` and home snapshots with "Changed since"; a home file restored with **Replace** got its old content back and the current one went to the Trash; **Options…** sheet; the rollback confirmation; the "Running from a snapshot" banner during a snapshot boot |

Screenshots: `D:\KwickOS-lab\snap\shots\` (`settings-dark-*.png`, `settings-light-*.png`, `settings-windows-dark.png`,
`settings-linux-light.png`, `settings-booted-snapshot.png`, `set-dark-docs.png`, `set-dark-restore-sheet.png`,
`grub-s-grub-menu2.png`, `grub-s-grub-submenu.png`, `sdboot-menu.png`, `icons-sheet.png`), a selection in `docs/img/snapshots-*.png`.

Problems found and fixed during the run: the installer's `grub.cfg` could not start an entry once; `kwick-snapshot` lost the
snapshot number when it refreshed the boot menu (shell variable reuse); options before the subcommand (`--device auto list`)
were not accepted; orphan renames in `btrfs send` streams showed up as `o123-4-0` paths in the change list; the root was mounted
without the subvolume's `compress` and `noatime`; `short` is a reserved word in QML's JavaScript; titles in the timeline were
elided too early; a Popup function named `enter` shadowed the transition property; the Snapshots launcher entry claimed the
Settings window class, so the dock showed every Settings window with the Snapshots icon.

Not verified: BIOS GRUB installs (the ext4 `/boot` for Btrfs on BIOS is new and was not booted), encrypted Btrfs installs, manual
partitioning onto Btrfs, a rollback across a kernel change (the module carry-over in `carry_kernels` ran but every snapshot had
the same kernel), `kwick-snapshot setup` on a Btrfs install from an older image, quotas, the space-based cleanup with a full disk,
the Dolphin "Restore Previous Versions…" action, GNOME, Hyprland and sway (the page is the same QML), the GUI and text
installers' new file system screens (code only), real apt instead of kpkg, arm64 and riscv64, U-Boot boards. The kwick-update
run on the ext4 VM failed in Debian's `sudo` postinst on that old image, unrelated to snapshots.

## Touch and tablet

VM: overlay on the installed desktop disk (`vpn-1.qcow2`), KVM, virgl, 1600x900 at scale 1.0, `EXTRA='-device virtio-multitouch-pci'`
(the guest sees "QEMU Virtio MultiTouch" as `ID_INPUT_TOUCHSCREEN`). Touch is injected with `qmp tap` / `qmp swipe`, touchpad
gestures with `tools/vmlab/touchpad.py` inside the guest (uinput, after `modprobe uinput`). The working-tree files and the
`plasma-keyboard` build from `scripts/mkkeyboardpkg.sh` were copied into the guest; `iio-sensor-proxy libinput-tools wvkbd
qt6-virtualkeyboard-plugin qml6-module-org-kde-layershell` came from Debian with apt. The `kwick-desktop` package itself was not rebuilt.

| Check | Result | Evidence |
| --- | --- | --- |
| `scripts/mkkeyboardpkg.sh` in a clean `debian:trixie` container | builds, 1.6 MB installed | build log |
| Tap a text field in Settings (Plasma) | keyboard slides up, KWin moves the window clear of it; typed "Touch" by tapping keys | `touch-osk-dark.png` |
| Same with the Plasma color scheme switched to BreezeLight | keyboard turns light live | `touch-osk-light.png` |
| `&123` key | symbols page | `touch-osk-symbols.png` |
| SDDM: tap the password field, type "kwick" on the keyboard, return | dark keyboard, greeter slides up, login succeeded (new session in `loginctl`) | `touch-sddm.png` |
| Installer (`kwick-installer-gui --dry-run`): language search | keyboard appears with the sheet, typed text lands in the field at once | `touch-installer.png` |
| `kwick-touch tablet on` / `auto` | `tabletMode` true then false over D-Bus; Plasma enlarges dock and menu bar, Settings badge says Tablet | `touch-tablet-mode.png` |
| Touchpad, macOS layout: 3 up, 3 down, 4 spread | Overview, App windows (ExposeClass), show desktop | `touch-gesture-overview.png` |
| Touchscreen: swipe up from the bottom edge, down from the top edge, 3 fingers up | Overview, Search, Overview | `touch-edge-overview.png` |
| Rotation lock on KDE | `autoRotation` in `kwinoutputconfig.json` flips between `InTabletMode` and `Never` | file contents |
| Gesture watcher | starts from autostart at login, survives touchpad hotplug | `ps` |
| Hyprland | `Hyprland --verify-config` ok with `kwick-touch.conf`; live: `workspace_swipe_touch` 1, fingers 3 (4 after `kwick-layout windows`); tapping the bar's keyboard button shows and hides `wvkbd` | `touch-hyprland-osk.png` |

Problems found and fixed on the way: Debian's `qt6-virtualkeyboard-plugin` is required (without it the keyboard draws but every key
logs "input method is not set"); the keyboard's language popup needs `qml6-module-org-kde-layershell` (without it the keyboard
crashes on start and KWin gives up after five tries); busybox `grep` has no `--line-buffered`, so the gesture watcher filters in
`awk`; `wvkbd` 0.15 dies on `SIGRTMIN`, so `kwick-touch` keeps the shown state itself and sends `SIGUSR1`/`SIGUSR2`; SDDM's greeter
needs `QT_QPA_PLATFORMTHEME=kde` to be dark.

Not verified: real rotation (the VM has no accelerometer; `iio-sensor-proxy` starts on D-Bus activation and exits without
sensors), a hardware tablet-mode switch, pen input, GNOME (settings are plain gsettings keys, not run), sway, the lock screen
(same Breeze component and KWin input method as SDDM), a rebuilt `kwick-desktop` package and the desktop ISO, arm64 and riscv64 builds
of `plasma-keyboard`.

## Arch repositories and AUR (kwick-arch)

Run on 2026-11-21. The packages `kwick-arch` and `kwick-update` were built from this tree with `scripts/mkarchpkg.sh` and
`scripts/mkupdatepkg.sh` in the lab container `arch-lab` and installed with `apt install ./*.deb` into a KVM VM (`arch-1`, a qcow2
overlay on the 0.4.0 KDE desktop disk `d10.qcow2`, virgl GPU, 8 GB). Development runs used a privileged `debian:trixie`
container (`arch-dev`). Arch bootstrap: `archlinux-bootstrap-2026.11.01-x86_64.tar.zst`.

| Check | Result |
| --- | --- |
| `vercmp` against pacman's `vercmp` | 3,441 version pairs from the tracker data plus edge cases, 0 mismatches |
| `tests/kwick-arch-gates.py` (gate thresholds, upgrade rule, risk analyzer, git tree hash vs `git write-tree`) | 0 failures |
| `enable` in the VM | apt pulled `archlinux-keyring`, `gpgv`, `zstd`; bootstrap verified (`signed by 3E80CA1A...9A5C`), keyring populated, `-Su`, `mesa`; 1 min 46 s, 877 MiB |
| bootstrap with one flipped byte | refused: `gpgv: BAD signature from "Pierre Schmitz"` |
| genuine bootstrap, signer not in `RELEASE_KEYS` | refused: `untrusted-signer` |
| `SigLevel = Never` in the environment's `pacman.conf` | refused before pacman runs (`insecure-pacman-conf`) |
| `install gnome-calculator qalculate-qt` (GTK4/libadwaita and Qt 6) | installed; warnings for `libtiff`, `giflib`, `xdg-utils` (Medium/Unknown, dependencies); both menu entries exported, the host's own `org.gnome.Calculator.desktop` kept and the Arch one exported as "Calculator (Arch)" |
| launching through the exported desktop files and from KRunner | both run on KDE Wayland as the user: `libQt6WaylandClient` and `libwayland-client` mapped, GTK on `libgallium`/`renderD128` (virgl); `docs/img/arch-qt-gtk-apps.png`, `arch-gtk4-calculator.png`, `arch-krunner.png` |
| `PATH` export | `su - kwick -c 'echo 6*7 \| gcalccmd'` prints 42 through `/usr/local/lib/kwick-arch/bin` |
| `install wget` (AVG-1892, Medium, open) | refused, exit 4, message names AVG-1892 and CVE-2021-31879 |
| `install neofetch --aur` without a terminal and without `--yes` | exit 3 with the review in the JSON |
| `info neofetch --aur --json`, then `install neofetch --aur --yes --commit <sha>` | snapshot tree matched the commit tree, upstream tag PGP-verified, built as uid 64990 with "Building neofetch without network access", installed, pinned commit in `list --json`, `neofetch` on PATH |
| build sandbox | inside the build step: no network (`curl: (6) Could not resolve host`), `/usr` and `/etc` read-only, `CapEff 0`, `NoNewPrivs 1`; the download step has network |
| upgrade | `gnome-calculator` downgraded to 51.0-1 from the Arch archive (signed); `upgrade --check` listed 51.0-1 -> 51.1-1; `kwick-update check` showed it as an `arch` row and in `"arch"`; `kwick-update upgrade arch` upgraded it, the row disappeared |
| Store calls as the unprivileged user | `status`, `search`, `search --aur`, `info`, `info --aur`, `list`, `upgrade --check` (all `--json`) succeeded; `install` asked polkit for authentication |
| `remove qalculate-qt` | its menu entry and command wrapper removed, others kept |
| `disable`, `enable`, `disable --purge` | exports and the PATH directory removed; `search` then exits 6; re-enable restored the exports; purge removed the root |
| host CVE check (`/usr/lib/kwick/debsec`) | on `debian:trixie` the CVE set equals `debsecan --suite trixie` (186 of 186, BusyBox `awk`, about 1 s); in the VM 19 CVEs fixable by pending updates, with the trixie-security fix versions apt also offers (`gpgme1.0 1.24.2-3+deb13u1`, `libgd2 2.3.3-14~deb13u3`) |
| arm64 | simulated (`platform.machine()` = aarch64): `status` reports `supported: false` with the reason, `enable`/`search` exit 7 |

Analyzer on real AUR packages: `yay`, `zoom`, `ttf-ms-fonts`, `downgrade`, `pamac-aur` low; `paru` low; `google-chrome` and
`brave-bin` medium; `spotify` high (plain-HTTP index files with `SKIP`).

Not verified for kwick-arch: GNOME and Hyprland sessions (only KDE Wayland), PipeWire audio from an Arch app, NVIDIA, a real arm64
machine, an upgrade that the gate refuses with live tracker data (covered only by the unit test), AUR packages with AUR
dependencies, the Store GUI and the Updates page (owned elsewhere; only their CLI/JSON was exercised), and the VM's own
older kpkg lacks `${source:Version}`, so `debsec` fell back to binary versions there (current kpkg provides it).

## AI agents (kwick-agents, kwick-mcp)

Own lab container `agents-lab` (image `kwick-vmlab`), VM overlays in the `agents-vm` volume: `agents-h1` (headless, on
`base-fresh2.qcow2`, KwickOS 0.4.0, user `tester`) and `agents-d1` (KDE Plasma desktop, on `d10.qcow2`, user `kwick`, virgl). The
`kwick-agents_0.6.5_amd64.deb` from `scripts/mkagentspkg.sh` was installed with `apt-get install ./...deb` (pulled `bubblewrap` 0.12.0,
`ca-certificates`); later iterations replaced only `/usr/bin/kwick-agents` and the catalog.

| Area | Result |
|---|---|
| Installs as a normal user, sha256 checked | codex, llama-cpp, gemini-cli (+ node), opencode, goose, omp, claude-code, cybara, aider (+ uv, Python 3.12), hermes (git tag + commit check, `uv sync --frozen`, Python 3.14), openclaw (`npm ci` from the shipped lock, postinstall run sandboxed without network), ollama (1.5 GB `.tar.zst`). Each `--version` ran through its `~/.local/bin` launcher inside the sandbox (rc 0). |
| System install | `install --system opencode` as root, run by a second user, `remove --system` |
| Legacy | 0.6.5-style `/var/lib/kwick-agents/cybara` marker shows as installed in `status --machine` |
| Lifecycle | `update` (nothing to do, `--json`), `remove goose` (launcher and MCP entry removed, data kept), reinstall |
| Sandbox (`kwick-agents shell codex`) | sees only its private home, `~/.codex`, the project folder; `/usr` read-only (`touch` fails), own pid namespace, `/run/kwick-mcp.sock`; `--offline` has no network; keys injected (own and `shared`, not other agents' keys) |
| Ollama | `ollama serve` in the sandbox, API on 127.0.0.1:11434 reachable from the host, `ollama list` works |
| MCP, real agents | `claude mcp list`: kwickos Connected; `opencode mcp list`: connected; `gemini mcp list`: Connected (after trusting the folder; Gemini disables MCP in untrusted folders); `codex`, `hermes`, `openclaw mcp list` show the entry; goose config written |
| MCP, clients | MCP Inspector CLI 2.16 inside the gemini-cli sandbox (relay through the broker, identity `gemini-cli`); Python MCP SDK client: tools, resource `kwickos://docs/agents`, system_info, files inside/outside the project (outside and `secrets.json` denied), deny grant, invalid package name rejected |
| Consent, headless | `files_write` and `packages_install` waited in `kwick-agents consent`, answered from a second process; privileged call then reported the `sudo apt install` command (no polkit) |
| Consent, desktop | kdialog prompts for `files_write` (Allow once), `settings_set` (Always allow, appearance switched to light, grant stored), `screenshot` and `packages_install` from inside the gemini-cli sandbox; polkit prompt with the `org.kwickos.agents.policy` message appeared and was cancelled (no password entered) |
| Keys | headless: `secrets.json` mode 600 in a mode 700 folder; desktop: Settings > Agents > Add Key > kdialog password dialog stored a test value. The KDE image has no Secret Service provider, so the file backend was chosen (correctly detected); the Secret Service path was not exercised |
| Settings > Agents | dark and light, expanded agent with switches, permission levels, folders, keys, activity |
| JSON | every `kwick-agents ... --json` output parsed; `kwick-layout status --json`, `kwick-desktop list --json`, `kwick-gpu status --json`, `kwick-vpn list/status --json`, `kwick-bluetooth status --json` on the desktop VM |
| arm64, riscv64 | packages built; binaries run under qemu-user (`list`, `mcp serve`): arm64 offers every agent, riscv64 only gemini-cli, node, uv |

Problems seen: `screenshot` fails on this KDE image because KWin refuses spectacle itself ("The process is not authorized to take a
screenshot", also when spectacle is run by hand in Konsole); kwick-mcp reports the error to the agent. `kwick-update status --json` and
`kwick-kernel status --json` did not return JSON on the 0.4.0 headless image (older tools there).

Not verified: real API calls (no keys entered), the Secret Service backend, a successful privileged install through polkit, Codex's own
nested sandbox inside bubblewrap, GNOME and Hyprland consent dialogs (zenity, notify-send), arm64/riscv64 hardware, `kwick-snapshot`
(not present), the rebuilt `kwick-desktop` package (Settings files were copied into the VM).

## Shells (terminal shells, prompt presets, desktop shells)

Own lab container `shells-lab` (image `kwick-vmlab`, `--cpus 6`), VM overlay `shells-1` in the `shells-vm` volume on `d10.qcow2`
(KDE Plasma desktop on the 0.4.0 base, user `kwick` in group `sudo`, virgl, `SMP=2`). The changed files from the tree were copied into
the VM (`kwick-shell`, the shell configs, `shell-helper`, `shell-env`, `kwick-desktop`, `desktop-shells`, `hypr-shell`, the polkit
files, the Settings folder, `kwick-layout`); `add-shell`/`remove-shell` from the current base had to be copied too, because the old
image lacks them and Debian's `fish` and `xonsh` postinst call them. `kwick-quickshell_0.6.5_amd64.deb` came from
`scripts/mkquickshellpkg.sh` (Debian 13 container, Quickshell 0.3.2 source SHA-256 checked, wayland-protocols 1.47 SHA-256 checked).
Before the VM, every shell and preset ran in a `debian:trixie` container under `script(1)` and the raw prompt bytes were checked.

| Area | Result | Evidence |
| --- | --- | --- |
| Install from Debian | `kwick-shell install zsh|fish|elvish|xonsh|starship` as root: installed, added to `/etc/shells` | VM serial log |
| Install from upstream | Nushell 0.117.0 and PowerShell 7.7.0: downloaded, `verified sha256 2b80…9924` and `c89d…a0cb`, links in `/usr/local/bin`, `libicu76` pulled for PowerShell | container and VM logs |
| `list --json`, `prompt list --json`, `desktop shell list --json` | valid JSON, versions read with `dpkg-query --showformat` | Settings parses them |
| Helper refusals | `PKEXEC_UID=1000 shell-helper set root fish` refused ("you can only change your own login shell", rc 2) | VM serial log |
| Settings, terminal shell | in the Plasma session, Use on fish: no terminal, no password dialog, `/etc/passwd` has `/usr/bin/fish` | `shells-settings-terminal-switching.png`, `shells-settings-terminal-fish.png` |
| CLI as the user | `kwick-shell nushell` in a terminal of the active session: switched without a password (polkit rule) | `shells-cli-switch.png` |
| Not in the active session | Settings started from a serial root shell: polkit had no agent and Settings showed the error inline | screenshot kept in the lab |
| Prompt presets | KwickOS, Minimal, Powerline, Starship in bash, BusyBox ash, zsh, fish, Nushell, Elvish, xonsh, PowerShell: colours, layout blue, red character or arrow after a failed command, git branch from `.git/HEAD`; Starship with the KwickOS theme | container log `ctest*.log`, `shells-prompt-powerline-fish.png`, `shells-prompt-powerline-nu-elvish-xonsh-pwsh.png`, `shells-prompt-kwick-all.png` |
| Same prompt everywhere | KwickOS preset, one terminal: zsh, Nushell, Elvish, xonsh and PowerShell all print `kwick@kwick proj` with the folder in the layout blue; bash in this old VM kept the prompt of the user's own `~/.bashrc` from before `prompt.sh` existed (new users get `/etc/skel/.bashrc`, checked in the container) | `shells-prompt-kwick-all.png` |
| Settings, prompt preview | Powerline preview with drawn arrows and the branch glyph; clicking a preset writes `~/.config/kwick/prompt` | `shells-settings-prompt-powerline.png` |
| Settings, desktop shells | cards for Plasma, GNOME Shell, Hyprland + Waybar, Sway + Waybar, Dux Shell, Noctalia; dark and light; 1, 2 or 3 columns by width | `shells-settings-desktop.png`, `shells-settings-desktop-light.png` |
| Dux Shell install from Settings | Install and use: Dux Shell 2.1.2 downloaded as the user, SHA-256 checked, Hyprland made the default session through `shell-helper session` without a password, card "At next login" | `shells-settings-dux-installed.png` |
| Dux Shell on Hyprland | after a reboot SDDM started Hyprland and `hypr-shell` started Dux Shell (Quickshell 0.3.2) with the KwickOS wallpaper; welcome window, then the bar | `shells-dux-welcome.png`, `shells-dux-desktop.png` |
| Appearance | `kwick-layout appearance light` turned the Dux Shell bar light (`dms ipc call theme getMode` prints `light`), and back | `shells-dux-light.png` |
| Live switch | `kwick-desktop shell hyprland` inside Hyprland stopped Dux Shell and started the KwickOS Waybar bar and dock; Switch now on the Dux card in Settings went back (the bar takes about 30 s to appear in this VM) | `shells-live-waybar.png`, `shells-live-dux-from-settings.png` |
| Noctalia | `kwick-noctalia_0.6.5_amd64.deb` from `scripts/mknoctaliapkg.sh` (Noctalia 5.6.0 release SHA-256 checked, 860 build steps on Debian 13's GCC 14), installed; `kwick-desktop shell noctalia` inside Hyprland stopped Waybar and started Noctalia with the KwickOS wallpaper (`noctalia msg wallpaper-get`); `kwick-layout appearance light` made it light (`theme-mode-get` prints `light`); Settings marks it In use | `shells-noctalia-desktop.png`, `shells-noctalia-light.png`, `shells-settings-noctalia-in-use.png` |

Problems found and fixed while testing: QML `top` is a final property of `Item` (preview did not load); kpkg's `dpkg-query -f=FORMAT`
keeps the `=` (versions showed as `=5.2.37`), so the scripts use `--showformat=`; Elvish has no system rc, so `kwick-shell` seeds
`~/.config/elvish/rc.elv` (and `~/.zshrc`) for existing users; xonsh's readline mode maps dark greys to the wrong 256-colour entries,
so it emits the SGR codes itself; bash showed a red prompt character on the first prompt because `~/.bashrc` ended with a failing
test; Debian 13 has wayland-protocols 1.44, Quickshell 0.3.2 and Noctalia 5.6.0 need `ext-background-effect-v1`; Noctalia's
`libqalculate-dev` needs the GnuTLS flavour of `libcurl4-*-dev`; Noctalia keeps the wallpaper in its state, not in `settings.toml`, so
`hypr-shell` sets it once with `noctalia msg wallpaper-set`. Screenshots are in `D:\KwickOS-lab\shells\shots\final` on the test machine.

Not verified for shells: the rebuilt `kwick-desktop` package and a fresh image (files were copied into an old VM); Sway, GNOME and
Plasma reached through the Shells page (only the session switch to Hyprland and back on the CLI); arm64 and riscv64; a polkit
password prompt for installing a shell in the Plasma session (the shells were installed from the serial console first); Dux Shell's
own lock screen, launcher and settings beyond the bar; PowerShell's login-shell mode.

## Not verified

* Steam client window or login screen (blocked by bug 4).
* Cube rotation (the effect loads; nothing was driven), desktop-cube shortcuts.
* sway session (Hyprland was the tiling session tested), `kwick-effects` in GNOME and Hyprland.
* A clean second run of `apt install kwick-desktop` with the fixed postinst on a fresh image; the install of the first run needed the
  two workarounds above, and later runs were reinstalls.
* The newer base image with kpkg multiarch; arm64 and riscv64 (no KVM for them here).
* GPU-specific behavior on real NVIDIA / Intel hardware; the guest GPU is virtio, and the renderer is the host d3d12 driver.
* Desktop ISO built from the current tree: the ISO booted is the published v0.2.0 asset (`kwickos-amd64-desktop.iso`, 1329504256 bytes,
  sha256 `8c89bc36b0606394140c934c74a2cabe3d83e93b0201d464f66f57e14eb66449`, reports KwickOS 0.2.0).

## Reproduce

```
bash tools/vmlab/run.sh
docker exec kwlab bash -c 'cp /usr/local/share/vmlab-asuser.sh /work/pkg/repo/x/asuser.sh'   # after buildrepo
docker exec kwlab buildrepo                                   # packages and signs the working tree into /work/pkg/repo
docker exec -d kwlab serve-repo /work/pkg/repo 8080
docker exec kwlab mkdisk /out/amd64/kwickos-amd64.qcow2 /vm/base24.qcow2 24
docker exec kwlab bash -c 'cd /vm && qemu-img create -f qcow2 -b base24.qcow2 -F qcow2 d1.qcow2'
docker exec -d -e DISK=/vm/d1.qcow2 -e RAM=8192 -e SMP=6 kwlab vm h1
docker exec kwlab sh2 /vm/h1/ser.sock 'wget -qO /etc/apt/keyrings/kwick-dev.asc http://10.0.2.2:8080/kwickos-archive-keyring.asc'
docker exec kwlab sh2 /vm/h1/ser.sock 'apt update && apt install -y kwick-desktop' 3600
docker exec kwlab grab 9 /work/shots/desktop.png            # screenshot of the VM display
docker exec kwlab sh2 /vm/h1/ser.sock 'su kwick -s /bin/sh -c "asuser kwick-effects full"'
docker exec kwlab fx-wobbly h1 ; docker exec kwlab fx-lamp h1 ; docker exec kwlab fx-flame h1
docker exec kwlab shots-layouts h1 vm-gnome GNOME gnome-text-editor
docker exec kwlab shots-tiling h1 vm-tiling Hyprland
docker exec -d -e CDROM=/vm/desktop.iso -e DISP=10 kwlab vm iso2          # UEFI ISO; add -e BIOS=bios for SeaBIOS
```

The sources list the guest used (`/etc/apt/sources.list.d/kwick-dev.sources`): `Types: deb`, `URIs: http://10.0.2.2:8080`, `Suites: stable`,
`Components: main`, `Signed-By: /etc/apt/keyrings/kwick-dev.asc`. The archive key is ephemeral and changes on every `mkrepo` run.
Never run `pkill qemu` in the lab: it also kills the other VMs.
