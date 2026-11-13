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
