# Shells

KwickOS lets you switch two kinds of shell, from Settings or from a terminal:

* the **terminal shell**: the login shell your terminals run (zsh, bash, fish, Nushell and others), with one prompt look in all of them;
* the **desktop shell**: what draws your desktop (Plasma, GNOME Shell, Hyprland with Waybar, Sway, and Quickshell-based shells on Hyprland).

Settings has both under **Shells**. The CLI is `kwick-shell` for terminal shells and `kwick-desktop shell` (also reachable as
`kwick-shell desktop`) for desktop shells.

## Terminal shells

```
kwick-shell                          your shell, the default for new users, the prompt preset and what is available
kwick-shell list [--json]            every shell with its version, source and state (* marks yours)
kwick-shell fish                     make fish your login shell, installing it first
kwick-shell install nushell          install without switching
kwick-shell --user NAME zsh          change another user's shell (root)
kwick-shell --default zsh            shell for users created from now on (root)
kwick-shell --current                print the name of your login shell
```

| Shell | Name | Source on KwickOS | Version | License |
| --- | --- | --- | --- | --- |
| Z shell | `zsh` | Debian 13 `zsh`, `zsh-autosuggestions`, `zsh-syntax-highlighting` | 5.9 | MIT-like (Zsh licence) |
| GNU Bash | `bash` | Debian 13 `bash` (the base has an on-demand stub) | 5.2.37 | GPL-3.0-or-later |
| fish | `fish` | Debian 13 `fish` | 4.0.2 | GPL-2.0-only |
| BusyBox ash | `ash` | built into the base | 1.37.0 | GPL-2.0-only |
| Nushell | `nushell` (`nu`) | official release, pinned and checked with SHA-256 | 0.117.0 | MIT |
| Elvish | `elvish` | Debian 13 `elvish` | 0.21.0 | BSD-2-Clause |
| xonsh | `xonsh` | Debian 13 `xonsh` | 0.19.4 | BSD-2-Clause |
| PowerShell | `powershell` (`pwsh`) | official release, pinned and checked with SHA-256 (amd64, arm64) | 7.7.0 | MIT |

* Debian shells come from the Debian 13 archive through `apt`, so apt's signed repositories vouch for them.
* Nushell and PowerShell are not in Debian 13. `kwick-shell` downloads the official GitHub release for the machine
  (`nu-0.117.0-<arch>-unknown-linux-musl`, or the glibc build on riscv64; `powershell-7.7.0-linux-x64|arm64`), compares its SHA-256 with
  the value pinned in `kwick-shell` (copied from upstream's `SHA256SUMS` and `hashes.sha256`), and refuses to install on a mismatch.
  They go to `/opt/kwick-shells/<name>/<version>` with `/usr/local/bin/nu` and `/usr/local/bin/pwsh` as links, and the source URL and
  hash are recorded in `.kwick-source` next to them. PowerShell has no riscv64 build, so it is hidden there. Its telemetry and update
  check are turned off (`/etc/profile.d/30-kwick-shells.sh`).
* `dash` is not offered: Debian's `dash` package owns `/usr/bin/sh` and would replace BusyBox `ash` as the system `/bin/sh`.
  `ash` is the POSIX choice.
* A change applies at the next login. Typing the shell's name starts it in the current terminal.

### Switching without a terminal or password

Settings never opens a terminal to switch. It calls a small privileged helper, `/usr/lib/kwick/shell-helper`, through `pkexec`:

* `shell-helper set USER SHELL` changes the login shell, the same thing `chsh` does. The polkit rule
  `/usr/share/polkit-1/rules.d/50-kwickos-shell.rules` allows it without a password only for the active local session, only when `USER`
  is the caller, and only for the eight shell names. The helper checks again that `USER` matches `PKEXEC_UID` and refuses to install
  anything on this path.
* `shell-helper install SHELL` installs a shell or Starship. It needs an administrator password (polkit `auth_admin_keep`), unless
  `sudo` works without one.
* `shell-helper session kde|gnome|hyprland|sway` makes that session the default at the login screen (`kwick-desktop switch`). The
  rule allows it without a password for members of `sudo` or `wheel` in the active local session; Settings uses it when a desktop
  shell needs another session.
* From a terminal, `kwick-shell fish` uses the same helper, so switching between installed shells does not ask for a password either.
  Without polkit it falls back to `sudo`.

### Same environment in every shell

* `PATH` and the rest of the login environment come from `/etc/profile` and `/etc/profile.d` for every shell. That includes the
  Homebrew, `kwick-agents` (`~/.local/bin`) and `kwick-arch` (`/usr/local/lib/kwick-arch/bin`) entries.
* POSIX shells read those files themselves. zsh, fish, Nushell, Elvish, xonsh and PowerShell run `/usr/lib/kwick/shell-env` once,
  when `KWICK_ENV` is not set yet: it sources `/etc/profile` in `sh` and prints the resulting variables, which the shell imports.
  `/etc/profile` sets `KWICK_ENV=1`, so terminals inside a desktop session, which already inherit that environment, skip the step.
* The aliases are the same everywhere: `ls` with colour, `ll`, `la`, `l`, `grep` with colour, `..` and `...` where the shell allows it
  (Nushell keeps its own structured `ls` and gets `ll` and `la`).

| Shell | KwickOS file |
| --- | --- |
| ash, bash | `/usr/share/kwick/shell/prompt.sh` (from `/etc/ashrc` and `~/.bashrc`) |
| zsh | `/usr/share/kwick/zsh/kwick.zsh` (from `/etc/zsh/zshrc` and `~/.zshrc`) |
| fish | `/usr/share/fish/vendor_conf.d/kwick.fish` |
| Nushell | `/usr/share/nushell/vendor/autoload/kwick.nu` |
| Elvish | `/usr/share/elvish/lib/kwick.elv`, loaded by `use kwick` in `~/.config/elvish/rc.elv` (seeded from `/etc/skel`) |
| xonsh | `/etc/xonsh/rc.d/kwick.xsh` |
| PowerShell | `/usr/share/kwick/shell/kwick.ps1`, loaded from `$PSHOME/profile.ps1` |

### Prompt presets

```
kwick-shell prompt                   the current preset
kwick-shell prompt list [--json]     presets, with a sample of each in a terminal
kwick-shell prompt minimal           use a preset in every shell (stored in ~/.config/kwick/prompt)
kwick-shell prompt kwick --default   default for every user (/etc/kwick/prompt, root)
```

| Preset | Look |
| --- | --- |
| `kwick` (default) | `user@host folder %` in zsh and `$` elsewhere, like Terminal on macOS: grey `user@host`, the folder in bold in the layout colour (blue for macOS, Fluent blue for Windows, indigo for Linux), the prompt character red after a failed command, red `user@host` for root |
| `minimal` | the folder and a `❯` arrow in the layout colour, red after an error |
| `powerline` | powerlevel-style segments: `user@host`, the folder on the layout colour and the git branch, joined by powerline arrows; the last arrow turns red after an error |
| `starship` | [Starship](https://starship.rs) 1.22.1 from Debian 13 (ISC) with the KwickOS theme `/usr/share/kwick/shell/starship.toml` (used when you have no `~/.config/starship.toml`); picking it installs Starship |

* Every preset is written natively for each shell, so no shell needs a framework. The git branch is read from `.git/HEAD` without
  running `git`.
* `KWICK_PROMPT=minimal` in the environment overrides the file for one session.
* Without a colour terminal, or with `NO_COLOR`, the prompts are plain text. On the Linux console and without UTF-8, `❯` becomes `>`
  and the powerline arrows are left out.
* The powerline arrows and the branch symbol need a font with powerline glyphs. JetBrains Mono and Cascadia Code, the KwickOS
  terminal fonts, have them.
* Starship has no init for BusyBox `ash`, so `ash` shows the `kwick` preset when `starship` is selected.

## Desktop shells

```
kwick-desktop shell [list] [--json]   desktop shells, * marks the one used at login
kwick-desktop shell dms               switch to Dux Shell (installs it first; live when you are already in Hyprland)
kwick-desktop shell install noctalia  install without switching
kwick-desktop shell current           the desktop shell used at login
kwick-shell desktop ...               the same commands
```

| Name | Desktop shell | Session | What it is | Source | License |
| --- | --- | --- | --- | --- | --- |
| `plasma` | KDE Plasma | Plasma | the default KwickOS desktop | Debian 13 | GPL-2.0-or-later |
| `gnome` | GNOME Shell | GNOME | GNOME with the KwickOS dock and effects | Debian 13 | GPL-2.0-or-later |
| `hyprland` | Hyprland + Waybar | Hyprland | KwickOS bar, dock and Search on Hyprland 0.49.0 | `kwick-hyprland` | BSD-3-Clause |
| `sway` | Sway + Waybar | Sway | the same bar on Sway | Debian 13 | MIT |
| `dms` | Dux Shell 2.1.2 | Hyprland | Material 3 shell built on Quickshell (formerly DankMaterialShell) | official release, pinned and checked with SHA-256, plus `kwick-quickshell` | MIT |
| `noctalia` | Noctalia 5.6.0 | Hyprland | native Wayland shell (C++, no Qt) | `kwick-noctalia`, built from the pinned release | MIT |

* `plasma`, `gnome`, `sway` and `hyprland` make that session the default at the login screen, like `kwick-desktop switch`.
* `hyprland`, `dms` and `noctalia` all run in the Hyprland session and only change what draws the bar. The choice is per user
  (`~/.config/kwick/hypr-shell`), and inside Hyprland it switches at once: `/usr/lib/kwick/hypr-shell` stops Waybar, the dock, mako and
  swaybg and starts the new shell, or the other way round. Outside Hyprland it applies at the next login.
* Hyprland itself still comes from `kwick-hyprland`; the KwickOS key bindings (Search, capture, clipboard, layouts) keep working
  with every bar.
* Appearance: `kwick-layout appearance dark|light` (and the Appearance page) also switch Dux Shell
  (`dms ipc call theme dark|light`) and Noctalia (`noctalia msg theme-mode-set dark|light`). The first start seeds each shell with
  the current appearance and the KwickOS wallpaper (Dux Shell through `~/.local/state/dms/session.json`, Noctalia through
  `noctalia msg wallpaper-set`); after that the shells keep their own settings.

### Quickshell and the shells built on it

[Quickshell](https://quickshell.org) is a QML toolkit for desktop shells (LGPL-3.0). It is not in Debian 13 (only in trixie-backports
and forky), so KwickOS builds `kwick-quickshell` from the pinned v0.3.2 release (`scripts/mkquickshellpkg.sh`, source SHA-256
checked) against Debian 13's Qt 6.8.2. Quickshell 0.3.2 needs `ext-background-effect-v1` from wayland-protocols 1.45 or later and
Debian 13 has 1.44, so the build uses wayland-protocols 1.47 (pinned, SHA-256 checked) at build time only. The crash handler is off
because `cpptrace` is not in Debian 13.

Which Quickshell shells KwickOS offers, as of November 2026:

| Shell | Latest | License | On Debian 13 with Qt 6.8.2 | Offered |
| --- | --- | --- | --- | --- |
| Dux Shell (formerly DankMaterialShell) | v2.1.2 | MIT | runs on stock Quickshell; tested on `kwick-quickshell` 0.3.2 with Qt 6.8.2 | yes, `dms` |
| Noctalia | v5.6.0 | MIT | v5 is no longer Quickshell but a native C++ shell; `scripts/mknoctaliapkg.sh` builds it on Debian 13 (with the same wayland-protocols 1.47 at build time) | yes, `noctalia` |
| Noctalia v4 (legacy Quickshell version) | v4.7.7 | MIT | needs Noctalia's own `noctalia-qs` Quickshell fork; the final v4 release | no |
| Caelestia | v2.5.0 | GPL-3.0 | its C++ plugin requires Qt 6.9 and `m3shapes`, and Quickshell from git | no |
| end-4 illogical-impulse | 2026.05.11 | GPL-3.0 | Arch-only dependency set (matugen, MicroTeX, many Arch packages); current main targets Hyprland 0.55 with Lua config | no |

* Dux Shell is installed per user into `~/.local/share/kwick/shells/dms/2.1.2` from `dms-full-amd64.tar.gz` or
  `dms-full-arm64.tar.gz` (SHA-256 pinned in `/usr/lib/kwick/desktop-shells`, matching upstream's `.sha256` files). There is no
  riscv64 build, so it is hidden there. Its optional helpers (matugen for wallpaper colours, dgop, cava) are not in Debian 13 and
  are not installed; the shell runs without them.
* Upstream recommends Qt 6.10 for Dux Shell's lock screen on fractional-scale outputs whose logical size is not a whole number.
  KwickOS leaves the Hyprland bindings alone, so Super+L and the idle timer still lock with `swaylock` under every bar.
* On first start Dux Shell shows its own welcome window; Skip closes it.

### Settings, Shells

* **Desktop shell**: one card per shell with a drawn preview that follows the layout and dark or light appearance, the toolkit,
  version and license, and the state: In use, At next login, or Running. The button says Switch now when the change is live (inside
  Hyprland between Waybar, Dux Shell and Noctalia), Use when it applies at the next login, and Install and use when something has to
  be downloaded first.
* **Terminal shell**: every shell this machine can run with its version and where it comes from; Use switches with one click and no
  terminal, Install installs first. Hovering a row shows that shell in the prompt preview.
* **Prompt**: the four presets and a live terminal preview with the current layout colour.
* Everything is read from `kwick-shell list --json`, `kwick-shell prompt list --json` and `kwick-desktop shell list --json`
  (`helpers/shells.sh`), so the page and the CLI always agree.
