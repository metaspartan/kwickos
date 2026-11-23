# Storage and NAS

KwickOS ships no NAS software in the base image. `kwick-storage` (package `kwick-storage`, architecture `all`) adds it module by
module, so a 6.6 MB base image can grow into a file server, a ZFS box or an Unraid-style parity array, and shrink back again.

```
kwick-storage list | status | install <module...> | remove <module...> | all
kwick-storage overview | disks
kwick-storage pool   list | status | create | scrub | snapshot | snapshots | rollback | auto-snapshot
kwick-storage array  status | setup | sync | scrub | fix | teardown
kwick-storage raid   list | create
kwick-storage share  list | add | remove | user
kwick-storage smart  status | email | log | spindown
kwick-storage ups    setup | status
kwick-storage webui | schedules
```

On the desktop the same modules appear in Settings, Storage, together with the disks, pools, arrays and shares of the machine
and an Open Cockpit button.

## Modules

| Module | What it installs | Where it comes from |
| --- | --- | --- |
| `zfs` | prebuilt OpenZFS modules for the running KwickOS kernel, `zfsutils-linux`, `zfs-zed`, `sanoid` | KwickOS repo (modules), Debian 13 `trixie-backports` contrib (userland) |
| `raid` | `mdadm`, `lvm2`, `thin-provisioning-tools`, `bcache-tools` | Debian 13 |
| `btrfs` | `btrfs-progs`, `snapper`, `btrfsmaintenance` | Debian 13 |
| `array` | `mergerfs`, `snapraid`, `xfsprogs` | Debian 13 |
| `shares` | `samba`, `wsdd2`, `avahi-daemon`, `nfs-kernel-server` | Debian 13 |
| `iscsi` | `targetcli-fb` (LIO target) | Debian 13 |
| `smart` | `smartmontools`, `hdparm`, `hd-idle`, the `drivetemp` hwmon module | Debian 13 |
| `ups` | `nut-server`, `nut-client` | Debian 13 |
| `containers` | `docker.io`, `docker-compose`, `podman` | Debian 13 |
| `vms` | `libvirt-daemon-system`, QEMU for the machine's architecture, UEFI firmware, `virtinst`, `virt-manager` on the desktop | Debian 13 |
| `webui` | `cockpit`, `cockpit-storaged`, `cockpit-podman`, `cockpit-files`, `cockpit-machines` (with `vms`), 45Drives `cockpit-file-sharing` and `cockpit-identities` | Debian 13 `trixie-backports`; 45Drives modules are pinned release `.deb`s checked with sha256 |

Debian 13 packages come first, official upstream repositories second, and pinned downloads with sha256 last (only the two
45Drives Cockpit modules, which Debian does not package). 45Drives' `cockpit-zfs` has no downloadable release, so ZFS is managed
with `kwick-storage pool`, the Settings page and the ZFS command line.

Scheduled jobs (ZFS scrub on the first of the month, sanoid every 15 minutes, SnapRAID sync nightly at 03:30 and scrub on
Sundays) are systemd timers when systemd is PID 1 (the desktop) and lines in root's crontab for BusyBox `crond` under kinit
(the headless edition). `kwick-storage schedules` lists them.

## ZFS

### Modules built in CI

Debian's `zfs-dkms` needs headers, a compiler and a matching kernel on the target and breaks easily with a custom kernel.
KwickOS instead builds the modules in CI right after the generic kernel, against that exact build tree:

* `scripts/mkzfspkg.sh <arch> [flavor]` downloads the release tarball pinned in `config/zfs.env` (sha256 checked), applies the
  pinned upstream commits (each `.diff` sha256 checked) and the local patches in `config/zfs/`, regenerates the build system,
  builds `spl.ko` and `zfs.ko` with `--with-config=kernel` (cross-compiling for arm64 and riscv64), checks the vermagic and packages:
  * `kwick-zfs-modules-<kernel release>`: the modules in `/usr/lib/modules/<release>/updates/zfs`, depending on the exact
    `linux-image-kwick-generic` version, providing `zfs-modules` and conflicting with `zfs-dkms`.
  * `kwick-zfs`: a metapackage whose version carries the kernel version (`2.4.4-1+k7.3.4`), depending on the module package and
    on `zfsutils-linux (>= 2.4)`. A kernel bump publishes a new `kwick-zfs`, so `apt upgrade` moves kernel and modules together.
    If a module build ever fails for a new kernel, the old module package pins the old kernel and apt keeps the kernel back
    instead of booting a kernel without ZFS.
* `make zfs ARCH=<arch>` runs it locally. `.github/workflows/build.yml` runs it on every build (riscv64 on release builds, like
  the riscv64 generic kernel), and `release.yml` publishes the packages to the signed apt repository. The step is allowed to
  fail so that a kernel release is never blocked by ZFS; it then writes a warning to the run summary.
* `kwick-storage install zfs` adds `trixie-backports` (contrib) and an apt pin so the userland matches the module version, then
  installs `kwick-zfs`, the module package for the running kernel and `zfs-zed`.

### Version and kernel support

| | |
| --- | --- |
| KwickOS kernel | 7.3.4 (`KERNEL_VERSION`) |
| OpenZFS release | 2.4.4 (2026-08-21), `Linux-Maximum: 7.2` |
| OpenZFS master | 2.4.99, `Linux-Maximum: 7.3` |
| Chosen | 2.4.4 release plus the upstream Linux 7.3 compat commits |
| Userland | `zfsutils-linux 2.4.4-1~bpo13+1` from `trixie-backports` (riscv64: 2.4.3) |

Kernel 7.3 is newer than any OpenZFS release supports. Master gained 7.3 support through PR #19082, but master is a development
branch (2.4.99) whose userland and pool features would not match Debian's packaged 2.4 tools. The safer choice is the stable
2.4.4 release with only the 7.3 compat changes from that PR:

* `d966f3dd8c2e` bvec_iter.bi_bvec_done is now bi_offset (applied as is)
* `cd3699d308e1` make the host filesystem available to kernel threads (applied as is; without it SPL threads would see an
  empty filesystem on 7.3)
* `315bc75afc18` cpu_feature_enabled() instead of static_cpu_has() (mechanical backport: the same substitution in the two files)
* `6e2fa4bc87c3` inode_operations.create dropped its flag arg (backported in `config/zfs/linux-7.3-iops-create.patch`, because
  master restructured that check)
* `a128b8a075b5` META: Linux-Maximum 7.3

`mkzfspkg.sh` reads `Linux-Minimum` and `Linux-Maximum` after patching and refuses to build for a kernel outside the range
(exit code 3, with a message naming `config/zfs.env`). When OpenZFS 2.4.5 or 2.5 ships with 7.3 support, bump `ZFS_VERSION`
and `ZFS_SHA256` and empty the patch lists. `ZFS_ALLOW_UNSUPPORTED=1` builds with `--enable-linux-experimental` for testing only.

### Architectures

| Arch | Modules | Userland | Status |
| --- | --- | --- | --- |
| amd64 | built natively | 2.4.4 backports | built, loaded and tested in a VM |
| arm64 | cross-built (`aarch64-linux-gnu-`) | 2.4.4 backports | built against the arm64 (gb10 flavor) kernel tree; not booted |
| riscv64 | cross-built (`riscv64-linux-gnu-`) | 2.4.3 backports | built against the riscv64 generic kernel; not booted |

### Licensing

OpenZFS is licensed under the CDDL, which is incompatible with the GPL of the kernel. KwickOS never builds ZFS into the kernel
image (no `CONFIG_ZFS`, no built-in patching): the modules are compiled out of tree and shipped only in the separate
`kwick-zfs-modules-*` packages with the CDDL text in `/usr/share/doc/<package>/copyright`, which is the same arrangement Debian
uses for `zfs-dkms` in contrib. Nothing ZFS related is installed unless the user installs it.

### Pools, snapshots and scrubs

```
kwick-storage pool create tank mirror /dev/sdb /dev/sdc            # ashift=12, lz4, xattr=sa, posixacl, mounted at /mnt/tank
kwick-storage pool create tank raidz2 sdb sdc sdd sde --force      # --force wipes disks that hold old data
kwick-storage pool snapshot tank/media before-cleanup
kwick-storage pool rollback tank/media@before-cleanup
kwick-storage pool auto-snapshot tank on                           # sanoid: 24 hourly, 30 daily, 8 weekly, 6 monthly
kwick-storage pool scrub tank
```

Pools are created by `/dev/disk/by-id` names when the disks have one. Without udev (the headless edition) each disk first gets
one GPT partition of the ZFS type, because `zpool` cannot label whole disks without udev. Every new pool gets a monthly scrub.
On the headless edition, where kinit does not follow `zfs.target`, `kwick-zfs-import.service` imports the pools from
`/etc/zfs/zpool.cache`, mounts them and starts zed at boot.

### ZFS root

`kwick-install --fs zfs` installs onto a ZFS root: a pool `kwickpool` on the root partition (optionally inside LUKS with
`--encrypt`), `kwickpool/ROOT/kwick` mounted at `/` and `kwickpool/home` at `/home` (legacy mountpoints in fstab). The kernel
and the installer's initramfs live on the ESP (UEFI) or on an ext4 `/boot` (BIOS, created automatically), so GRUB and
systemd-boot never need to read ZFS. The initramfs carries `spl`, `zfs`, `zpool` and `/etc/hostid`, imports the pool and
mounts the root dataset (`root=ZFS=kwickpool/ROOT/kwick rootfstype=zfs`). The installer fetches OpenZFS into the live system
when it is missing, so it needs the network and the KwickOS repository. `efistub` is not offered for ZFS because it cannot load
an initramfs.

## Unraid-style array (mergerfs + SnapRAID)

```
kwick-storage array setup --data /dev/sdb,/dev/sdc --parity /dev/sdd --format --yes
kwick-storage array sync           # first parity build, then nightly at 03:30
kwick-storage array status
kwick-storage array scrub          # weekly: 8% of the array, blocks older than 10 days
kwick-storage array fix -d d1      # rebuild a failed data disk onto its replacement
```

`setup` partitions and formats the disks (XFS for data, `--fs ext4` to change it, ext4 `largefile4` for parity) when asked
with `--format --yes`, or uses existing filesystems otherwise. It mounts data disks at `/mnt/disk<N>`, parity at
`/mnt/parity<N>` and the pooled view at `/mnt/storage` (`--mount` to change it; mergerfs runs from `kwick-array.service`, which
works under both kinit and systemd), writes `/etc/snapraid.conf` (content files on
every data disk and in `/var/lib/snapraid`) and the fstab entries (by UUID, `nofail`), and checks that each parity disk is at
least as large as the largest data disk. New files go to the data disk with the most free space. Disks of different sizes mix
freely, and every data disk stays a plain filesystem that can be read on its own. Up to six parity disks are supported.

## Shares

```
kwick-storage share add /mnt/storage/media --smb --nfs              # SMB share "media" and an NFS export for the local subnets
kwick-storage share add /srv/public --smb --guest                   # guest access, no password
kwick-storage share add /srv/tm --name TimeMachine --timemachine --user alice
kwick-storage share user alice                                      # set a Samba password
kwick-storage share remove media
```

Samba gets the macOS `fruit` settings, wsdd2 makes the server show up in Windows' Network view, and Avahi advertises it to
Finder. Shares live in `/etc/samba/kwick-shares.conf` and `/etc/exports.d/kwick.exports`; `testparm` validates every change.
NFS exports default to the machine's directly connected networks (`--clients` to override) with `root_squash`.

## Web console

`kwick-storage install webui` installs Cockpit 372 from `trixie-backports`. On the desktop (systemd) it enables `cockpit.socket`.
kinit has no socket activation, so on the headless edition `kwick-cockpit-ws.service` runs `cockpit-ws --for-tls-proxy` on
127.0.0.1:9091 and `kwick-cockpit-tls.service` runs stunnel on port 9090 with a self-signed certificate
(`/etc/kwick/storage/cockpit.pem`). Either way the console is at `https://<host>:9090`. Debian's default of refusing root logins
in Cockpit is kept; log in with the user created by the installer.

## Kernel options (generic flavor)

Added as modules unless noted: md `linear`, `raid0`, `raid1`, `raid10`, `raid456`; dm `snapshot`, `thin-pool`, `cache` (smq),
`writecache`, `raid`, `integrity`, `multipath`; `bcache`; `nbd`; quota (`QUOTA`, `QUOTACTL`, `QFMT_V2`, built in), XFS quota
and ACLs, btrfs ACLs, `f2fs`, ntfs3 ACLs; NFS client 4.2 and the NFS server (`nfsd` with v3 ACLs and v4); the LIO iSCSI target
(`target_core_mod`, iblock, fileio, pscsi, user with `uio`, loopback, `iscsi_target_mod`) and the iSCSI initiator transport;
LSI/Broadcom `mpt3sas` and `megaraid_sas` and Microchip `smartpqi` HBAs; `drivetemp`; `macvtap`. Already present: `md`,
`dm-crypt`, `dm-mirror`, xfs, btrfs, exfat, ntfs3, CIFS client, FUSE, KVM, vhost-net. ZFS itself is never part of the kernel.

## Compared with Unraid and TrueNAS

| Feature | Unraid 7 | TrueNAS 25 | KwickOS |
| --- | --- | --- | --- |
| Base | Slackware, USB boot, paid | Debian, appliance | Debian 13 compatible, 6.6 MB base image, free |
| ZFS | yes (plugin, now built in) | yes, the core of the system | yes: prebuilt modules per kernel, Debian userland, `pool` helper, ZFS root in the installer |
| Parity array of mixed disks | yes, the core of the system | no | yes: mergerfs + SnapRAID; parity is computed on a schedule, not in real time like Unraid |
| mdadm / LVM | no | no | yes |
| Btrfs with snapshots | pools only | no | yes, snapper |
| Snapshot schedules | plugin | yes | yes, sanoid for ZFS, snapper for btrfs |
| Scrub schedules | yes | yes | yes, ZFS monthly, SnapRAID weekly, btrfs via btrfsmaintenance |
| SMB with Windows and macOS discovery | yes | yes | yes, Samba + wsdd2 + Avahi, Time Machine shares |
| NFS | yes | yes | yes |
| iSCSI target | plugin | yes | yes, targetcli; no guided setup yet |
| SMART monitoring and spindown | yes | yes | yes, smartd (journal or email), hd-idle |
| UPS | yes | yes | yes, NUT with USB autodetection |
| Docker apps | yes, app store | yes, app catalog | Docker, Compose and Podman; no curated app catalog |
| VMs | yes | yes | yes, libvirt/QEMU, Cockpit Machines, virt-manager on the desktop |
| Web UI | yes, the whole product | yes, the whole product | Cockpit with storage, VMs, Podman, files and 45Drives sharing and users; ZFS and the parity array are CLI and Settings only |
| Replication | plugins | yes | not integrated (`syncoid` comes with sanoid) |
| Cache pools / tiering | yes | L2ARC, special vdevs | ZFS L2ARC and special vdevs by hand, dm-cache and bcache available; no Unraid-style mover |
| GPU passthrough to VMs | yes | yes | kernel has VFIO; no guided setup |

## Tested

In a QEMU VM (amd64, UEFI, headless edition, generic kernel 7.3.4 with the options above) on six virtio disks:

* `kwick-storage install zfs`, the module loads (`ZFS: Loaded module v2.4.4-1`) with the 2.4.4 backports userland; a mirror
  pool, a snapshot and a rollback; scrub and sanoid jobs in root's crontab; the pool imports and mounts again after a reboot.
* `kwick-storage array setup` on three disks: 30 files spread 15/15 over two XFS data disks, `snapraid sync` and `status` clean,
  everything mounted again after a reboot.
* SMB: a guest share written to from inside the VM and from outside it with `smbclient`; wsdd2 and Avahi running.
* Cockpit served on port 9090.
* `kwick-install run --fs zfs` onto a spare disk with GRUB, then booting it: `/` is `kwickpool/ROOT/kwick`.

Not tested yet: ZFS root with systemd-boot, with `--encrypt` and on BIOS; booting the arm64 and riscv64 module packages; an NFS
mount from a client (the export itself is checked by `exportfs`); the `raid`, `btrfs`, `iscsi`, `smart`, `ups`, `containers`
and `vms` modules beyond their package lists.

## Limitations

* SnapRAID protects from the last sync. Files changed after it are not covered until the next sync.
* The 45Drives Cockpit modules are pinned to specific releases and are not updated by apt.
* NFS exports of a mergerfs or ZFS path get a fixed `fsid` derived from the path.
