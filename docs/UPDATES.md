# Updates

KwickOS keeps itself current through apt (Debian 13 and the KwickOS repository) and, on the desktop, Flatpak (Flathub).
`kwick-update` is the one command behind it, in both editions, and the **Updates** page of KwickOS Settings is a
window onto that command. Kernels are part of the same page, through `kwick-kernel` ([KERNELS](KERNELS.md)).

```
kwick-update status [--json]              release, last check, pending updates, settings, running task
kwick-update check                        apt update (and Flatpak), then list what can be updated
kwick-update upgrade [all|system|apps|security]
kwick-update download                     fetch system updates, install later
kwick-update auto on|off                  automatic checks
kwick-update auto set check|download|system|apps|security|notify on|off ...
kwick-update auto interval 12             hours between automatic checks
kwick-update kernel try generic-7.3.5 --promote    any kwick-kernel command, as a logged task
kwick-update log [N]                      output of the last task
```

`status`, `log` and `auto show` work as any user; the rest need root.

## What a check finds

* **System updates**: the packages `apt-get -s upgrade` would install, with the installed and the new version, the download
  size and the package summary. Packages from a `*-security` suite are marked as security fixes. One dry run plus one
  `apt-cache show` produce the whole list, so a check costs `apt update` and two index loads.
* **App updates**: `flatpak remote-ls --updates --system`, with the installed version from `flatpak list`. Per-user Flatpak
  installs are not covered.
* **A new KwickOS release**: the candidate version of `kwick-desktop` (or `kwick-essentials` on a headless system) in the
  KwickOS repository, compared with the installed package and `/etc/kwick-release`. Only when that package is installed:
  a headless system without `kwick-essentials` has nothing an update could move to the new release, so none is announced. No extra request is made: the version comes
  from the package lists `apt update` already fetched. Installing the update moves the desktop packages to the new release,
  and with them kinit, kpkg and the release files (`kwick-core`, see below); BusyBox changes only with a new image.

Results live in `/var/lib/kwick/update` (`state`, `updates`, `log`, `kernels.json`), readable by everyone, so the Settings
page and `kwick-update status` never need a password.

## Installing, and what happens to kernels

`kwick-update upgrade` runs `apt-get upgrade -y`, then `flatpak update --system`, and writes its progress to
`/var/lib/kwick/update/progress` (percent and a line such as "Configuring libfoo…", computed from apt's Get, Unpacking and
Setting up lines). Only one task runs at a time. `upgrade security` installs only the packages that come from a
`*-security` suite.

Closing Settings while a task runs does not stop it: the window closes at once, the task finishes (including the kernel
trial setup at the end), and the page reattaches to a running task when it is opened again.
Kernels reach a system as the package `linux-image-kwick-<flavor>`. Images register the kernel they boot as that
package (`scripts/mkimage.sh`: `linux-image-kwick-virt` on the disk image, the live kernel's package on the ISO, and
`linux-image-kwick-generic` on the desktop ISO since 0.7.1), so a plain `kwick-update upgrade` brings kernel updates on a
headless system too. Kernel packages pre-depend on `kwick-update`, so apt configures the new `kwick-kernel` before it unpacks
a kernel and the kernel's maintainer scripts never run an older one. Images built before this had the kernel
only on the ESP: there, `kwick-kernel install latest` installs the package once and later updates follow.

When the upgrade brings a new kernel package, `kwick-update` does not let the package switch the default kernel. It sets
`/run/kwick-kernel.keep` for the duration of apt, so the new kernel is only registered, and then runs
`kwick-kernel try NEW --promote`: the new kernel starts once at the next restart and becomes the default only after that boot
is confirmed. If it panics or cannot find its root file system, it reboots after 10 seconds into the old default by
itself; if it hangs, the next power cycle starts the old default (see the boot path table in [KERNELS](KERNELS.md)). On boot paths without a one-shot boot (Raspberry Pi firmware, Apple Silicon) the new kernel becomes the
default directly and the previous one stays for `kwick-kernel rollback`. If a trial cannot be set up on a boot path that has
one (no `efibootmgr`, or GRUB whose `grubenv` sits on btrfs, xfs or ZFS where GRUB cannot clear the one-shot entry), the
old default stays and the new kernel waits for `kwick-kernel try`. An upgrade of a kernel package of another flavor than the
default (for example `virt` next to `generic`) only installs it. Installing a kernel from the Settings page
(`kwick-update kernel install VERSION:FLAVOR`) follows the same rule, except that it may switch the flavor.

## Lean musl builds

On a headless system `apt install curl` (likewise `python3`, `nginx`, `openssh-server`, `git`) installs the KwickOS lean build
`kwick-<name>` from the KwickOS repository instead of Debian's package ([BASE](BASE.md#lean-builds)). These packages are
built by KwickOS, not Debian, so Debian's security archive does not cover them. They are kept current like this:

* **Pinned sources.** `config/musl-lean/sources` names every upstream tarball (CPython, curl, mbedTLS, nghttp2, OpenSSL,
  nginx, PCRE2, OpenSSH, git, expat, zlib, xz, bzip2, libffi, SQLite, ncurses, readline) with its URL and SHA-256, plus the
  Mozilla CA bundle and any security patch taken ahead of an upstream release (for example the five OpenSSL 3.5.9 fixes
  Alpine ships as `3.5.9-r1`, pinned to an aports commit). `scripts/build-musl-lean.sh` refuses a file whose checksum does not
  match. The tarballs matching Alpine 3.24's versions were also checked against the SHA-512 sums in Alpine's APKBUILDs.
* **Reproducible builds in CI.** The release workflow builds them in `alpine:3.22` for amd64, arm64 and riscv64 with fixed
  `SOURCE_DATE_EPOCH`, `-ffile-prefix-map`, sorted file lists and normalised timestamps, and `mkrepo.sh` signs them into the
  KwickOS repository with the same key as every other `kwick-*` package. musl comes from the builder image, so a musl fix
  arrives with Alpine's next 3.22 package and the next build.
* **Tracking upstream security releases.** `scripts/cve-check.sh` (the security gate run on every push and nightly) compares
  each pin with Alpine's security database (`secdb.alpinelinux.org`, edge main and community). It fails when any pinned
  version is older than a version Alpine lists as fixing a CVE, warns when Alpine patched the pinned version (the fix is not
  in an upstream release yet, so it is taken as a pinned patch), and warns when the CA bundle is older than 120 days. A
  security release is a one-line change of version and checksum in `config/musl-lean/sources`; the next release build
  rebuilds every package that uses the library (an OpenSSL fix rebuilds Python, nginx and OpenSSH).
* **Upgrades.** The lean packages upgrade with `apt upgrade` and `kwick-update` like any other `kwick-*` package. They never
  depend on Debian libraries, and Debian packages never resolve to them except through `Provides` of a command (`curl`,
  `git`, `nginx`, `openssh-server`), so a Debian security update keeps reaching Debian's own `libcurl4t64`, `libssl3t64` and
  Python.

## Snapshots around updates

On a Btrfs install `kwick-update upgrade` takes a `pre` snapshot before it starts and a `post` snapshot when it ends ("System update (N updates)"), so the whole update can be undone from the Snapshots page or the boot menu. apt and kpkg transactions outside the Updates app get their own pairs through the `DPkg::Pre-Invoke`/`Post-Invoke` hooks; during an Updates run those hooks stay quiet. On ext4 nothing changes. See [SNAPSHOTS](SNAPSHOTS.md).

## Automatic updates

KwickOS's PID 1 (kinit) runs systemd services but has no timers, so automatic updates use BusyBox `crond`, which is already in
the base. `kwick-update auto on` writes one line to root's crontab (`KWICK_JOB=update`, the same convention as
`kwick-storage`), at a random minute of every hour, and enables `crond`. Each run exits at once unless the last check is older
than the interval (12 hours by default), so a machine that was off at the usual time catches up within the hour. Nothing runs
while automatic updates are off, and `crond` is stopped again when no crontab has any job left.

A scheduled run checks at lower priority (`renice 10`), then, when the check found something, installs system, security
or app updates as configured (not while the computer runs on battery) or only downloads them, and finally notifies the
desktop. The result of the check stays the last task when there was nothing to install.

Automatic updates are off on a new system and no `/etc/kwick/update.conf` exists. `kwick-update auto` writes the file;
after `kwick-update auto on` and `kwick-update auto set system on` it reads:

```
CHECK=1
DOWNLOAD=0
INSTALL_SYSTEM=1
INSTALL_APPS=0
INSTALL_SECURITY=0
NOTIFY=1
INTERVAL=12
```

Turning on any install or download option turns checking on; `auto off` turns everything off.

## Systems installed from an older image

`kwick-update`, `kwick-kernel`, `kwick-kernel-install`, `kwick-bootctl`, `kwick-snapshot`, `kwick-kernel-confirm.service`,
`crond.service` and `kwick-boot-ok.service` are part of the base image. An older install that is upgraded with apt gets them
from the `kwick-update` package (`scripts/mkupdatepkg.sh`), which `kwick-essentials` and `kwick-desktop` depend on, together
with the base tools the desktop calls: `kwick-shell` with `shell-helper`, the prompt presets and the per-shell setup files,
`kwick-vpn` and `kfetch`, and `add-shell`/`remove-shell`, which the maintainer scripts of Debian's shell packages call (put in
place only when missing). Its postinst enables `kwick-kernel-confirm.service` and `kwick-boot-ok.service` and hooks
`/etc/ashrc` into an `/etc/profile` that predates it. `kwick-update` depends on `kwick-core` (`scripts/mkcorepkg.sh`, one per
architecture, taken from the release's root file system): kinit, kpkg, `/etc/kwick-release` and `os-release`, so an upgraded
system runs the release's init and package manager (kinit from the next boot) and reports the release it is on. kpkg never
lets a package overwrite `/usr/sbin/kinit` or `/usr/bin/kpkg`, so the package ships both under `/usr/lib/kwick/core` and its
postinst moves them into place. On a current image both packages take over the same files from the base.

### How every installed system gets kwick-core and the desktop package

What an image registers in `/var/lib/dpkg/status` decides what `apt upgrade` can move, because an upgrade only touches packages
that are installed. `kwick-base` (the base system) is never upgraded, so each image registers real packages next to it:

| image | registered since 0.7.1 | registered before |
|---|---|---|
| headless disk image and ISO (`mkimage.sh`) | `kwick-core`, `kwick-update`, `linux-image-kwick-virt` or `-generic` | the kernel only |
| Raspberry Pi image (`mkrpiimage.sh`) | `kwick-core`, `kwick-update`, `kwick-rpi-firmware`, `linux-image-kwick-rpi` | firmware and kernel |
| desktop ISO (`mkdesktop-iso.sh`) | `kwick-core`, `kwick-update`, `kwick-gpu`, `kwick-gaming`, `kwick-essentials`, `linux-image-kwick-generic`, `kwick-desktop` | nothing but `kwick-base` |
| root file system tarball and container | `kwick-base` only | the same |

The images extract each package over the root and record its file list, maintainer scripts and conffile checksums
(`deb_register` in `scripts/deb.sh`), then `scripts/dpkg-depcheck.py` fails the build if any registered package has an unmet
dependency, so a fresh system never starts with a broken dependency that a later `apt remove` would resolve by removing it.
`kwick-core` keeps its copies of kinit and kpkg as hard links to `/usr/sbin/kinit` and `/usr/bin/kpkg`, so the image does not
grow. The desktop image installs the Debian packages `kwick-essentials` depends on for the same reason.

Older systems reach `kwick-core` like this:

* **Headless images and Raspberry Pi images** have their kernel registered. Every kernel package (`linux-image-kwick-*`,
  `kwick-kernel-asahi`) has `Pre-Depends: kwick-update (>= release)`, and `kwick-update` depends on `kwick-core (>= release)`, so
  the next kernel upgrade installs both, configured before the kernel is unpacked (the new `kwick-kernel` then handles the kernel).
  The kernel packages' Debian revision went from `-1` to `-2` in 0.7.1 (`kernel_deb_version`), so a system already on the newest
  kernel still gets this upgrade once; the kernel itself is the same and stays the default. The chain has no cycle: `kwick-core`
  depends on nothing.
* **Desktop ISO installs before 0.7.1** have only `kwick-base` registered and nothing KwickOS could upgrade. The repository
  therefore carries `zsh-autosuggestions` (in the package set of every desktop image of the 0.6 and 0.7 releases) as Debian's package with one added
  dependency, on `kwick-update`, and the version `+kwick1` (`scripts/mkcarrierpkg.sh`, rebuilt from Debian's current package
  for every release, data and maintainer scripts unchanged). The first `apt upgrade` or Updates run takes it and with it
  `kwick-update` and `kwick-core`. `kwick-update`'s postinst sees a desktop (`/usr/share/kwick/settings` and a Desktop
  `/etc/kwick-edition`) whose `kwick-desktop` is not installed and starts `kwick-update adopt-desktop --wait`, which waits until
  apt and any Updates task are done, then runs `apt-get install kwick-desktop` as a logged task with the kernel trial
  guard. That installs `kwick-desktop` over the files already on disk (kpkg overwrites files no package owns and files of
  `kwick-base`), its dependencies including the generic kernel package, and from then on desktop updates arrive with the rest of
  the system. If it cannot run then (no network), `kwick-update upgrade` installs `kwick-desktop` first the next time.
* **Containers** have no kernel and get nothing unless their user installs a package that needs it; an image that never runs
  apt is not affected.

Your changes to the desktop's files in `/etc` are kept. `kwick-desktop` declares its `/etc` files (except `/etc/skel`) as
conffiles. When it is installed over a desktop that already has them, or upgraded from a version without conffiles, kpkg keeps
any file that differs from the package's and puts the new one next to it as `.dpkg-dist`. The postinst then compares each kept
file with `/usr/share/kwick/conffiles.md5`, the checksums of every version of those files KwickOS has ever shipped: a file that
matches one was never edited and is replaced by the new version; any other file is yours and stays, with a message that names it.
On adoption the postinst also leaves out what only a first install does (the `kwick` user, SDDM autologin, the move of
`/etc/network/interfaces`), so the installer's choices stand.

An update that stops half-way (a maintainer script that fails) leaves packages unconfigured. apt then ends with an error
that names them, and `kwick-update upgrade` runs `dpkg --configure -a` before it installs anything, so the Updates app
finishes the interrupted update by itself.

## The notification

After a scheduled check that found something new, `kwick-update notify` finds the running desktop shells (plasmashell,
gnome-shell, Hyprland, sway), takes the session bus address from their environment and, as that user, sends one notification
through `gdbus` ("Updates Available", with the count and a new release if there is one). Clicking it opens
`kwick-settings software-update`. The same set of updates is announced once. No process stays in the session: the helper that
waits for the click exits when the notification is closed, or after an hour.

## Permissions

`desktop/rootfs/usr/share/polkit-1/actions/org.kwickos.update.policy` defines one action, `org.kwickos.update`, for
`pkexec /usr/sbin/kwick-update`. Installing and kernel changes ask for an administrator password once and keep the
authorization for a few minutes (`auth_admin_keep`), so a session of changes is one prompt.
`rules.d/50-kwickos-update.rules` lets local, active members of `sudo` or `wheel` run `kwick-update check`, `status` and `log`
without a prompt, so opening the Updates app can refresh a stale list silently. The Settings page uses `sudo -n` first when
it is allowed (the live session) and `pkexec` otherwise.

## Settings page

KwickOS Settings, **Updates** (`kwick-settings software-update`, also `update` or `kernel`; the launcher has an
Updates action):

* **Automatic Updates** with an info button that opens the options sheet (check, download, install system, security and app
  updates, notifications, check interval).
* The status: "KwickOS is up to date" with the release and when it last checked, or "Updates Available" with the count, size
  and security fixes, **Update Now** and **Check Again**. A newer KwickOS release has its own row with a link to the release
  notes. System and app updates are groups that expand to every package with old and new version, size and summary, and each
  group can be installed on its own.
* While a task runs: a progress bar, the current step and **Details** with the live log. The page reattaches to a running
  task when it is opened again. Opening the page checks by itself when the last check is more than six hours old and that
  needs no password.
* **Restart Required** when a kernel trial is pending or the default kernel differs from the running one; **Restart…** opens
  the desktop's restart prompt.
* **Kernel**: running and default kernel, the previous one with **Roll Back…**, a pending trial with **Cancel Trial**, the
  result of the last trial, **Keep** (2, 3 or 5 per flavor) and the boot method.
* **Installed kernels** with **Try Once…**, **Make Default…** and **Remove…** (only kept copies), and **Available from
  KwickOS** with **Install…** for the versions the repository offers of the running flavor and of flavors already installed
  (other flavors, such as `virt` on a desktop, are left out: a boot only confirms that the kernel reached userspace, not that
  the desktop has a graphics driver). Every kernel change asks first and says what
  happens if the kernel does not start.

The GPU page now points at Updates for kernels instead of listing them itself.
