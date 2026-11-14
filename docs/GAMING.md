# Gaming: KwickOS compared with Bazzite

`kwick-gaming` (package `kwick-gaming`, source in `desktop/gaming/rootfs`) is the KwickOS answer to Bazzite's gaming images. Bazzite is an
immutable Fedora Atomic image with Valve's patched stack and `ujust` recipes. KwickOS is Debian 13, so the same features are modules
you install on demand: Debian packages first, Flathub next, a pinned upstream release (version and sha256) only where neither exists.

```
kwick-gaming list | status | install <module...> | remove <module...> | all
kwick-gaming session boot-on | boot-off | status
```

Settings, Gaming shows each module with its state and an Install or Remove button. Status values: installed, partial, unavailable
(wrong architecture or missing kernel support).

Source for the Bazzite side: the Bazzite docs (docs.bazzite.gg) and its `ujust` recipe files in ublue-os/bazzite.

## Parity table

| Feature | Bazzite way | KwickOS way | Status |
|---|---|---|---|
| Steam | Fedora Steam RPM plus Steam Deck patches | `steam` module: Debian `steam-installer` via `kwick-gpu steam` (i386 multiarch, udev, uinput), Flathub fallback | Done (x86_64 only) |
| Game Mode session | `gamescope-session-steam`, Steam Deck UI at boot | `gamescope-session` module: `Steam Game Mode` session on SDDM/GDM, `kwick-gamescope-session`, `steamos-session-select` shim for Switch to Desktop | Done on x86_64; Debian 13 has no `gamescope` package, so it uses the Flathub Steam gamescope extension unless apt offers one |
| Boot to Game Mode | Separate `bazzite-deck` image | `kwick-gaming session boot-on` writes an SDDM autologin drop-in, `boot-off` reverts | Done (SDDM only) |
| Handhelds | HHD, InputPlumber, per-device kernel patches | `handheld` module: pinned `hhd` from PyPI in `/opt/kwick-hhd` with Debian python deps, udev rules, `hhd@USER` service | Partial: HHD yes, Bazzite's device kernel patches no |
| Proton-GE | ProtonUp-Qt, `ujust` Proton-GE updater | `proton` module: ProtonUp-Qt (Flathub) plus pinned GE-Proton in `/usr/share/steam/compatibilitytools.d` | Done (x86_64) |
| Launchers | Lutris, Heroic, Bottles preinstalled | `launchers` module: Lutris from Debian, Heroic and Bottles from Flathub | Done |
| Overlays | MangoHud, vkBasalt, GameMode, ScopeBuddy | `overlay` module: Debian `mangohud`, `vkbasalt`, `gamemode`, `goverlay` (i386 variants when multiarch is on) | Done; no ScopeBuddy |
| Waydroid | Preinstalled, binder in kernel | `waydroid` module: installs prerequisites; Debian 13 has no package and our kernel has no binder | Blocked: needs binder in `config/kernel` and the upstream repo |
| Decky Loader | `ujust` installer | `decky` module: pinned PluginLoader release, `plugin_loader.service`, CEF debug flag for native and Flatpak Steam | Done (x86_64) |
| Controllers | `steam-devices`, xone, xpadneo, InputPlumber | `controllers` module: `steam-devices`, `joystick`, uinput and hidraw rules, Bluetooth pairing fix; kernel xpad, hid-playstation, hid-nintendo, hid-steam | Partial: xone and xpadneo are not in Debian 13 |
| ntsync, fsync | Kernel with ntsync, Wine/Proton use it | `tweaks` module loads `ntsync` and sets its permissions; kernel has `CONFIG_NTSYNC=m`; fsync comes from Proton | Done (needs Linux 6.14+) |
| CPU scheduler | `scx_lavd`/`scx_bpfland` via sched_ext, CFS tuning | Not available: our kernel has no sched_ext; `tweaks` sets I/O schedulers (none for NVMe, mq-deadline for SSD, bfq for HDD) | Gap |
| zram and sysctl | zram-generator, `vm.max_map_count`, split lock, swappiness | `20-kwick-gaming.conf` always on; `tweaks` adds `systemd-zram-generator` (zstd), VM sysctls, inotify limits, earlyoom | Done |
| Limits | High `nofile` | `limits.d/20-kwick-gaming.conf` (1048576) | Done |
| Streaming | Sunshine via `ujust setup-sunshine`, Moonlight Flatpak | `streaming` module: pinned Sunshine `.deb` built for Debian trixie (amd64 and arm64), Moonlight from Flathub | Done |
| OpenRGB | `ujust install-openrgb` (AppImage) | `rgb` module: OpenRGB Flatpak, udev rules pinned to a git commit, `i2c-dev`, uaccess for I2C, `ratbagd` and Piper | Done |
| Input remapping | Steam Input, HHD, InputPlumber | Steam Input and HHD; no InputPlumber (not in Debian 13) | Partial |
| Other ujust recipes | SteamCMD, EmuDeck, OpenRazer, OpenTabletDriver, CoolerControl, Boxtron, DisplayLink | Use Lutris and Flathub directly; `kwick-gaming` covers the gaming set only | Out of scope |
| Image variants | Desktop, Deck, HTPC, handheld, NVIDIA | One desktop image, plus modules: `gamescope-session` with `boot-on` is the Deck/HTPC mode, `handheld` the handheld mode, `kwick-gpu` handles NVIDIA | Done by composition |
| Immutability and rollback | rpm-ostree, atomic updates | Not offered; `kwick-gaming remove` undoes a module | Different design |

## Architecture notes

- Steam, Proton-GE, Decky, Game Mode and HHD are x86_64 only. On arm64 and riscv64 they print `x86-only` and exit; Debian 13 ships no x86
  emulator (no fex-emu, no box64).
- Launchers, overlay, controllers, streaming, rgb and tweaks work on arm64 too (Sunshine ships an arm64 build). On riscv64 only the Debian and
  Flathub pieces that exist for it install.

## Pinned upstream fetches

All pins are in `desktop/gaming/rootfs/usr/lib/kwick/gaming/pins.env`.

| Item | Version | Integrity |
|---|---|---|
| GE-Proton | GE-Proton11-12 | sha256 |
| Decky Loader PluginLoader | v3.3.1 | sha256 |
| Sunshine (Debian trixie build) | 2026.914.233613 | sha256 per architecture |
| HHD (PyPI sdist) | 4.1.12 | sha256 through `pip --require-hashes` |
| OpenRGB udev rules | release_1.1 | git commit `8e16de27` (immutable raw URL) |

## Building

`scripts/mkgamingpkg.sh` builds the architecture-independent `kwick-gaming_<version>_all.deb`. `kwick-desktop` depends on it and installs the
`overlay` module after first boot. The release workflow and `tools/vmlab/buildrepo.sh` build it next to the other packages.
