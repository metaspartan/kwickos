# Software Update

KwickOS keeps itself current through apt (Debian 13 and the KwickOS repository) and, on the desktop, Flatpak (Flathub).
`kwick-update` is the one command behind it, in both editions, and the **Software Update** page of KwickOS Settings is a
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
package (`scripts/mkimage.sh`: `linux-image-kwick-virt` on the disk image, the live kernel's package on the ISO), so a
plain `kwick-update upgrade` brings kernel updates on a headless system too. Images built before this had the kernel
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

## Snapshots around updates

On a Btrfs install `kwick-update upgrade` takes a `pre` snapshot before it starts and a `post` snapshot when it ends ("Software Update (N updates)"), so the whole update can be undone from the Snapshots page or the boot menu. apt and kpkg transactions outside Software Update get their own pairs through the `DPkg::Pre-Invoke`/`Post-Invoke` hooks; during Software Update those hooks stay quiet. On ext4 nothing changes. See [SNAPSHOTS](SNAPSHOTS.md).

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

An update that stops half-way (a maintainer script that fails) leaves packages unconfigured. apt then ends with an error
that names them, and `kwick-update upgrade` runs `dpkg --configure -a` before it installs anything, so Software Update
finishes the interrupted update by itself.

## The notification

After a scheduled check that found something new, `kwick-update notify` finds the running desktop shells (plasmashell,
gnome-shell, Hyprland, sway), takes the session bus address from their environment and, as that user, sends one notification
through `gdbus` ("Software Updates Available", with the count and a new release if there is one). Clicking it opens
`kwick-settings software-update`. The same set of updates is announced once. No process stays in the session: the helper that
waits for the click exits when the notification is closed, or after an hour.

## Permissions

`desktop/rootfs/usr/share/polkit-1/actions/org.kwickos.update.policy` defines one action, `org.kwickos.update`, for
`pkexec /usr/sbin/kwick-update`. Installing and kernel changes ask for an administrator password once and keep the
authorization for a few minutes (`auth_admin_keep`), so a session of changes is one prompt.
`rules.d/50-kwickos-update.rules` lets local, active members of `sudo` or `wheel` run `kwick-update check`, `status` and `log`
without a prompt, so opening Software Update can refresh a stale list silently. The Settings page uses `sudo -n` first when
it is allowed (the live session) and `pkexec` otherwise.

## Settings page

KwickOS Settings, **Software Update** (`kwick-settings software-update`, also `update` or `kernel`; the launcher has a
Software Update action):

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

The GPU page now points at Software Update for kernels instead of listing them itself.
