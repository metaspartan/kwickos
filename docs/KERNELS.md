# Kernels: install, switch, try once, roll back

`kwick-kernel` manages the kernels of a KwickOS system the way you would hope a kernel manager works: see what is
installed and what the repository offers, move to the latest or to a specific version, pick the default, boot a kernel
once to see if it works, and go back. It is a single POSIX shell script (`/usr/sbin/kwick-kernel`) in both editions,
and the Settings app shows it on the GPU page.

```
kwick-kernel list                      installed kernels (version, flavor, size, running, default) and what the repo offers
kwick-kernel install latest            newest kernel of the running flavor, through apt
kwick-kernel install 7.3.3             a specific version  (7.3.3:generic, generic-7.3.3 pick the flavor)
kwick-kernel install generic           newest kernel of another flavor (generic, virt, k1, k1mainline, gb10, apple)
kwick-kernel default 7.3.3             boot this one from now on
kwick-kernel try 7.3.4                 boot it once, the default boots again if the boot is not confirmed
kwick-kernel try 7.3.4 --promote       ... and make it the default once the boot is confirmed
kwick-kernel rollback                  back to the previous default
kwick-kernel remove 7.3.2              delete a retained kernel (never the running or the default one)
kwick-kernel keep 3                    keep the running, default and newest 3 per flavor (automatic cleanup)
kwick-kernel status | list --json      machine-readable output for the Settings app
kwick-kernel mainline [VERSION]        versions and flavors the repository publishes
```

Installing needs root. `list` and `status` do not.

## How it fits together

* **Flavors and versions.** The repository has one package per flavor (`linux-image-kwick-generic`, `-virt`, `-k1`,
  `-k1mainline`, `-gb10`, `kwick-kernel-asahi` for Apple). `k1` is SpacemiT's 6.6 BSP and `k1mainline` the kernel.org
  kernel for the Banana Pi BPI-F3; both are built by `scripts/build-kernel-variant.sh` (see [HARDWARE](HARDWARE.md)). A kernel is identified as `FLAVOR-VERSION`, for example `generic-7.3.4`.
  A bare version works when it is unambiguous, `7.3.4:virt` otherwise. `install` resolves versions with
  `apt-cache madison` and installs `package=version`, so older versions are a normal downgrade. `install` also takes
  `--no-default` (install, do not switch the default) and `--no-update`.
* **Several kernels at once.** A package replaces its previous version, so `kwick-kernel` retains the outgoing kernel
  (files and modules, hardlinked, almost no extra disk) under `/var/lib/kwick/kernels/<id>` before apt replaces it. The
  package's `preinst` does this on every upgrade, and `kwick-kernel install` does it itself first, so plain
  `apt upgrade` keeps the old kernel too. `keep N` limits how many pile up (default 3 per flavor, `/etc/kwick/kernel.conf`).
  The kernel owned by an installed package is never deleted by `remove` or `keep`.
* **State** lives in `/var/lib/kwick/kernel-state` (default, previous, pending trial, result of the last trial).
* **The boot path decides how switching works.** `kwick-kernel` detects it; `kwick-kernel status` shows it.

| Boot path | default | one-shot `try` | fallback if the trial is not confirmed |
|---|---|---|---|
| EFI stub (no bootloader) | the default kernel is `EFI/BOOT/BOOTx64.EFI` (the previous one stays as `EFI/kwick/previous.efi`); other kernels are copied only when selected, so a small ESP is fine | the kernel is copied to `EFI/kwick/trial.efi` and `efibootmgr` creates a boot entry and sets `BootNext` (installs `efibootmgr` if missing) | the firmware consumes `BootNext`; the next boot uses the default again |
| GRUB (UEFI or BIOS) | `grub.cfg` has one entry per kernel (`/EFI/kwick/k/<id>/` or `/boot/k/<id>/`), the default is `saved_entry` in `grubenv` | `next_entry` in `grubenv`, which `grub.cfg` clears before booting (the same mechanism as `grub-reboot`) | `next_entry` is already gone, the next boot uses the default |
| systemd-boot | one `loader/entries/kwick-<id>.conf` per kernel, `default` in `loader.conf` plus `bootctl set-default` | `bootctl set-oneshot` (or the `LoaderEntryOneShot` EFI variable directly) | the boot loader clears the one-shot variable |
| U-Boot boards (BPI-F3) | `kwick-bootctl set-kernel <release>`, which also appends the kernel's own `uboot.txt` (the mainline flavor uses it to boot with the SoC watchdog armed) | the same call; `kwick-bootctl` falls back to the vendor system when the boot is unconfirmed | `kwick-kernel confirm` restores the previous kernel selection after a failed trial |
| Apple Silicon | `kwick-apple-boot install <release>` | not available | none |
| containers, direct-kernel boot | nothing to switch (the kernel is stored under `/usr/lib/kwick/kernels`) | | |

* **Confirmation.** `kwick-kernel-confirm.service` runs `kwick-kernel confirm --wait` at every boot. After a short delay
  (`CONFIRM_DELAY`, 30 s by default) it compares the running kernel with the pending trial. A match records the trial as
  confirmed (and with `--promote` makes it the default). Anything else records it as failed. Because every one-shot
  mechanism above is consumed by the firmware or boot loader itself, a kernel that hangs needs nothing more than a
  power cycle to come back on the default.
* `kwick-kernel-install <release>` (what the kernel packages call in their `postinst`) now forwards to `kwick-kernel`,
  so a kernel installed with `apt install` becomes the default exactly as before, the previous default is remembered
  for `rollback`, and `kwick-kernel-install --list` and `--rollback` still work. On GRUB and systemd-boot installs
  `kwick-kernel` writes the boot entries itself (the initramfs for btrfs, xfs, ZFS and encrypted roots still comes from
  `kwick-install initrd`); `kwick-kernel sync` rewrites them after a manual change.

## Where the ideas come from

| Tool | What was taken |
|---|---|
| Ubuntu mainline-kernels / ukuu | list available versions beside installed ones, install an arbitrary version, remove old ones |
| Arch `downgrade` and `linux-lts` | going back to a specific older package version, several kernel flavors side by side and a way to pick one |
| Fedora `grubby` and `installonlypkgs` | `keep N` ("installonly_limit"), the running kernel is never removed, set the default entry |
| NixOS generations | every kernel stays a selectable entry, rollback is a normal boot choice rather than a repair |
| Pop!_OS `kernelstub` | the boot entries are generated from the installed kernels, nobody edits them by hand |
| systemd `kernel-install`, `bootctl` | per-kernel entries identified by an id, `set-default` and `set-oneshot`, boot counting as the model for "confirm or fall back" |
| Raspberry Pi `rpi-update` | one command to move to a newer or older kernel and a clear statement of what changed on disk |
| GRUB `grub-reboot`, EFI `BootNext` | the one-shot trial that cannot strand the machine |

## "mainline": what is and is not offered

Building a kernel.org kernel on the device is not practical (a generic build takes tens of minutes on a fast machine and
needs gigabytes), so `kwick-kernel mainline` does not build one. KwickOS follows kernel.org stable in CI instead: the
`kernel-watch` workflow checks kernel.org every six hours, bumps `KERNEL_VERSION` and starts `release.yml`, which builds
every flavor with `scripts/build-kernel.sh` (our config fragments in `config/kernel`), packages it with
`scripts/mkkernelpkg.sh`, boot-tests it and publishes it to the signed apt repository (`scripts/mkrepo.sh` keeps
several versions with `--multiversion`). `kwick-kernel mainline` lists the versions and flavors that repository holds,
and `kwick-kernel mainline 7.3.3` installs one. To get a version the repository does not have yet, build it with
`KVER=<version> scripts/build-kernel.sh <arch> <flavor>` (see [BUILDING](BUILDING.md)) and `scripts/mkkernelpkg.sh`.

## Settings

The GPU page of the Settings app has a **Kernel** section: every installed kernel with **Set default** and
**Try once** buttons (the same commands, run elevated in a terminal), driven by `kwick-kernel list --json`.

## Testing

`tests/kernel-switch.sh efistub|grub` boots the image under QEMU/UEFI nine times with real kernels: an older and a newer
virt kernel and the generic kernel are packaged into a signed repository, installed through apt with `kwick-kernel`,
switched with `default`, trialled with `try` (confirmed, promoted, and left unconfirmed), rolled back and removed. It
needs an older virt kernel build in `OLD_VIRT` (a directory with `version`, `vmlinuz` and `config`, built with
`KVER=7.3.3 scripts/build-kernel.sh amd64 virt`). Results and what is not covered are in [VERIFICATION](VERIFICATION.md).
