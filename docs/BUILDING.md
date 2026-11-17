# Building KwickOS

## Requirements

Linux with Docker, and KVM for fast boot tests. For non-native architectures register binfmt once:

```sh
docker run --privileged --rm tonistiigi/binfmt --install all
```

## Build and test

```sh
make builder                       # build container with cross toolchains + QEMU
make ARCH=amd64                    # busybox, kinit, kpkg, kernels (virt+generic), rootfs, images
make boot-test ARCH=amd64          # boots microvm, ram, disk, UEFI disk, UEFI ISO
make container compat ARCH=amd64   # real-world Debian package compatibility matrix
bash bench/container.sh kwickos:0.1.0-amd64   # container benchmarks vs Alpine/Debian/Ubuntu
make headless-iso ARCH=amd64       # kwickos-amd64-headless.iso, UEFI and BIOS
make headless-iso-grub             # the same with a GRUB menu (live, safe graphics, install)
```

The kernel version is pinned in [`KERNEL_VERSION`](../KERNEL_VERSION). The build verifies the tarball checksum against kernel.org.

Raspberry Pi 4 and 5 (arm64, after `make userland kpkg rootfs ARCH=arm64`; this is what `.github/workflows/rpi.yml` runs).
The kernel comes from `raspberrypi/linux` `rpi-7.3.y` at the commit in `config/kernel/rpi.source`, the firmware blobs
from the release pinned in `config/rpi-firmware.env`. The image lands in `out/arm64/kwickos-arm64-rpi.img(.zst)` and
`tests/rpi-boot.sh` boots it under QEMU `raspi4b`:

```sh
docker run --rm -v $PWD:/src -v $PWD/out:/out -v kwick-build:/build -v kwick-cache:/cache kwick-builder bash -c '
  bash /src/scripts/build-kernel-variant.sh arm64 rpi &&
  bash /src/scripts/mkrpifwpkg.sh &&
  bash /src/scripts/mkkernelpkg.sh arm64 rpi && bash /src/scripts/mkkernelhdrpkg.sh arm64 rpi &&
  KEEP_IMG=1 bash /src/scripts/mkrpiimage.sh &&
  bash /src/tests/rpi-boot.sh'
```

Optional packages are built by their own scripts in `scripts/` (`mkdesktoppkg.sh`, `mkgamingpkg.sh`, `mkpenpkg.sh`,
`mkagentspkg.sh`, `mkstoragepkg.sh`, `mkzfspkg.sh`, `mkgpupkg.sh`, `mkdarlingpkg.sh` and others). The release workflow and
`tools/vmlab/buildrepo.sh` build them next to the base.

## Source tree

| path | contents |
|---|---|
| `src/kinit/` | init system (C) |
| `src/kpkg/` | package manager (Go) |
| `src/kwin-flip/` | native KWin Flip effect plugin (C++) |
| `config/kernel/` | kernel config fragments (common, per-arch, `virt`/`generic`/`apple`/`gb10`) |
| `config/busybox/` | BusyBox config + GNU-compatibility patches |
| `rootfs/` | files copied into the base system |
| `desktop/` | desktop image, theme and catalog generators, the files shipped by `kwick-desktop` |
| `storage/` | `kwick-storage` |
| `scripts/` | build steps (userland, kernel, rootfs, images, packages, apt repo) |
| `site/` | the project site, which also hosts the signed apt repository |
| `tools/` | icon generator and the KVM/GPU verification lab (`tools/vmlab/`) |
| `tests/` | boot matrix, VM functional test, package compatibility matrix, desktop screenshot script |
| `bench/` | benchmarks against Alpine/Debian/Ubuntu |
| `.github/workflows/` | CI build and test for 3 arches, releases, kernel watch |

## Releases and security

Every push to `main` that changes the product, and every kernel bump found by `kernel-watch` (kernel.org is polled every 6 hours),
triggers the `release` workflow. It builds and boot-tests all architectures, then publishes `v<version>-k<kernel>` with ISOs, disk
images, the multi-arch container on ghcr.io and the signed apt repo.

`.github/workflows/security.yml` runs on every push and nightly: kernel freshness, `govulncheck` for kpkg, OSV advisories and a grype
scan of the built image.

## Verification

The desktop was verified in KVM virtual machines with a GPU-accelerated display on an AMD Radeon 8060S host. The log, the lab setup
(`tools/vmlab/`), the bugs found and fixed, and the list of things that were not verified are in [VERIFICATION.md](VERIFICATION.md).
