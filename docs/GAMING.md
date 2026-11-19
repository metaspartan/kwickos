# Gaming: KwickOS compared with Bazzite

`kwick-gaming` (package `kwick-gaming`, source in `desktop/gaming/rootfs`) is the KwickOS answer to Bazzite's gaming images. Bazzite is an
immutable Fedora Atomic image with Valve's patched stack and `ujust` recipes. KwickOS is Debian 13, so the same features are modules
you install on demand: Debian packages first, Flathub next, a pinned upstream release (version and sha256) only where neither exists.

```
kwick-gaming list | status | install <module...> | remove <module...> | all
kwick-gaming session boot-on | boot-off | quick-on | quick-off | hud off|fps|compact|full | status
```

Settings, Gaming shows each module with its state and an Install or Remove button. Status values: installed, partial, unavailable
(wrong architecture or missing kernel support).

Source for the Bazzite side: the Bazzite docs (docs.bazzite.gg) and its `ujust` recipe files in ublue-os/bazzite.

## Parity table

| Feature | Bazzite way | KwickOS way | Status |
|---|---|---|---|
| Steam | Fedora Steam RPM plus Steam Deck patches | `steam` module: Debian `steam-installer` via `kwick-gpu steam` (i386 multiarch, udev, uinput), Flathub fallback | Done (x86_64 only) |
| Gaming Mode session | `gamescope-session-plus` and `gamescope-session-steam`, Steam Deck UI | `gamescope-session` module: `Gaming Mode` session on SDDM, `kwick-gamescope-session`, Gamescope 3.16 from `trixie-backports` (Flathub extension as the fallback) | Done on x86_64 |
| Boot to Gaming Mode, Switch to Desktop | `bazzite-deck` image, `steamos-manager` / `steamosctl` | `kwick-gaming session boot-on`, `quick-on`; `steamos-session-select`, a hidden one-shot desktop session, SDDM `Relogin` drop-in | Done (SDDM only), see [Gaming Mode](#gaming-mode) |
| Steam's SteamOS hooks | `steamos-select-branch`, `steamos-update`, `jupiter-biosupdate`, `steamos-polkit-helpers` | Same names as stubs: one branch (`stable`), "no update" (exit 7), BIOS no-op; KwickOS updates come from Settings | Done |
| Crash fallback | short-session tracker in `gamescope-session-plus` | 3 sessions under 60 s (1 when only quick switching is on) open the desktop and show a notification | Done |
| Performance overlay | `mangoapp`, driven by Steam's quick access menu | Steam's slider when `mangoapp` exists; Debian 13 and the MangoHud release ship none, so Settings sets a MangoHud preset for games in Gaming Mode | Partial |
| TDP in Steam's quick access menu | `steamos-manager`, HHD | HHD (`handheld` module) and Decky plugins; no `steamos-manager` | Partial |
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

## Gaming Mode

Gaming Mode is Steam's controller-first interface (`steam -gamepadui -steamos3 -steampal -steamdeck`) running inside Gamescope as its
own Wayland session, the way SteamOS, Bazzite and ChimeraOS do it. Install it from Settings, Gaming (Set Up) or with
`kwick-gaming install gamescope-session`. That installs Steam if needed and Gamescope from `trixie-backports` (the module adds that
source; it is in `contrib` there), and writes:

| File | Purpose |
|---|---|
| `/usr/share/wayland-sessions/kwick-gamemode.desktop` | "Gaming Mode" on the login screen, runs `kwick-gamescope-session` |
| `/usr/share/wayland-sessions/kwick-desktop-oneshot.desktop` | hidden; the desktop entered from Gaming Mode (`/usr/lib/kwick/gaming/desktop-oneshot` starts the normal desktop session) |
| `/usr/share/applications/kwick-return-to-gamemode.desktop`, plus a copy in `~/Desktop` | "Return to Gaming Mode" (`steamos-session-select gamescope`) |
| `/etc/xdg/autostart/kwick-gamemode-notice.desktop` | tells you on the desktop when Gaming Mode failed to start |

Settings, Gaming has the switches. The same from a shell:

| Setting | Command | Effect |
|---|---|---|
| Boot into Gaming Mode | `kwick-gaming session boot-on` / `boot-off` | SDDM logs in to Gaming Mode at boot and after every desktop logout |
| Switch without signing in | `kwick-gaming session quick-on` / `quick-off` | Switch to Desktop and Return to Gaming Mode skip the login screen; always on while booting into Gaming Mode |
| Performance overlay | `kwick-gaming session hud off`, `fps`, `compact` or `full` | MangoHud preset 1, 2 or 4 for games in Gaming Mode (per user, in `~/.config/kwick/gamescope.conf`) |

Switching. Both switches are opt-in. With both off, Switch to Desktop and Return to Gaming Mode log out to the login screen. Opting
in records the user in `/var/lib/kwick-gaming/gamemode-user` and installs `/etc/sudoers.d/kwick-gamemode`, which lets only that
user run `kwick-gaming session-select game|desktop|desktop-persistent|settle` without a password.

* `steamos-session-select` is what Steam's power menu calls (`plasma`, `plasma-wayland-persistent`, `gamescope`, ...). It has
  `session-select` write `/etc/sddm.conf.d/90-kwick-gamemode.conf` (`[Autologin]`, `Relogin=true`, the target session) and ends the
  current session: in Gaming Mode `steam -shutdown`, then Gamescope; on Plasma `org.kde.Shutdown.logout`; on GNOME
  `gnome-session-quit`; otherwise `loginctl terminate-session`. SDDM rereads its configuration for every new display, so it logs
  straight in to the target.
* Each session settles the drop-in when it starts: with boot on it points back to Gaming Mode (logging out of the desktop returns to
  it, as on SteamOS); with only quick switching on it is removed (a later logout or reboot shows the login screen).
* A `persistent` desktop request from Steam turns boot into Gaming Mode off and keeps quick switching on.
* The drop-in is named `90-` so it overrides `20-autologin.conf` and the `30-kwick-session.conf` of `kwick-desktop switch`. The package
  postinst runs `kwick-gaming session sync`, which migrates the old `30-kwick-gamemode.conf` and `boot-user`.

Crash fallback. `kwick-gamescope-session` logs to `~/.local/state/kwick/gamemode.log` and counts sessions that end within 60 seconds
without a switch request. After 3 of them (after 1 when only quick switching is on, since nothing would log in again) it switches to
the desktop and leaves a marker that the autostart entry turns into a notification. If nothing was opted in, a failed Gaming Mode
ends on the login screen. SDDM treats a session exit status of 1 as an authentication error and then neither logs in again nor
restarts the greeter (black screen), so the session script always exits 0.

Steam hooks. On SteamOS, Steam calls `steamos-select-branch`, `steamos-update`, `jupiter-biosupdate` and the same names under
`/usr/bin/steamos-polkit-helpers/`. The stubs report one branch, "no update" (exit 7, as on ChimeraOS) and a BIOS no-op, so Steam's
System settings work and never try to update the OS.

Environment. The session exports what `gamescope-session-plus` and `gamescope-session-steam` export for Steam (multiple Xwaylands,
tearing, VRR, NIS, dynamic frame limiter, volume keys, the Steam keyboard input method, `ENABLE_GAMESCOPE_WSI`) and runs
`gamescope --steam --xwayland-count 2`. `/etc/kwick/gamescope.conf` and `~/.config/kwick/gamescope.conf` can set
`KWICK_GAMESCOPE_ARGS` (for example `--steam -W 1920 -H 1080 -r 120 --adaptive-sync`) and `KWICK_STEAM_ARGS`.

Add-ons on the same page: Decky Loader (`decky`, plugins in Steam's quick access menu) and Handheld support (`handheld`, HHD; the page
names the device when its DMI strings match a known handheld). Controllers work through Steam Input in Gaming Mode; the `controllers`
module adds the udev rules for the desktop.

Gaps: no `steamos-manager`, so Steam's own TDP, GPU clock and charge limit sliders do nothing (use HHD or a Decky plugin); no
`mangoapp`, so Steam's Performance Overlay slider does nothing (use the Settings overlay); no InputPlumber; HDR is not enabled.

## Architecture notes

- Steam, Proton-GE, Decky, Gaming Mode and HHD are x86_64 only. On arm64 and riscv64 they print `x86-only` and exit; Debian 13 ships no x86
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
