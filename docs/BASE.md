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
* Packages install without their documentation, like Debian's slim container images. `/etc/dpkg/dpkg.cfg.d/excludes` skips
  `/usr/share/doc` (copyright files stay), man and info pages, groff and lintian data, and translations other than English and C.
  To turn it off, delete the file (or comment out a line in it) and reinstall the packages whose files you want back, for example
  `rm /etc/dpkg/dpkg.cfg.d/excludes; apt install man-db; apt install --reinstall nginx`. The desktop edition does not have the
  file.
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
| HTTPS downloads | none: `wget` refuses `https://` until it can verify certificates (see below) | `curl` (60 MB with `ca-certificates`), or `ca-certificates` and `openssl` so `wget` verifies |
| remote access | `nc`, `telnet`, `ssl_client` | `openssh-client` (61 MB), `openssh-server` (89 MB), `rsync` (28 MB) |
| time zones and keymaps | `TZ=` with POSIX rules (`TZ=CET-1CEST,M3.5.0,M10.5.0/3`), clock via `hwclock` | `tzdata` (31 MB), `kbd` (18 MB) for `loadkeys` |
| editors, pager, shell | `vi`, `less`, `ash` (history, line editing, coloured `user@host:dir$` prompt), `watch`, `kwick-shell` | `nano` (21 MB), `bash` (fetched when something needs it) and `bash-completion`, `zsh` (about 19 MB installed, 5 MB download), `fish` |
| users and privilege | `adduser`, `addgroup`, `passwd`, `su`, `chpasswd` | `sudo` (51 MB) |
| scheduling and logs | `crond`, `crontab`, systemd `.timer` units (`systemctl list-timers`), `syslogd`, `logread`, `dmesg` | `rsyslog`, `logrotate` (runs daily from `logrotate.timer`) |
| disks | `fdisk`, `mkfs.ext2`, `mkfs.vfat`, `mkswap`, `mount` (loop, CIFS; vfat, ext4, `ntfs3` and `exfat` in the kernel), `lsblk`, `blkid`, `losetup`, `fsck` | `e2fsprogs` (19 MB), `parted` (21 MB), `exfatprogs` (17 MB), `ntfs-3g` (57 MB), `xfsprogs`, `btrfs-progs` |
| archives | `tar`, `gzip`, `bzip2`, `xz`, `unzip`, `cpio` | `zstd` (23 MB), `p7zip` |
| hardware and processes | `lspci`, `lsusb`, `lsmod`, `modprobe`, `top`, `ps`, `free`, `lsof`, `kfetch` | `htop` (18 MB), `pciutils`, `usbutils`, `strace` |
| containers | `unshare`, `nsenter`, `chroot` and a kernel with namespaces and cgroups | `podman` (197 MB), `docker.io` (see the compatibility matrix) |
| installer | `kwick-install`, `kwick-installer` | fetches `fdisk`, `e2fsprogs`, GRUB and so on when needed |

BusyBox `wget` in the base cannot verify TLS certificates on its own (the base carries no TLS library and no CA bundle), so it
refuses `https://` URLs and says what to install: `apt install curl`, or `apt install ca-certificates openssl`, after which `wget`
hands the connection to `openssl s_client` with certificate and host name verification against
`/etc/ssl/certs/ca-certificates.crt` (or `$SSL_CERT_FILE`). `--no-check-certificate` fetches without verification when you ask
for it. `apt` itself is unaffected: kpkg checks the repository signatures and hashes, so it fetches `https://` sources
with `--no-check-certificate` when `curl` is missing. The base has no `sudo`: log in as root or install it. Enabling anything
at boot is left to you, so the base starts only `networking` and `syslog`.

## Shells

The headless base keeps BusyBox `ash` as the login shell, so it carries no shell package. Debian's `zsh` and `zsh-common` need about
19 MB installed, three times the base, which would end the size lead over Alpine. The desktop edition ships zsh as the default, like
macOS, and either edition can switch with `kwick-shell`.

```
kwick-shell                       current shell, the default for new users, the prompt preset and what is installed
kwick-shell NAME                  change your login shell, installing it first when it is missing
kwick-shell --user NAME zsh       change another user's shell (root)
kwick-shell --default zsh         change the shell given to users created from now on (root)
kwick-shell prompt NAME           kwick, minimal, powerline or starship prompt in every shell
```

Shells: `zsh`, `bash`, `fish`, `ash`, `nushell`, `elvish`, `xonsh`, `powershell`. [SHELLS](SHELLS.md) lists their sources and
versions, the prompt presets and the desktop shells.

* `kwick-shell` is a POSIX script. It installs with `apt` (Nushell and PowerShell from their official releases, checked against a
  pinned SHA-256), adds the shell to `/etc/shells`, and changes the login shell with `chsh` or `usermod`, or edits `/etc/passwd` itself
  when the base has neither. As a normal user it goes through `pkexec /usr/lib/kwick/shell-helper` (no password for your own shell in
  the active session) or `sudo`. `--default` writes `SHELL=` to `/etc/default/useradd` (what `useradd` reads) and `DSHELL` in
  `/etc/adduser.conf` when that exists.
* A change applies at the next login. `exec zsh` switches the current terminal at once.
* The desktop picks zsh for the live user, for `useradd` and `adduser` defaults and for the account `kwick-install` creates.
  `kwick-install --shell zsh|bash|ash|fish` overrides that. The Settings app has the same choice under Shells.
* The zsh setup is one file, `/usr/share/kwick/zsh/kwick.zsh`, loaded from `/etc/zsh/zshrc` and from `~/.zshrc` in `/etc/skel`. It
  gives a Terminal-style `user@host dir %` prompt whose directory colour follows the layout (blue for macOS, Fluent blue for
  Windows, indigo for Linux), history shared between sessions, `compinit` with a cached dump and a selectable completion menu,
  Home, End, Delete, Ctrl and Alt arrow keys, `ls` colours, and Debian's `zsh-autosuggestions` and `zsh-syntax-highlighting`. There is
  no framework, and `zsh -i -c exit` takes about 30 ms.
* `ash` reads `/etc/profile` as a login shell and `/etc/ashrc` (set as `ENV`) in nested shells, so the prompt and aliases (`ls`, `ll`,
  `la`, `grep`, `..`, `df -h`) are the same either way. The prompt is the same `user@host dir $` as in the other shells
  (`/usr/share/kwick/shell/prompt.sh`), red for root, and plain without a colour terminal or with `NO_COLOR`.

## kfetch

`kfetch` prints a system summary with a bold K in the cyan-to-violet brand gradient, on both editions: OS and edition, kernel, host
or board model, uptime, package counts (dpkg and apk), shell, init, terminal, CPU, GPU, memory, disk, local IP and, on the desktop,
the session, layout and theme.

* It is a 10 KB POSIX shell script that runs under BusyBox `ash`, takes about 15 ms, reads `/proc` and `/sys` directly and skips
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
