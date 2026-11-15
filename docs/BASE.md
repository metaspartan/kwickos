# Using the base system

The headless base is BusyBox, kinit and kpkg on the latest stable kernel. Everything else comes from Debian 13 with `apt`, or from
Alpine with `apk`. How the pieces work is in [ARCHITECTURE.md](ARCHITECTURE.md).

## Everyday commands

```sh
apt update; apt install postgresql        # real Debian packages
apt search redis; apt show nginx; apt list --installed; apt autoremove; apt full-upgrade
dpkg -l; dpkg -L nginx; dpkg -S /usr/sbin/nginx
systemctl status nginx; systemctl restart nginx; journalctl -u nginx -f
service ssh restart
vi /etc/network/interfaces                 # ifupdown syntax (DHCP on eth0 by default)
```

* Recommends are not installed by default (`/etc/kpkg.conf`). Use `--install-recommends`.
* The console logs in as root automatically on VM and live images. Run `rm /etc/kinit/autologin` and `passwd` for a password
  prompt. Install `openssh-server` for remote access.
* `kwick-kernel-install --list | --rollback` manages kernels.
* `apk add <pkg>` works next to `apt`. Alpine (musl) and Debian (glibc) packages coexist, and the apk bootstrap is
  signature-verified. `tests/ecosystems.sh` checks that `apk add nodejs`, `apt install python3` and the official Bun installer work
  side by side.
* Real software from the Debian archive passes a 31-package compatibility matrix: [COMPATIBILITY.md](COMPATIBILITY.md).

## Out of the box

What the base can do before you install anything, and what is one `apt install` away. Sizes in the last column were measured on a
fresh base and include the dependencies it lacks. The first Debian package pulls in glibc, about 16 MB, which every later package
then shares. `apt install kwick-essentials` installs a common set of these tools (curl, jq, sudo, dnsutils, net-tools,
build-essential and similar) in one step.

| need | in the base | with apt |
|---|---|---|
| network | DHCP and static IPv4 (`/etc/network/interfaces`, `ip`, `ifconfig`, `route`), IPv6 SLAAC and `udhcpc6`, DNS (`nslookup`, `/etc/resolv.conf`), `ping`, `ping6`, `traceroute`, `nc`, `telnet`, `netstat`, `brctl`, `rfkill`, NTP client (`ntpd`, `systemctl enable --now ntpd`) | `dnsutils` (`dig`, 44 MB), `iproute2` (`ss`), `tcpdump` (54 MB) |
| Wi-Fi | `cfg80211`, `mac80211` and `iwlwifi` modules in the generic kernel, `rfkill` | `wpasupplicant` or `iwd` (20 MB), plus the card's firmware package (Debian's `non-free-firmware` component, which is not enabled by default) |
| HTTPS downloads | `wget` with TLS (no certificate validation, see below) | `ca-certificates` (42 MB with its dependencies) and `curl` (60 MB) for validated TLS |
| remote access | `nc`, `telnet`, `ssl_client` | `openssh-client` (61 MB), `openssh-server` (89 MB), `rsync` (28 MB) |
| time zones and keymaps | `TZ=` with POSIX rules (`TZ=CET-1CEST,M3.5.0,M10.5.0/3`), clock via `hwclock` | `tzdata` (31 MB), `kbd` (18 MB) for `loadkeys` |
| editors, pager, shell | `vi`, `less`, `ash` (history, line editing), `watch` | `nano` (21 MB), `bash` (fetched when something needs it) and `bash-completion` |
| users and privilege | `adduser`, `addgroup`, `passwd`, `su`, `chpasswd` | `sudo` (51 MB) |
| scheduling and logs | `crond`, `crontab`, `syslogd`, `logread`, `dmesg` | `rsyslog`, `logrotate` |
| disks | `fdisk`, `mkfs.ext2`, `mkfs.vfat`, `mkswap`, `mount` (loop, CIFS; vfat, ext4, `ntfs3` and `exfat` in the kernel), `lsblk`, `blkid`, `losetup`, `fsck` | `e2fsprogs` (19 MB), `parted` (21 MB), `exfatprogs` (17 MB), `ntfs-3g` (57 MB), `xfsprogs`, `btrfs-progs` |
| archives | `tar`, `gzip`, `bzip2`, `xz`, `unzip`, `cpio` | `zstd` (23 MB), `p7zip` |
| hardware and processes | `lspci`, `lsusb`, `lsmod`, `modprobe`, `top`, `ps`, `free`, `lsof`, `kfetch` | `htop` (18 MB), `pciutils`, `usbutils`, `strace` |
| containers | `unshare`, `nsenter`, `chroot` and a kernel with namespaces and cgroups | `podman` (197 MB), `docker.io` (see the compatibility matrix) |
| installer | `kwick-install`, `kwick-installer` | fetches `fdisk`, `e2fsprogs`, GRUB and so on when needed |

`wget` in the base uses BusyBox's built-in TLS client, which encrypts but does not validate certificates. Install `ca-certificates`
and `curl` when that matters. The base has no `sudo`: log in as root or install it. Enabling anything at boot is left to you, so the
base starts only `networking` and `syslog`.

## kfetch

`kfetch` prints a system summary with the K logo in the cyan-to-violet brand gradient, on both editions: OS and edition, kernel, host
or board model, uptime, package counts (dpkg and apk), shell, init, terminal, CPU, GPU, memory, disk, local IP and, on the desktop,
the session, layout and theme.

* It is a 6 KB POSIX shell script that runs under BusyBox `ash`, takes about 15 ms, reads `/proc` and `/sys` directly and skips
  whatever a machine does not have.
* `kfetch --small` is a compact version, `kfetch --json` prints one JSON object and `--no-logo` drops the logo.
* Colour is off when `NO_COLOR` is set, and the logo is dropped when stdout is not a terminal.
* No `neofetch` or `fastfetch` symlinks are installed, because both names belong to Debian packages with different options.

<img src="img/kfetch.png" width="700" alt="kfetch">

## Homebrew

`kwick-brew install` sets up [Homebrew](https://brew.sh) (Linuxbrew) at `/home/linuxbrew/.linuxbrew` using the official installer.

* Nothing is preinstalled, so it costs about 0 bytes in the image.
* It first installs the Debian build dependencies it needs (`build-essential`, `procps`, `curl`, `file`, `git`) if they are missing.
* After install Homebrew itself takes about 220 MB, plus roughly 460 MB of build tools on a minimal system.
* `kwick-brew status`, `kwick-brew uninstall` (the official uninstall script) and `kwick-brew shellenv` cover the rest. The desktop
  also has an "Install Homebrew" launcher.
* Supported on x86_64 and arm64 only. Other architectures exit with status 3.
* Once installed, login shells add brew to the end of `PATH` (`/etc/profile.d/20-kwick-brew.sh`), so system tools in `/usr/bin`
  always win.
