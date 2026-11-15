<p align="center">
  <img src="docs/img/kwickos-logo.svg" width="112" alt="KwickOS logo">
</p>

<h1 align="center">KwickOS</h1>

<p align="center"><b>Smaller than Alpine. Installs like Debian.</b></p>

<p align="center">
  <a href="https://github.com/metaspartan/kwickos/releases/latest">Download</a> ·
  <a href="docs/INSTALL.md">Install</a> ·
  <a href="docs/SCREENSHOTS.md">Screenshots</a> ·
  <a href="docs/ARCHITECTURE.md">Architecture</a> ·
  <a href="docs/BENCHMARKS.md">Benchmarks</a>
</p>

<p align="center">
  <img src="docs/img/desktop.png" width="860" alt="KwickOS desktop in the macOS layout">
</p>

## Contents

* [What is KwickOS](#what-is-kwickos)
* [Quick start](#quick-start)
* [Size and speed](#size-and-speed)
* [The desktop](#the-desktop) and [Kwick Effects](#kwick-effects)
* [Optional packages](#optional-packages)
* [Installing](#installing)
* [kfetch](#kfetch)
* [Hardware support](#hardware-support)
* [Building from source](#building-from-source)
* [Documentation](#documentation)
* [License](#license)

## What is KwickOS

* **A tiny base.** 6.2 MB, built from scratch on the latest stable kernel (7.3.x). BusyBox, a 120 KB init (kinit) and an
  apt-compatible package manager (kpkg), all static.
* **Debian's packages, Alpine's too.** `apt install` uses the unmodified Debian 13 "trixie" archive (about 69,000 packages).
  glibc arrives only when something needs it. `apk add` works alongside it.
* **Every architecture.** The same base boots as a container, a microVM, a VM or cloud disk, or a live ISO on amd64, arm64 and
  riscv64.
* **An optional desktop.** `apt install kwick-desktop` adds KDE Plasma 6 with macOS, Windows 11 and Linux layouts. The same
  layouts work on GNOME and Hyprland.
* **Real installers.** A graphical installer, a text installer and a scriptable `kwick-install`, with GRUB, systemd-boot or
  the EFI stub, LUKS and ZFS root.

## Quick start

**Try it in a container:**

```console
$ docker run --rm -it ghcr.io/metaspartan/kwickos
root@kwick:/# apt update && apt install -y nginx python3
root@kwick:/# systemctl enable --now nginx      # works in containers too
```

**Download an image** from the [latest release](https://github.com/metaspartan/kwickos/releases/latest):

| image | use |
|---|---|
| [`kwickos-amd64-desktop.iso`](https://github.com/metaspartan/kwickos/releases/latest/download/kwickos-amd64-desktop.iso) | KDE Plasma 6 live and installer ISO, UEFI and BIOS (also [arm64](https://github.com/metaspartan/kwickos/releases/latest/download/kwickos-arm64-desktop.iso), UEFI) |
| [`kwickos-amd64.iso`](https://github.com/metaspartan/kwickos/releases/latest/download/kwickos-amd64.iso) | headless live ISO, runs from RAM |
| [`kwickos-amd64.qcow2`](https://github.com/metaspartan/kwickos/releases/latest/download/kwickos-amd64.qcow2) | VM and cloud disk |
| [`SHA256SUMS`](https://github.com/metaspartan/kwickos/releases/latest/download/SHA256SUMS) | checksums |

Replace `amd64` with `arm64` or `riscv64`. Raw disks, the kernel as a UEFI app, an initramfs and a rootfs tarball are listed in
[docs/INSTALL.md](docs/INSTALL.md#downloads).

**Install from the ISO:** write it to a USB stick, boot it, and run **Install KwickOS** from the desktop (or `kwick-installer` on
the headless ISO).

**Turn any install into a desktop:**

```sh
apt update && apt install kwick-desktop
reboot
```

**Add the apt repository by hand** (it is preconfigured on KwickOS images):

```sh
curl -fsSL https://metaspartan.github.io/kwickos/kwickos-archive-keyring.asc -o /usr/share/keyrings/kwickos-archive-keyring.asc
printf 'Types: deb\nURIs: https://metaspartan.github.io/kwickos\nSuites: stable\nComponents: main\nSigned-By: /usr/share/keyrings/kwickos-archive-keyring.asc\n' > /etc/apt/sources.list.d/kwickos.sources
```

Daily use of the base system (apt, services, networking, what is in the base and what is one `apt install` away) is in
[docs/BASE.md](docs/BASE.md).

## Size and speed

| | Alpine 3.24.4 | **KwickOS** |
|---|---:|---:|
| container image (uncompressed / gzip) | 8.43 / 3.72 MB | **6.21 / 2.91 MB** |
| VM boot to shell prompt (QEMU/KVM, live ISO) | 3.23 s | **1.04 s** |
| memory in use after boot | 66.1 MiB | **37.8 MiB** |
| live ISO | 70 MB | **53 MB** |
| packages available | ~20k (musl) | **~69k (Debian 13, glibc)** |

Method, more rows and the Debian and Ubuntu comparison: [docs/BENCHMARKS.md](docs/BENCHMARKS.md). Real Debian software
(PostgreSQL, MariaDB, Docker, OpenJDK, Node.js and more) passes a 31-package matrix: [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).
How it gets this small: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## The desktop

`kwick-layout macos|windows|linux` switches the whole look at once: window buttons, panel or dock, fonts, icons, wallpaper and the
Files sidebar.

| macOS | Windows 11 | Linux |
|---|---|---|
| <img src="docs/img/layout-macos.png" width="280" alt="macOS layout"> | <img src="docs/img/layout-windows.png" width="280" alt="Windows layout"> | <img src="docs/img/layout-linux.png" width="280" alt="Linux layout"> |

* **KDE Plasma 6** is the default, with the KwickOS Settings app, a dock, an icon theme and fonts per layout.
* **GNOME** gets the same three layouts.
* **Hyprland** (`kwick-hyprland`) gets the same three layouts, each with its own waybar.

`kwick-gpu` installs the right GPU drivers, and `steam` installs native Steam. More: [docs/DESKTOP.md](docs/DESKTOP.md) and the
[screenshot gallery](docs/SCREENSHOTS.md).

## Kwick Effects

Native effects with presets (`kwick-effects off|subtle|fluid|full`) or one toggle at a time (`kwick-effects set wobbly on`). They
run on KDE, GNOME and Hyprland and need a GPU compositor.

| 3D desktop cube | Flame |
|---|---|
| <img src="docs/img/effects-cube.gif" width="420" alt="3D desktop cube"> | <img src="docs/img/effects-flame.gif" width="420" alt="Flame close"> |
| **3D open/close** | **Wobbly windows** |
| <img src="docs/img/effects-3dopen.gif" width="420" alt="3D flip open"> | <img src="docs/img/effects-wobbly.gif" width="420" alt="Wobbly windows"> |

Also: magic lamp, dissolve, door and tilt open/close, five flame styles, blur, translucency, dimmed inactive windows and Cover Flow
Alt+Tab. All options and GIFs: [docs/EFFECTS.md](docs/EFFECTS.md).

## Optional packages

Nothing below is in the base image. Each one is a small package or command that installs its pieces on demand.

| package | what it does | install | docs |
|---|---|---|---|
| `kwick-essentials` | common tools in one step: curl, jq, sudo, dnsutils, net-tools, build-essential and similar | `apt install kwick-essentials` | [BASE](docs/BASE.md) |
| `kwick-gaming` | Bazzite-style gaming modules: Steam, Game Mode session, Proton-GE, launchers, overlays, handhelds, streaming | `apt install kwick-gaming` (included with the desktop) | [GAMING](docs/GAMING.md) |
| `kwick-pen` | Kali-style security toolkit from Debian and pinned upstream sources, for authorized testing | `apt install kwick-pen` | [PEN](docs/PEN.md) |
| `kwick-agents` | AI agent tooling, starting with the Cybara agent platform | `apt install kwick-agents` | [AGENTS](docs/AGENTS.md) |
| `kwick-storage`, `kwick-zfs` | NAS modules: prebuilt OpenZFS, RAID, SnapRAID arrays, SMB and NFS shares, Cockpit | `apt install kwick-storage`, then `kwick-storage install zfs` | [STORAGE](docs/STORAGE.md) |
| `kwick-vpn` | import WireGuard and OpenVPN profiles, add Tailscale, Mullvad, Proton, ZeroTier or NetBird | in the base: `kwick-vpn install tailscale` | [VPN](docs/VPN.md) |
| `kwick-brew` | Homebrew (Linuxbrew) with the official installer, amd64 and arm64 | in the base: `kwick-brew install` | [BASE](docs/BASE.md#homebrew) |
| `kwick-gpu` | detects GPUs and installs AMD, Intel or NVIDIA drivers and firmware | `apt install kwick-gpu` (included with the desktop) | [HARDWARE](docs/HARDWARE.md) |
| `kwick-darling` | runs macOS command-line programs with Darling (amd64) | `apt install kwick-darling` | [DARLING](docs/DARLING.md) |

Most of them share one interface: `list`, `status`, `install <module...>`, `remove <module...>` and `all`.

## Installing

The live desktop opens **Install KwickOS** at login: one decision per screen, keyboard-only friendly, with a `--dry-run` mode.

| Select a disk | Installing |
|---|---|
| <img src="docs/img/installer-disk.png" width="420" alt="Installer disk selection"> | <img src="docs/img/installer-progress.png" width="420" alt="Installer progress"> |

* **Text installer.** `kwick-installer` opens a plain-terminal installer outside a desktop session, for example on the headless ISO.
* **Scriptable.** Both front ends call `kwick-install`, which takes every choice as a flag and reads secrets only from files.
* **Boot loaders.** The EFI stub (the kernel is the boot entry), GRUB (UEFI and BIOS, any file system, LUKS2) or systemd-boot.
* **File systems.** ext4, btrfs, xfs or a ZFS root (`kwick-install --fs zfs`), optionally encrypted with LUKS.

Details, flags and all downloads: [docs/INSTALL.md](docs/INSTALL.md).

## kfetch

`kfetch` is a 10 KB shell script that prints a system summary in about 15 ms, with `--small` and `--json` modes.
[More](docs/BASE.md#kfetch).

<img src="docs/img/kfetch.png" width="640" alt="kfetch output">

## Hardware support

| target | status |
|---|---|
| amd64 and arm64 VMs (QEMU/KVM, UTM, Lima, Parallels), containers | verified |
| riscv64 QEMU virt (OpenSBI, UEFI) | verified in CI under emulation |
| AMD, Intel and older NVIDIA GPUs | mainline drivers, not tested on real cards by the project |
| NVIDIA Turing and newer | built, not run on a GPU |
| Apple Silicon M1 and M2 (Asahi kernel) | built, not yet booted on a Mac |
| NVIDIA DGX Spark (GB10 kernel flavor) | built, not yet booted |
| Banana Pi BPI-F3 (SpacemiT K1, riscv64) | built, not yet booted |

The project has no hardware lab, so "built" means it compiles and passes static checks only. Per-device detail:
[docs/HARDWARE.md](docs/HARDWARE.md).

## Building from source

Needs Linux with Docker, and KVM for fast boot tests.

```sh
make builder                       # build container with cross toolchains and QEMU
make ARCH=amd64                    # busybox, kinit, kpkg, kernels, rootfs, images
make boot-test ARCH=amd64          # boot matrix: microvm, RAM, disk, UEFI disk, UEFI ISO
```

Cross builds, the source tree, releases and CI: [docs/BUILDING.md](docs/BUILDING.md).

## Documentation

| doc | contents |
|---|---|
| [INSTALL](docs/INSTALL.md) | downloads, installers, boot loaders, apt repository |
| [BASE](docs/BASE.md) | using the base system, what is included, kfetch, Homebrew |
| [DESKTOP](docs/DESKTOP.md) | layouts, Settings, icons, fonts, gaming, GPUs, Darling |
| [EFFECTS](docs/EFFECTS.md) | every effect, option and GIF |
| [SCREENSHOTS](docs/SCREENSHOTS.md) | the full screenshot gallery |
| [ARCHITECTURE](docs/ARCHITECTURE.md) | kinit, kpkg, the boot path, limitations |
| [BENCHMARKS](docs/BENCHMARKS.md) and [COMPATIBILITY](docs/COMPATIBILITY.md) | measurements and the package matrix |
| [HARDWARE](docs/HARDWARE.md) | kernel flavors, GPUs, Apple Silicon, GB10, riscv64 boards |
| [GAMING](docs/GAMING.md), [PEN](docs/PEN.md), [AGENTS](docs/AGENTS.md), [STORAGE](docs/STORAGE.md), [VPN](docs/VPN.md), [DARLING](docs/DARLING.md) | optional packages |
| [BUILDING](docs/BUILDING.md) and [VERIFICATION](docs/VERIFICATION.md) | building from source, CI, and what was tested |

## License

KwickOS sources are MIT-licensed. Images also contain GPL-2.0 software (Linux, BusyBox) and others; see [LICENSE](LICENSE).

* The native KWin effect plugins link against KWin (GPL-2.0-or-later). The Flip plugin's source in `src/kwin-flip` is MIT, and its
  compiled `kwick_flip.so` (like the third-party KDE-Rounded-Corners plugin) is distributed under the GPL-2.0-or-later, with a note
  in `/usr/share/doc/kwick-flip/copyright`.
* OpenZFS is CDDL. It is never built into the kernel. The modules ship only in the separate `kwick-zfs-modules-*` packages with the
  CDDL text, and nothing ZFS-related is installed unless you install it. See [docs/STORAGE.md](docs/STORAGE.md#licensing).
