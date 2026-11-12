# KwickOS

**A Linux distribution smaller and faster than Alpine that installs software
like Debian.**

KwickOS is a headless/server/container Linux built from scratch on the **latest
stable kernel** (7.3.x), with a **5.5 MB** base. It runs `apt install` against
the **unmodified Debian 13 "trixie" archive**: about 69,000 packages, glibc
included, pulled in only when you install something that needs them. The
same base boots as a container, a microVM, a cloud/VM disk, or a live ISO on
**amd64, arm64 and riscv64**.

```console
$ docker run --rm -it ghcr.io/kwickos/kwickos
root@kwick:/# apt update && apt install -y nginx python3
root@kwick:/# systemctl enable --now nginx      # works in containers too
```

<!-- BENCH-SUMMARY -->

## Why it's different

| | Alpine | Debian/Ubuntu | **KwickOS** |
|---|---|---|---|
| base userland | BusyBox + musl `.so` | GNU coreutils + glibc | BusyBox + **static** kinit/kpkg (no libc `.so` at all) |
| package manager | apk (Alpine packages, musl) | apt/dpkg | **kpkg**: `apt`/`dpkg`-compatible, uses Debian's own repos |
| software compatibility | musl rebuilds | everything | everything in Debian (glibc arrives on demand) |
| init | OpenRC | systemd | **kinit**: 120 KB PID 1 that runs systemd unit files |
| boot chain | bootloader + initramfs | GRUB + initramfs-tools | **none**: the kernel is a UEFI app with a 120 KB embedded root finder |
| kernel updates | apk | apt + update-grub + initramfs rebuild | `apt upgrade` copies one EFI file (and keeps the previous one for rollback) |

Key ideas (details in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)):

* **Essential set provided virtually.** The base declares the Debian Essential packages
  (`coreutils`, `bash`, `dpkg`, ...) as satisfied by BusyBox, so real Debian packages
  install unmodified on a 5 MB system.
* **Self-healing compatibility.** If a Debian maintainer script trips over a BusyBox
  difference (`pgrep -u`, `ln -r`, a perl helper), kpkg detects it, installs the GNU
  tool from Debian and retries. GNU tools exist only where software needs them.
* **systemd compatibility without systemd.** Debian's `.service` units,
  `deb-systemd-helper`, `systemd-sysusers` and `systemd-tmpfiles` are handled by kinit,
  so `apt install nginx` gets you a running, enabled, supervised service.
* **One file boots everything.** The EFI-stub kernel embeds kinit, which finds a
  `kwick-root` partition, a `KWICKOS` live medium (erofs + overlay), `root=`, virtiofs/9p,
  or a whole-OS initramfs. There is no GRUB, no dracut, and nothing to regenerate.
* **Built for agent sandboxes.** A full KwickOS microVM boots to a shell in about 0.2 s of
  guest time, and its RAM image is a 2.2 MB file.

## Download / run

Release artifacts (built by CI for each tag) are listed below; replace `amd64` with `arm64` or `riscv64`.

| file | what |
|---|---|
| `kwickos-amd64.iso` | UEFI live ISO (generic kernel, broad hardware); runs from RAM (erofs + overlay) |
| `kwickos-amd64.qcow2` / `.img.zst` | VM/cloud disk: ESP (kernel) + ext4 root, 1 GiB |
| `kwickos-amd64.efi` | the kernel itself (virt flavor): a UEFI app, `-kernel` for QEMU/Firecracker |
| `kwickos-amd64-initramfs.cpio.zst` | the whole OS as an initramfs (microVMs, CI sandboxes) |
| `kwickos-rootfs-amd64.tar.gz` | rootfs tarball (containers, chroots, WSL) |
| `ghcr.io/kwickos/kwickos` | multi-arch container image |

```sh
# VM with persistent disk (UEFI)
qemu-system-x86_64 -M q35,accel=kvm -cpu host -m 512 -bios /usr/share/OVMF/OVMF_CODE.fd \
  -drive file=kwickos-amd64.qcow2,if=virtio -nic user,model=virtio-net-pci -nographic

# microVM, whole OS in RAM: boots in a fraction of a second
qemu-system-x86_64 -M microvm,accel=kvm -cpu host -m 256 -nodefaults -nographic -serial stdio \
  -kernel kwickos-amd64.efi -initrd kwickos-amd64-initramfs.cpio.zst -append "console=ttyS0"

# run one command and power off (CI / agents)
  ... -append "console=ttyS0 kwick.run=apt+update;apt+install+-y+jq"
```

**Apple Silicon:** use the arm64 qcow2 or ISO with UTM, Lima, Parallels or any
Virtualization.framework VM (virtio devices, UEFI). Bare-metal M-series Macs need
Asahi Linux's kernel patches and are not a target yet.

## Using it

It feels like Debian:

```sh
apt update; apt install postgresql        # real Debian packages
apt search redis; apt show nginx; apt list --installed; apt autoremove; apt full-upgrade
dpkg -l; dpkg -L nginx; dpkg -S /usr/sbin/nginx
systemctl status nginx; systemctl restart nginx; journalctl -u nginx -f
service ssh restart
vi /etc/network/interfaces                 # ifupdown syntax (DHCP on eth0 by default)
```

* Recommends are not installed by default (`/etc/kpkg.conf`); use `--install-recommends`.
* The console logs in as root automatically on VM/live images. `rm /etc/kinit/autologin`
  and `passwd` for a password prompt. Install `openssh-server` for remote access.
* `kwick-kernel-install --list | --rollback` manages kernels.

## Building

Requirements: Linux with Docker (and KVM for fast boot tests). For non-native arches,
register binfmt once: `docker run --privileged --rm tonistiigi/binfmt --install all`.

```sh
make builder                       # build container with cross toolchains + QEMU
make ARCH=amd64                    # busybox, kinit, kpkg, kernels (virt+generic), rootfs, images
make boot-test ARCH=amd64          # boots microvm, ram, disk, UEFI disk, UEFI ISO
make container compat ARCH=amd64   # real-world Debian package compatibility matrix
bash bench/container.sh kwickos:0.1.0-amd64   # container benchmarks vs Alpine/Debian/Ubuntu
```

Kernel version is pinned in [`KERNEL_VERSION`](KERNEL_VERSION). The `kernel-watch` workflow
opens a PR whenever kernel.org publishes a new stable release, and the build verifies the
tarball checksum against kernel.org and fails if required config options are lost.

| path | contents |
|---|---|
| `src/kinit/` | init system (C) |
| `src/kpkg/` | package manager (Go) |
| `config/kernel/` | kernel config fragments (common, per-arch, `virt`/`generic`) |
| `config/busybox/` | BusyBox config + GNU-compatibility patches |
| `rootfs/` | files copied into the base system |
| `scripts/` | build steps (userland, kernel, rootfs, images, kernel packages, apt repo) |
| `tests/` | boot matrix, VM functional test, package compatibility matrix |
| `bench/` | benchmarks against Alpine/Debian/Ubuntu |
| `.github/workflows/` | CI build+test for 3 arches, releases (ISO/images/GHCR/apt repo), kernel watch |

## Status and limitations

KwickOS 0.1 is an early release. Known gaps:

* UEFI only: there is no legacy BIOS boot for the ISO/disk (direct `-kernel` boot works everywhere).
* kpkg implements the commonly used apt/dpkg surface. Pinning, holds, foreign multiarch
  architectures, and source packages are not implemented.
* kinit implements the commonly used subset of systemd units. There is no socket
  activation, timers, dependency ordering beyond "start everything in parallel", or D-Bus.
* No SELinux/AppArmor policy. Lockdown, Landlock, Yama and seccomp are enabled.
* riscv64 is tested under QEMU emulation only. The riscv64 generic flavor builds only in release CI.
* A GUI edition is planned separately.

## License

KwickOS sources are MIT-licensed. Images also contain GPL-2.0 software (Linux,
BusyBox) and others; see [LICENSE](LICENSE).
