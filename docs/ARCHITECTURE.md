# KwickOS architecture

KwickOS is built from three small programs plus the upstream Linux kernel:

| component | language | size (amd64, static) | role |
|---|---|---|---|
| **BusyBox 1.38** (+ KwickOS patches) | C / musl | ~1.1 MB | 340+ POSIX/Linux commands, shell (`sh`, `bash`→ash), networking (`ip`, `udhcpc`, `ifup`), syslog, cron, ntpd |
| **kinit** | C / musl | ~120 KB | initramfs root finder, PID 1, service manager, `systemctl`/`service`/`journalctl`, Debian helpers, `systemd-sysusers`/`systemd-tmpfiles` |
| **kpkg** | Go | ~4.2 MB | `apt`, `apt-get`, `apt-cache`, `apt-mark`, `dpkg`, `dpkg-query`, `dpkg-deb`, `update-alternatives`, ... on real Debian repositories |
| **Linux 7.3.x** | C | 6.4 MB (virt, EFI) | `virt` (monolithic, module-free) and `generic` (defconfig + modules) flavors |

Nothing in the base image is dynamically linked, so the base contains no libc
`.so` at all. glibc arrives only when you install a Debian package that needs it.

```mermaid
flowchart LR
  FW[UEFI firmware / hypervisor] -->|loads| K["Linux kernel = EFI app\n(EFI stub + built-in cmdline)"]
  K -->|embedded initramfs| S0["kinit stage 0\n(/init, ~120 KB)"]
  S0 -->|root=, PARTLABEL=kwick-root,\nor live ISO LABEL=KWICKOS| R[(root fs:\next4 / erofs+overlay / RAM)]
  R --> S1["kinit stage 1 = PID 1"]
  S1 --> U["systemd-style units\n(/usr/lib/systemd/system, *.wants)"]
  S1 --> G[getty / autologin on every console]
  U --> N[networking: ifup + udhcpc]
  U --> L[syslogd ring buffer]
  U --> D[Debian daemons: nginx, sshd, postgres...]
  A["apt / dpkg (kpkg)"] -->|signed InRelease + SHA256| DEB[(deb.debian.org trixie)]
  A -->|maintainer scripts| H["deb-systemd-helper / invoke-rc.d\n(kinit multi-call)"]
```

## 1. No bootloader: the kernel is the boot loader

Every KwickOS kernel is built with `CONFIG_EFI_STUB`, which makes the kernel image a
valid UEFI application, and with an **embedded initramfs** that contains only
`kinit` (about 120 KB). The resulting single file boots on:

* UEFI firmware, from the ESP removable path `EFI/BOOT/BOOTX64.EFI`
  (`BOOTAA64.EFI`, `BOOTRISCV64.EFI` on the other architectures);
* QEMU/Firecracker/cloud-hypervisor `-kernel` direct boot (PVH on x86);
* the live ISO, as an El Torito EFI image.

kinit stage 0 finds the root without any kernel command line:

1. `root=` if given (`/dev/x`, `PARTLABEL=`, `LABEL=`, `UUID=`, `virtiofs:tag`, 9p);
2. otherwise the GPT partition named `kwick-root`;
3. otherwise a volume labelled `KWICKOS` (the live ISO or USB stick). Its
   `kwick/root.erofs` image is mounted read-only (LZ4HC) under a tmpfs overlay. A
   partition named `kwick-persist` makes the overlay persistent, and `kwick.toram`
   copies the image to RAM first.
4. If the whole OS was loaded as an initramfs (`/etc/kwick-release` exists), it
   simply continues. This is the fastest mode, used for microVMs and agent sandboxes.

Labels are read straight from the superblocks, so no blkid is needed. There is
no GRUB, no initramfs generator, and nothing to regenerate on kernel updates.

## 2. kinit: PID 1, service manager, systemd compatibility

* Mounts the API filesystems, cgroup2 (`nsdelegate`), applies `sysctl.d`, runs
  `systemd-tmpfiles --create`, coldplugs modules (generic flavor) and hotplugs
  them from kernel uevents (netlink, no udev daemon).
* Service definitions use **the systemd unit format**. Units shipped by Debian
  packages (`/usr/lib/systemd/system/*.service`) work unmodified. Supported:
  `Type=simple|exec|notify|forking|oneshot`, `ExecStart/Pre/Post/Stop/Reload`,
  `Restart=` (with backoff), `User/Group/DynamicUser`, `Environment(File)`,
  `WorkingDirectory`, `PIDFile`, `RemainAfterExit`, `Runtime/State/Logs/CacheDirectory`,
  drop-ins (`*.service.d/*.conf`), template units (`foo@bar.service`) and
  `%i %n %p %t ...` specifiers.
* Services start **in parallel** as soon as PID 1 is up. Boot "ordering" is
  whatever finishes first: daemons that need the network retry, as on systemd.
* `systemctl start|stop|restart|reload|status|enable|disable|mask|is-active|is-enabled|cat|daemon-reload|list-units`,
  `service`, `journalctl -u UNIT [-f]` (per-unit log files in `/var/log/kinit/`),
  `poweroff|reboot|halt`.
* **Containers:** `systemctl start nginx` inside a container transparently starts
  `kinit --supervisor`, a non-PID-1 service manager. Agents can therefore use the
  same commands everywhere.
* Debian integration: `deb-systemd-helper`, `deb-systemd-invoke`, `invoke-rc.d`
  (honours `policy-rc.d`) and `update-rc.d`. kinit also creates `/run/systemd/system`,
  so maintainer scripts take the systemd code path and enable and start services
  exactly as on Debian.
* `systemd-sysusers` and `systemd-tmpfiles` are implemented natively, so packages
  that declare `systemd | systemd-sysusers` don't pull in systemd.
* Shutdown signals all services in parallel, waits until no process is left
  (`ECHILD`), unmounts, and remounts `/` read-only.

## 3. kpkg: apt/dpkg on real Debian repositories

The KwickOS base **virtually provides Debian's Essential set** (coreutils, bash,
dpkg, util-linux, ...), as versioned `Provides:` of the single `kwick-base`
status entry. So `apt install nginx` resolves against the unmodified Debian 13
archive and pulls in only what nginx really needs (libc6, libssl, pcre2, ...).

* **Security model** is Debian's. `InRelease` is verified with the Debian
  archive keys (RSA-4096 and Ed25519, using kpkg's own minimal OpenPGP
  implementation); index files and every `.deb` are checked by SHA256;
  `Valid-Until` is enforced; `by-hash` downloads avoid mirror races. Because
  integrity doesn't depend on TLS, kpkg ships a 300-line HTTP/1.1 client
  instead of `net/http`+`crypto/tls`, which saves about 3.5 MB. `https://` sources
  go through curl or wget.
* **Compact indexes:** `Packages.gz` is stream-parsed into a field-filtered,
  gzip'd index (~11 MB for all of Debian main) without ever being fully loaded.
  It downloads 3.6 MB more than `Packages.xz` but decodes about 4× faster, which cut
  `apt update` from 2.3 s to 1.6 s on one core. `index-compression = xz` in
  `/etc/kpkg.conf` switches back for slow links.
* **dpkg-compatible database:** `/var/lib/dpkg/status`, `info/*.list`,
  maintainer scripts, conffiles (locally modified ones are kept and the new
  version is saved as `.dpkg-dist` only when the package's version changed; deleted
  ones stay deleted, as with dpkg), triggers (explicit and file triggers, e.g.
  `ldconfig`), `update-alternatives`, `/var/lib/apt/extended_states` (autoremove),
  holds (`apt-mark hold`, `dpkg --set-selections`; `--allow-change-held-packages`).
* **Solver:** alternatives, versioned and virtual Provides,
  Conflicts/Breaks/Replaces with removals, Pre-Depends, and Tarjan SCC ordering.
  Cycles are unpacked fully, then configured Essential-first.
* **Essential on demand:** perl (debconf), libc-bin (ldconfig/getent) and a real
  bash are installed only when a transaction needs them.
* **Self-healing compatibility.** If a maintainer script fails because a BusyBox
  applet lacks a GNU option (`pgrep -u`, `find -uid`, `ln -r` ...), or a script
  needs an interpreter that isn't present, kpkg installs the real Debian package
  (procps, findutils, coreutils, perl-base ...) and retries the script. The base
  stays tiny, and GNU tools appear only on systems whose software needs them.
* Recommends are **off by default** (`/etc/kpkg.conf`), as in Debian container
  images. Use `--install-recommends` per call.
* Candidates follow apt's policy: `/etc/apt/preferences` and `preferences.d`
  pins (release, origin, version, glob and regex package patterns), `-t` /
  `APT::Default-Release` (990), NotAutomatic archives such as backports (100,
  or 1 without ButAutomaticUpgrades), installed versions (100). The highest
  priority wins, then the highest version; above 1000 may downgrade and a
  negative priority blocks a version. Dependencies use the same ranking, so
  `apt install samba` stays on trixie while `-t trixie-backports` moves it and
  its dependencies to backports.

## 4. Kernel flavors and updates

| flavor | base | modules | used for |
|---|---|---|---|
| `virt` | `tinyconfig` + fragments | none | disk images, microVMs, cloud (virtio, NVMe, ENA, gVNIC, e1000) |
| `generic` | arch `defconfig` + fragments | zstd-compressed, coldplugged by kinit | live ISO, bare metal, Hyper-V |

`config/kernel/*.config` are fragments merged by `merge_config.sh`. The build
**fails if any required option was dropped** by kconfig, and lists every
non-applied option.

Kernel updates are packages (`linux-image-kwick-virt`, `linux-image-kwick-generic`)
in the KwickOS apt repository published by CI to GitHub Pages. Their postinst runs
`kwick-kernel-install`, which copies the new EFI image to the ESP and keeps the
previous one for `kwick-kernel-install --rollback`. The `kernel-watch` workflow polls
kernel.org every 6 hours and opens a PR for each new stable release, which the full
build and boot matrix then tests.

## 5. Layout and security defaults

* Merged `/usr` (`/bin`, `/sbin`, `/lib` → `/usr/...`), as Debian 13 expects.
* Root account locked (`*`). The console autologins as root on VM and live
  images (`/etc/kinit/autologin`); remove that file to get a login prompt.
* The build fails if anything in the rootfs is world-writable (except sticky
  tmp dirs).
* Kernel: stack protector, `STRICT_KERNEL_RWX`, KASLR, hardened usercopy,
  `INIT_STACK_ALL_ZERO`, list hardening, Landlock, Yama, lockdown, BPF LSM, seccomp,
  `dmesg_restrict`, `kptr_restrict`, protected links/fifos.
* Networking defaults: BBR + fq, TCP Fast Open, nftables (with an iptables-legacy
  fallback), WireGuard, VXLAN, bridges, veth, cgroup v2 and all namespaces, so
  Docker/containerd/podman installed via `apt` work.

## 6. Compared with Alpine and Debian

| | Alpine | Debian/Ubuntu | **KwickOS** |
|---|---|---|---|
| base userland | BusyBox + musl `.so` | GNU coreutils + glibc | BusyBox + **static** kinit/kpkg (no libc `.so` at all) |
| package manager | apk (Alpine packages, musl) | apt/dpkg | **kpkg**: `apt`/`dpkg`-compatible, uses Debian's own repos |
| software compatibility | musl rebuilds | everything | everything in Debian (glibc arrives on demand) |
| init | OpenRC | systemd | **kinit**: 120 KB PID 1 that runs systemd unit files |
| boot chain | bootloader + initramfs | GRUB + initramfs-tools | **none**: the kernel is a UEFI app with a 120 KB embedded root finder |
| kernel updates | apk | apt + update-grub + initramfs rebuild | `apt upgrade` copies one EFI file (and keeps the previous one for rollback) |

* **Essential set provided virtually.** The base declares the Debian Essential packages (`coreutils`, `bash`, `dpkg`, ...) as
  satisfied by BusyBox, so real Debian packages install unmodified on a 5 MB system.
* **Self-healing compatibility.** If a maintainer script trips over a BusyBox difference, kpkg installs the GNU tool from Debian
  and retries. GNU tools exist only where software needs them.
* **systemd compatibility without systemd.** `.service` units, `deb-systemd-helper`, `systemd-sysusers` and `systemd-tmpfiles`
  are handled by kinit, so `apt install nginx` gets you a running, enabled, supervised service.
* **One file boots everything.** The EFI-stub kernel embeds kinit, which finds a `kwick-root` partition, a `KWICKOS` live medium
  (erofs + overlay), `root=`, virtiofs/9p, or a whole-OS initramfs. No GRUB, no dracut, nothing to regenerate.
* **Multiarch.** kpkg handles foreign architectures (`dpkg --add-architecture i386`), which is what native Steam uses.
* **Alpine packages too.** `apk add` works next to `apt`, with a signature-verified bootstrap.

## 7. Limitations

* The headless live ISO and the disk images boot through UEFI only. The desktop ISO and `kwickos-amd64-headless.iso` also boot in
  BIOS mode on amd64. Direct `-kernel` boot works everywhere.
* kpkg implements the commonly used apt/dpkg surface, multiarch and apt's pin priorities (`/etc/apt/preferences(.d)`, `-t`,
  `APT::Default-Release`, `apt-cache policy`). Source packages are not implemented.
* kinit implements the commonly used subset of systemd units: no socket activation, timers or D-Bus, and units start in parallel
  with only the ordering described above.
* No SELinux/AppArmor policy. Lockdown, Landlock, Yama and seccomp are enabled.
* riscv64 is tested under QEMU emulation only.
* Desktop effects need a GPU compositor. GPU, Apple Silicon and GB10 specifics are in [HARDWARE.md](HARDWARE.md).
