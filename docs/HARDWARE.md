# Hardware support

Status legend, applied honestly:

* **Verified**: booted and exercised, by the project, on the real thing or an equivalent virtual machine.
* **Built**: the pieces build in CI or were built locally and pass static checks, but nothing has been booted on the real hardware. Expect first-boot problems and please report them.
* **Upstream**: works with the stock kernel by virtue of mainline drivers, not specifically tested by this project.
* **Unsupported**: no packages, no kernel options, or known not to work.

KwickOS itself has no hardware lab. Anything that needs physical hardware that is not listed as Verified is Built or Upstream at best.

## Kernel flavors

| Flavor | Arch | Purpose | Package |
| --- | --- | --- | --- |
| virt | amd64, arm64, riscv64 | tiny VM and microVM kernel | `linux-image-kwick-virt` |
| generic | amd64, arm64, riscv64 | broad bare-metal hardware, modules | `linux-image-kwick-generic` |
| apple | arm64 | Asahi tree, 16K pages, Apple Silicon Macs | `kwick-kernel-asahi` |
| gb10 | arm64 | NVIDIA DGX Spark (GB10), ACPI, SMMUv3, NUMA, mlx5 | `linux-image-kwick-gb10` |
| rpi | arm64 | Raspberry Pi 4 and 5 (Raspberry Pi Foundation `rpi-7.3.y` tree), 4K pages, Pi firmware boot | `linux-image-kwick-rpi` |

Every flavor has a matching `linux-headers-kwick-<flavor>` (or `kwick-kernel-asahi-headers`) package that provides `/lib/modules/<release>/build`, so DKMS and out-of-tree modules work. That was checked by building NVIDIA's open modules against the extracted amd64 headers package.

## x86-64 GPUs

| Vendor | Stack | Status |
| --- | --- | --- |
| Intel (Gen8 and newer, Arc, Xe) | i915 or xe kernel driver, Mesa iris and ANV, VA-API | Upstream |
| AMD (GCN 1.0 and newer) | amdgpu kernel driver, Mesa radeonsi and RADV, firmware from Debian non-free-firmware | Upstream |
| NVIDIA Turing and newer | NVIDIA open kernel modules (pinned release, see `config/nvidia.env`) plus userspace from NVIDIA's Debian 13 CUDA repository, installed by `kwick-gpu install` through `/usr/lib/kwick/gpu-nvidia` | Built: the modules were compiled against the KwickOS 7.3.4 amd64 kernel tree and against the extracted headers package; not run on a GPU |
| NVIDIA Pascal and older | nouveau kernel driver and Mesa NVK or nouveau | Upstream, performance limited by reclocking |
| virtio-gpu, QXL, Bochs, VMware, Hyper-V | in-tree DRM drivers, Mesa virgl or llvmpipe | Verified under QEMU (virtio, software rendering) |

Notes:

* The helper only enables NVIDIA's open modules for PCI device ids at or above 0x1e00, which is Turing and newer. NVIDIA's open modules do not support older GPUs.
* Kernel module and userspace versions are pinned together (`NVIDIA_DRIVER_VERSION`). The helper writes an apt preference at priority 1001 for that exact version.
* The repository key is verified by fingerprint before it is trusted. NVIDIA's Debian 13 key is not the older CUDA key.
* 32-bit libraries (`nvidia-driver-libs:i386`) are installed only when the i386 architecture is already enabled, for example by the Steam path.

## Apple Silicon

Apple Silicon support is the Asahi Linux project's work. KwickOS packages their pinned kernel tree, m1n1 and U-Boot and uses their installer.

**Intel Macs are not a target.** KwickOS supports Macs only through Apple Silicon (arm64). There are no Intel Mac or T2 packages, kernel options, drivers or boot handling, none are planned, and Intel Macs are not tested. Reports about Intel Macs are out of scope.

| Generation | Kernel | GPU | Status |
| --- | --- | --- | --- |
| M1, M1 Pro, M1 Max, M1 Ultra | Asahi tree | `asahi` DRM driver with Mesa asahi (OpenGL) and honeykrisp (Vulkan) from trixie-backports | Built |
| M2, M2 Pro, M2 Max, M2 Ultra | Asahi tree | same | Built |
| M3 family | boots in the Asahi tree, work in progress (daily use is not yet realistic per Asahi) | not supported | Unsupported for now; device trees are present, nothing else is promised |
| M4 and M5 | device trees only reached the mailing list | none | Unsupported |

What was verified for the Built entries: the pinned Asahi tag `asahi-7.3.3-2` was configured and compiled to completion in the KwickOS builder (defconfig, `asahi.config`, KwickOS fragments, Rust enabled with Debian trixie rustc 1.85.1 and bindgen 0.71.1). The result is a 47 MB EFI-stub `Image`, 1666 modules including `asahi` and `apple` DRM, device trees for all Apple SoCs, and `nvme_apple`, DART, SART, AIC, PCIe, USB and SMC drivers built in so the root partition is reachable with the embedded kinit. It was not booted on a Mac.

Boot chain: macOS or recoveryOS runs the Asahi installer, which creates the ESP and runs m1n1 stage 1. m1n1 loads `m1n1/boot.bin` (m1n1 stage 2, the device trees, then U-Boot), U-Boot's UEFI boots `EFI/BOOT/BOOTAA64.EFI`, which is the KwickOS kernel with kinit embedded, and kinit mounts the `kwick-root` partition. `kwick-apple-boot` rebuilds `m1n1/boot.bin` and installs the kernel whenever `kwick-kernel-asahi` is installed.

Things that must be true on a Mac, and are not yet verified:

* The Asahi installer accepts the generated `installer_data.json` and zip package.
* U-Boot built from the pinned Asahi tag with `apple_m1_defconfig` boots on all supported models.
* `asahi-fwextract` from trixie handles the firmware tarball staged by the installer for the macOS version in use. The extraction target (`firmware.tar` or `firmware.cpio` in `/lib/firmware`) is handled for both layouts but untested.
* The 16K page size works with the userland you install. Debian's arm64 userland is mostly page-size agnostic, but some software (jemalloc configured for 4K, some JITs, Chrome-family browsers in some builds) has historically needed fixes. Fedora Asahi Remix ships a 16K userland and patches for this.
* Speakers: `speakersafetyd` is not in Debian. KwickOS builds the pinned upstream tag. Do not enable the internal speakers without it running.

Not packaged: the Touch Bar daemon `tiny-dfr`, Thunderbolt/USB4 display tunnelling quirks, camera (ISP), and microphones other than the headset path. Hardware video decode (`avd`) needs extra work.

Installation for users: run `kwickos-apple-bootstrap.sh` from macOS (it downloads Asahi's installer and points it at the KwickOS metadata), choose to add a new OS, and let the installer shrink macOS to make room. Never repartition the APFS containers by hand. Alternatively write the `kwickos-arm64-apple.img.zst` disk image to a free partition area following Asahi's UEFI-only install procedure.

## NVIDIA DGX Spark (GB10) and other GB10 systems

GB10 is a Grace-Blackwell arm64 system on a chip, booted through UEFI and described by ACPI. NVIDIA's DGX OS is Ubuntu 24.04 based with NVIDIA's own `linux-nvidia` kernel (6.17, and 7.0 as of the October 2026 software update). NVIDIA's kernel carries Grace-Blackwell patches that are not in mainline, so mainline-only kernels can lack features. GB10 needs NVIDIA's open GPU kernel modules, not the proprietary modules and not nouveau.

| Piece | Status |
| --- | --- |
| `gb10` kernel flavor (4K pages, ACPI, SMMUv3, NUMA, memory hotplug, ZONE_DEVICE, HMM, PCIe DOE, NVMe, mlx5 and RDMA, r8169, mt7925e, TPM) | Built: configured and built from the KwickOS 7.3.4 tree with all required options present |
| NVIDIA open modules `595.112.07` for arm64 | Built: cross-compiled locally against the `gb10` kernel tree (vermagic `7.3.4-gb10-kwick SMP preempt mod_unload aarch64`), packaged as `kwick-nvidia-kmod-<release>`; never loaded on a GB10 |
| Userspace (`libcuda1`, `nvidia-smi`, `firmware-nvidia-gsp`) from NVIDIA's Debian 13 sbsa repository | Built: package names and versions checked against the repository index; not installed on a Spark |
| ConnectX-7 200 GbE (mlx5 and RDMA) | Built, not tested; `nvidia-peermem` and GPUDirect RDMA on Spark have known issues reported by users |
| Onboard 10 GbE | Believed to need `r8169` with RTL8127 support (mainline since the 6.1x series per user reports); unverified |
| Wi-Fi and Bluetooth (MediaTek MT7925) | Built (`mt7925e`, `btusb` with MediaTek support); firmware from `firmware-mediatek` |
| Suspend, thermal and power-management behaviour | Unknown; NVIDIA's kernel patches may be required |

DGX OS ships a recovery environment and firmware updates; keep it. KwickOS has not been installed on a Spark.

## Other arm64

| Hardware | Status |
| --- | --- |
| QEMU virt (virtio), UEFI | Verified |
| ServerReady (SBSA) servers and VMs with UEFI and ACPI (Ampere, Graviton, Azure Cobalt, Hetzner CAX, Oracle A1) | Upstream: the generic arm64 flavor has the common NIC, NVMe, and virtio drivers; not specifically tested |
| Raspberry Pi 4, 400, CM4, 5, 500, CM5 | Built: `rpi` flavor and `kwickos-arm64-rpi.img.zst`, booted under QEMU `raspi4b` only; see [Raspberry Pi 4 and 5](#raspberry-pi-4-and-5) |
| Other Arm boards with device trees (Rockchip, Allwinner, Amlogic, i.MX) | Unsupported |
| Apple Silicon virtualization (UTM, Lima, Parallels) | Verified with the arm64 virt images |

## Raspberry Pi 4 and 5

One image, `kwickos-arm64-rpi.img.zst`, and one kernel flavor, `rpi` (`linux-image-kwick-rpi`, `linux-headers-kwick-rpi`), cover the Raspberry Pi 4, 400 and Compute Module 4 (BCM2711) and the Raspberry Pi 5, 500 and Compute Module 5 (BCM2712).

| Board | Device tree shipped | Status |
| --- | --- | --- |
| Raspberry Pi 4 Model B | `bcm2711-rpi-4-b.dtb` | Built. The image's kernel, device tree, SD driver, root mount by label, first-boot growth and userland were booted under QEMU `raspi4b` (see below); not booted on a real Pi 4 |
| Raspberry Pi 400 | `bcm2711-rpi-400.dtb` | Built |
| Compute Module 4 (and CM4S) | `bcm2711-rpi-cm4.dtb`, `bcm2711-rpi-cm4s.dtb` | Built; eMMC variants boot from eMMC like an SD card |
| Raspberry Pi 5 (C1 and D0 steppings) | `bcm2712-rpi-5-b.dtb`, `bcm2712d0-rpi-5-b.dtb` | Built; nothing can emulate it (QEMU has no `raspi5`) |
| Raspberry Pi 500 | `bcm2712-rpi-500.dtb` | Built |
| Compute Module 5 (and CM5 Lite) on the CM5 or CM4 IO board | `bcm2712-rpi-cm5-cm5io.dtb`, `bcm2712-rpi-cm5-cm4io.dtb`, `bcm2712-rpi-cm5l-*.dtb` | Built |
| Raspberry Pi 3 and older, Zero 2 W | none | Unsupported |

### Kernel: the Raspberry Pi Foundation tree, not mainline

The `rpi` flavor is built from `raspberrypi/linux` branch `rpi-7.3.y` at commit `b005af6699cc67413be78028a201e87fe40dcb50` (Linux 7.3.5, the same version as the kernel.org `KERNEL_VERSION` the other flavors use since 2026-11-17) with `bcm2711_defconfig` plus `config/kernel/rpi.config` (pinned in `config/kernel/rpi.source`). The decision, checked on 2026-11-17:

* **What mainline 7.3.4 has.** The KwickOS 7.3.4 tree carries `bcm2712-rpi-5-b.dts` and `bcm2712-d-rpi-5-b.dts`, the RP1 driver (`drivers/misc/rp1`, mainline since 6.17), RP1 Ethernet in `macb` (`raspberrypi,rp1-gem`), RP1 USB through `dwc3`, the BCM2712 SD controller (`sdhci-brcmstb`), BCM2712 PCIe (`pcie-brcmstb`), the BCM2712 display pipeline in `vc4` (HVS, pixel valves, both HDMI ports) and V3D 7.1 in `v3d` (`brcm,2712-v3d`). The code for Pi 5 Ethernet, USB, SD, HDMI and v3d is present.
* **Why it is not used.** Mainline has no device tree for the Pi 500, the CM5 or the CM5 Lite, and names the Pi 5 D0 tree `bcm2712-d-rpi-5-b.dtb` where the firmware looks for `bcm2712d0-rpi-5-b.dtb`. The RP1 PWM driver that runs the Pi 5 active cooler's fan was still under review in June 2026 (v5 of the series), as were the BCM2712 IOMMU driver (July 2026) and a `macb` TX-stall recovery for RP1 Ethernet (June 2026). The one public report of RP1 Ethernet on mainline (v6.18-rc3, LKML, October 2025) saw the PHY and the link come up but no traffic, and nothing later shows it working. Every `dtoverlay=` and `dtparam=` the firmware applies from `config.txt` (`vc4-kms-v3d`, `pciex1` for M.2 HATs, HATs, cameras, displays) is written against the Foundation's device trees and does not apply to mainline ones. Pi 5 Ethernet on mainline could not be shown to work, so the requirement for using mainline was not met.
* **Revisit** when mainline has the RP1 PWM driver, Pi 500 and CM5 device trees and a confirmed working RP1 Ethernet. The Foundation's default branch is `rpi-6.18.y`, which Raspberry Pi OS ships; `rpi-7.3.y` follows the kernel.org 7.3 stable series and is less widely deployed.
* **Page size.** 4K pages (`CONFIG_ARM64_4K_PAGES=y`). Raspberry Pi OS boots a 16K-page `kernel_2712.img` on the Pi 5 for a few percent more speed, but 16K pages break some Debian software (jemalloc built for 4K, some JITs and Chromium builds), so KwickOS boots the same 4K `kernel8.img` on the Pi 4 and the Pi 5, and `config.txt` names it (`kernel=kernel8.img`).
* **Built in, so the embedded kinit can mount the root:** SD and eMMC (`MMC_SDHCI_IPROC` and `MMC_BCM2835` on the Pi 4, `MMC_SDHCI_BRCMSTB` on the Pi 5), USB mass storage and UAS (`USB_XHCI_PCI` behind the Pi 4's VL805, `MFD_RP1` and `USB_DWC3` on the Pi 5), NVMe over PCIe (`PCIE_BRCMSTB`, `BLK_DEV_NVME`), ext4, and both Ethernet drivers (`BCMGENET` on the Pi 4, `MACB` on the Pi 5). `vc4` and `v3d` are modules; the fan (`PWM_RP1`, `SENSORS_PWM_FAN`) is built in.

### Boot partition and image layout

The Raspberry Pi has no UEFI; its firmware reads a FAT partition. The Pi 4 runs `start4.elf` and `fixup4.dat` from that partition; the Pi 5 has its bootloader in EEPROM and reads only `config.txt`, the kernel and the device trees. KwickOS uses no U-Boot.

`kwickos-arm64-rpi.img.zst` is an MBR disk, which every Pi 4 and Pi 5 bootloader version reads:

| Partition | Size | Contents |
| --- | --- | --- |
| 1, FAT32, type `0x0c`, label `KWICKBOOT`, from 4 MiB | 256 MiB | `kernel8.img` (the kernel with kinit embedded), `bcm2711-*.dtb`, `bcm2712*.dtb`, `overlays/` (the 387 overlays of the same kernel build, with `overlay_map.dtb`), `start4.elf`, `fixup4.dat`, `LICENCE.broadcom`, `config.txt`, `cmdline.txt`; mounted at `/boot/firmware` |
| 2, ext4, type `0x83`, label `kwick-root` | 1 GiB in the image | the KwickOS root; `kwick-growroot.service` grows the partition and the filesystem to the end of the card on first boot |

`config.txt` sets `arm_64bit=1`, `kernel=kernel8.img`, `enable_uart=1`, `dtoverlay=vc4-kms-v3d` (full KMS for the desktop and the console), `display_auto_detect=1`, and `dtparam=pciex1` under `[pi5]` so an NVMe drive on an M.2 HAT is visible. `cmdline.txt` is `console=serial0,115200 console=tty1 root=LABEL=kwick-root rootfstype=ext4 rootwait rootdelay=60`. MBR partitions have no partition names, so the root is found by its ext4 label; `rootdelay=60` gives kinit a minute for slow USB drives (kinit ignores `rootwait`, the kernel never waits itself because kinit is the initramfs). Both files are written only when missing and are never overwritten.

The firmware blobs come from `raspberrypi/firmware` release `1.20260915` (commit `6f0881cba8be`), are checked against the SHA-256 sums in `config/rpi-firmware.env`, and ship only in the `kwick-rpi-firmware` package and the Pi image, never in the base. `kwick-rpi-firmware` also carries `kwick-rpi-boot`, the counterpart of Debian's `raspi-firmware` hooks. `linux-image-kwick-rpi` depends on it; its `postinst` runs `kwick-kernel-install`, `kwick-kernel` recognises the `rpi` boot path from the device tree and calls `kwick-rpi-boot install <release>`, which copies `kernel8.img` (keeping the previous one as `kernel8.prev.img`), the device trees and the overlays of that kernel to `/boot/firmware` and refreshes `start4.elf` and `fixup4.dat`. `kwick-kernel default`, `rollback` and `list` work; `try` does not (the firmware's `tryboot` mode is not wired up). Root growth is a small kinit applet, `kwick-growroot`: it rewrites the last MBR partition entry, tells the kernel with `BLKPG_RESIZE_PARTITION` and grows ext4 online, so the base needs neither `growpart`, `sfdisk` nor `resize2fs`.

### Desktop

`apt install kwick-desktop` is meant to work on the Pi image: the desktop package accepts `linux-image-kwick-rpi` in place of the generic kernel, and `kwick-gpu` detects the Pi from the device tree (`brcm,bcm2711`, `brcm,bcm2712`) and installs Mesa (`libgl1-mesa-dri`, `mesa-libgallium`, `mesa-vulkan-drivers` with v3dv, `libgles2`) and `firmware-brcm80211` for the on-board Wi-Fi. Rendering is hardware OpenGL ES 3.1 and OpenGL 3.1 through Mesa's `v3d` driver with `vc4` as the KMS display device; the KWin plugins are built for arm64 by the release workflow. The desktop has not been run on a Pi; plan on a 4 GB board or larger for Plasma.

### What was tested without hardware

* Built locally and in CI (`.github/workflows/rpi.yml`, on a native arm64 runner): the kernel (`7.3.5-kwick-rpi`, a 29 MB `Image`, 1886 modules), `linux-image-kwick-rpi`, `linux-headers-kwick-rpi` (complete `Module.symvers` and arm64 `scripts/`), `kwick-rpi-firmware`, and the image (47 MB compressed). The workflow checks the device trees, overlays, required kernel options, the `vc4` and `v3d` modules and the arm64 `Image` header.
* `tests/rpi-boot.sh` boots the image under QEMU 10.0 `-M raspi4b` (2 GB) from a 4 GiB SD card. `kernel8.img` and `bcm2711-rpi-4-b.dtb` are taken from the image's FAT partition and loaded directly, because QEMU cannot run the VideoCore firmware; the console is the PL011, because QEMU's mini UART does not probe, and the Bluetooth node is removed from a copy of the device tree so the PL011 is free. Evidence from 2026-11-17:

  ```
  Machine model: Raspberry Pi 4 Model B
  mmcblk1: mmc1:eaf4 QEMU! 4.00 GiB
  EXT4-fs (mmcblk1p2): mounted filesystem 8392c7dc-... r/w with ordered data mode.
  kinit: KwickOS 0.6.0 ready in 3831 ms (since kernel start)
  growroot: partition 2 of mmcblk1 grown from 1024 to 3836 MiB
  KW-REL 7.3.5-kwick-rpi
  /dev/mmcblk1p1 /boot/firmware vfat rw,noatime,...
  boot path      rpi
  partition 2: 3836 MiB, ext4: 3836 MiB, card: 4G
  RESULT raspi4b ok wall_s=38
  ```

  QEMU's `raspi4b` has no PCIe, USB, Ethernet, GPU, VideoCore firmware or Pi 5 model, so this exercises the kernel, the Pi 4 device tree, the SD driver, kinit's root search by label, `kwick-growroot`, the `/boot/firmware` mount and `kwick-kernel`'s boot path detection, and nothing else.

### Not verified on real hardware

Everything that needs a Pi: the VideoCore firmware loading `kernel8.img` with this `config.txt` on a Pi 4, the Pi 5 EEPROM bootloader doing the same, the firmware's translation of `console=serial0`, Ethernet (GENET on the Pi 4, RP1 on the Pi 5), USB, NVMe and USB boot (both also need the EEPROM `BOOT_ORDER`, which KwickOS does not change), HDMI and the KMS desktop, `v3d` acceleration, Wi-Fi and Bluetooth, the Pi 5 fan, the Pi 400, CM4, Pi 500 and CM5, and `kwick-growroot` on a real card. KwickOS does not update the EEPROM; do that with Raspberry Pi OS or Raspberry Pi Imager if it is old. Reports move entries from Built to Verified.

## riscv64

| Hardware | Status |
| --- | --- |
| QEMU virt with OpenSBI and UEFI | Verified (boot test in CI) |
| Banana Pi BPI-F3 (SpacemiT K1) | Verified on mainline 7.3.4 (`k1mainline` flavor, the default) and on the vendor 6.1.15 kernel: eMMC install, both Ethernet ports, NVMe, USB, ssh, apt, all with the board's 2024 vendor firmware. The `k1` flavor (SpacemiT BSP 6.6.63) is unsupported and no longer built or shipped by default. See below |
| Other SpacemiT K1 boards (Milk-V Jupiter, Muse Pi Pro, Orange Pi RV2) | Upstream: same kernel and mainline device trees, not tried |
| VisionFive 2, Milk-V, HiFive boards | Unsupported: no board device trees or vendor firmware handling; the generic flavor is built only in release CI |

### Banana Pi BPI-F3

The board keeps its vendor boot chain (BootROM, FSBL, OpenSBI 1.3 and U-Boot 2022.10 from SpacemiT, on the SD card of an Armbian image). The BootROM tries the SD card first, then the medium the boot DIP switch selects (eMMC, SPI NOR or SPI NAND). KwickOS does not replace the bootloader. It lives on the eMMC user area: a GPT disk with a 512 MiB vfat ESP (`KWICKESP`) and an ext4 `kwick-root` partition. Armbian stays on the SD card as the fallback system.

**What boots today.** The SD card's U-Boot imports `/boot/env_k1-x.txt` from the SD card's FAT partition. KwickOS adds a few `kwick_*` variables to that file (the original is kept as `env_k1-x.txt.armbian`). By default U-Boot boots the vendor 6.1.15 kernel, initrd and `k1-x_deb1.dtb` from the SD card with `root=/dev/mmcblk2p2 init=/usr/lib/kwick/init-crumb`, exactly the way Armbian boots except for the root. The vendor kernel needs an initrd: its power-management co-processor loads `esos.elf` at about 4 s, before the root filesystem exists, and without it the boot stalls.

**Fallback.** Before every KwickOS boot U-Boot writes `kwick-attempt` to the SD card's FAT partition. `kwick-boot-ok.service` deletes it once the system has had an IPv4 address for 60 s. If U-Boot finds `kwick-attempt` at the next boot, the previous boot failed: it deletes the file, creates `kwick-mode-armbian` and boots Armbian, and stays there until switched back. With the vendor kernels a hang costs one power cycle. The mainline kernel needs none (see the next paragraph). `init-crumb` logs the kernel release to `/var/log/kinit-start`, saves `dmesg` to `/var/log/boot-dmesg-early` at once and to `/var/log/boot-dmesg-25s` after 25 s, starts the SoC watchdog when the device tree enables it, and reboots after 120 s without an IPv4 address (logs in `/var/log/boot-dmesg-safety`).

**Mainline boot path.** `linux-image-kwick-k1mainline` ships `uboot.txt`, which `kwick-bootctl set-kernel` appends to `kwick.txt`. It redefines `kwick_boot` for that kernel only:

1. stop the PMIC watchdog and start the SoC watchdog (`watchdog@D4080000`) with a 240 s timeout (`wdt start 240000`, 256 Hz counter, 255 s maximum);
2. write `kwick-attempt` as usual;
3. run `bootm start`, `bootm loados` and `bootm prep` with `fdt_high=0xffffffffffffffff`, so U-Boot loads the FIT, adds the memory nodes, the OpenSBI reserved memory and `bootargs` to the mainline DTB in place;
4. jump with `go` instead of `bootm go`.

`bootm go` removes all U-Boot devices first, and the SpacemiT watchdog driver stops the watchdog in its remove hook. `go` leaves it running into Linux. Mainline 7.3 has no K1 watchdog driver, so `init-crumb` feeds the watchdog through `/dev/mem` (unlock `0xbaba`/`0xeb10` at `0xd40800b0`/`0xb4`, counter reset at `0xd40800c8`) every 10 s and stops it once `kwick-boot-ok` has confirmed the boot. An unconfirmed boot stops being fed after 900 s. A hang anywhere from U-Boot to userspace therefore resets the board within 240 s, and the attempt counter lands on Armbian without a power cycle. `go` passes `argc` and `argv` instead of the hart id and the DTB, so the FIT kernel image starts with a 4 KiB stub (`FIT_STUB_DTB` in `config/kernel/k1mainline.source`). It loads at `0x1ff000`, disables interrupts, sets `a0=0` and `a1=0x31000000` (the env's `dtb_addr`) unless `a1` already points at a DTB, runs `fence.i` and jumps to the kernel at `0x200000`. A plain `bootm` of the same FIT also works. Panics reboot through the P1 PMIC restart handler: a full reboot to ssh takes about 22 s.

**kwick-bootctl.**

```
kwick-bootctl status
kwick-bootctl default kwickos|armbian
kwick-bootctl once kwickos|armbian
kwick-bootctl set-kernel vendor | <release>
kwick-bootctl rollback
kwick-bootctl list
```

`set-kernel <release>` copies `Image.itb`, the board DTB and `initrd.img` from `/usr/lib/kwick/kernels/<release>` to `kwick/<release>/` on the eMMC ESP and writes `kwick.txt` on the SD card, which U-Boot imports before booting. `kwick-kernel-install` (the kernel packages' postinst) hands kernels that ship `Image.itb` to `kwick-bootctl`, so `apt install linux-image-kwick-k1` selects the new kernel for the next boot and the attempt counter covers it. From Armbian, a selection is undone by hand on `/boot`: `mv kwick.prv kwick.txt` (or delete `kwick.txt` for the vendor kernel) and `rm kwick-mode-armbian`.

**Kernels.**

| Kernel | Status |
| --- | --- |
| `k1mainline` flavor: kernel.org 7.3.4 (`KERNEL_VERSION`), the generic fragments plus `config/kernel/k1mainline.config`, `spacemit/k1-bananapi-f3.dtb` with a 2 MiB ramoops region at `0x50000000` | Verified, the board's default since 2026-11-16: boots on the 2024 vendor firmware (OpenSBI 1.3, U-Boot 2022.10), all 8 harts, 16 GiB. Package `linux-image-kwick-k1mainline`, release `7.3.4-kwick-k1mainline` |
| Vendor 6.1.15 (Armbian `legacy-k1`, from the SD card) | Verified: eMMC, NVMe, USB, both Ethernet ports (`eth0`/`eth1`; Armbian's udev calls them `end0`/`end1`), Wi-Fi modules load, `/dev/dri` (PowerVR BXE-2-32 kernel driver and the SpacemiT HDMI KMS driver). With the KwickOS desktop running it dropped off the network three times in a row, 8 to 15 minutes after boot, on 2026-11-15; the one logged case was a hard hang (a heartbeat log stopped at 934 s, temperatures 45 °C), and there is no watchdog to recover |
| `k1` flavor: SpacemiT BSP 6.6.63 (`gitee.com/spacemit-buildroot/linux-6.6` tag `k1-bl-v2.2.11-release`, commit `31c449ae`, `k1_defconfig` plus `config/kernel/k1.config`) | **Unsupported.** The BSP is based on 6.6.63, about 100 stable releases and many security fixes behind the 6.6 longterm branch, and SpacemiT has published nothing newer (the `k1-bl-v2.2.y` branch is still 6.6.63 as of 2026-11-22). Release builds skip it and the repository no longer gets new `linux-image-kwick-k1` packages; use `k1mainline`. It is only built when the repository variable `KWICK_BUILD_K1_VENDOR` is `true`, and `scripts/cve-check.sh` then flags it. When it was last built it produced a FIT `Image.itb` loading at `0x600000`, `k1-x_deb1.dtb` with the watchdog enabled, and an initrd with kinit and the v2.2.11 `esos.elf`; it has not been booted since the kinit `rootfstype=` fix described below |
| `generic` flavor, mainline 7.3.x | Built. Has the same K1 drivers but no FIT image, stub or board DTB handling; use `k1mainline` on the BPI-F3 |

**Hardware on mainline 7.3.4 compared with vendor 6.1.15.** Measured on a 16 GiB BPI-F3 with a 128 GB eMMC, a 256 GB SDXC card and a 1 TB NVMe SSD.

| Part | Mainline 7.3.4 (`k1mainline`) | Vendor 6.1.15 |
| --- | --- | --- |
| CPU, SMP | 8 harts through SBI HSM, cpufreq-dt 614 MHz to 1.6 GHz, 5 thermal zones | 8 harts |
| eMMC | HS400 enhanced strobe, 214 MB/s sequential read (`mmcblk0`) | works (`mmcblk2`) |
| SD card | UHS-I SDR104 (`mmcblk1`); 9.5 MB/s O_DIRECT read with 1 MiB blocks on this card | works (`mmcblk0`) |
| NVMe (PCIe port 1) | works, link trains at Gen1 x2, 314 MB/s sequential read | works |
| Second PCIe controller | root port enumerates, no link (nothing fitted) | not tested |
| USB | DWC3 host, VIA VL817 USB 3 hub and the USB 2 hub | works |
| Ethernet | both K1 EMACs (`end0`/`end1`), link at 1 Gb/s, 52 MB/s download from cdn.kernel.org | works |
| Wi-Fi, Bluetooth (on-board RTL8852BS, SDIO) | not available: the mainline BPI-F3 device tree has no SDIO controller for it | vendor driver loads |
| HDMI, GPU | no display driver, no `/dev/dri`; the desktop needs the vendor kernel | SpacemiT HDMI KMS and PowerVR kernel driver |
| Audio, camera, video codecs | no drivers | vendor drivers |
| PMIC (P1) | regulators, RTC (`rtc0`, sets the clock at boot), power-off and restart | works |
| Watchdog | no driver; fed from `init-crumb`, see above | vendor driver |
| LEDs | `sys-led` heartbeat | works |

Boot time, from kernel start: the mainline kernel mounts the root at 2.3 s and runs `init-crumb` at 2.5 s, the Ethernet link is up at 4.9 s and ssh answers by 15 s (22 s for a whole `reboot`, firmware included). The vendor kernel goes through Armbian's initrd and the `esos.elf` load and mounts the root at 7.8 s.

**The kinit `rootfstype=` bug.** Until 2026-11-16 kinit's `cmdline_get()` returned a pointer into one static buffer, so reading `rootfstype=ext4` after `root=` replaced the root spec with `ext4`. Any kernel that let the embedded kinit mount the root with `rootfstype=` on the command line (the BPI-F3 env passes it) waited `rootdelay` seconds for a device called `ext4` and rebooted. That, not the firmware, is why the mainline and 6.6 kernels did not come up earlier; the vendor 6.1 kernel was unaffected because Armbian's initrd mounts the root. Stage 0 now copies the values.

**Firmware.** The newest SpacemiT K1 bootloader release is `k1-bl-v2.2.11-release`; Armbian builds `k1-bl-v2.2.9-release` with an MBR patch. Stock vendor firmware finds OpenSBI, U-Boot and the boot partition by GPT partition name, so it does not boot an MBR card like Armbian's. Neither release adds SBI system reset, so a kernel panic on the vendor kernels only reboots when the watchdog is enabled in the device tree. Back up the first 100 MiB of the card (bootinfo, FSBL, OpenSBI at sector 1280, U-Boot at sector 2048) before writing new firmware. Mainline 7.3 does not need new firmware: the 2024 OpenSBI 1.3 provides HSM, IPI and RFENCE, enables Svpbmt, Zicbom, Zicboz and Sstc for S-mode, and U-Boot adds its reserved memory and the memory nodes to the mainline device tree.

**Graphics.** The PowerVR GPU needs SpacemiT's closed userspace driver, which Debian does not ship, so a desktop on the vendor kernels renders with Mesa's llvmpipe on the HDMI KMS output. Mainline has no K1 display driver yet, so for a local desktop switch back with `kwick-bootctl set-kernel vendor`.

U-Boot numbers the SD card `mmc 0` and the eMMC `mmc 2`; the vendor kernels name them `mmcblk0` and `mmcblk2`, mainline names the eMMC `mmcblk0` and the SD card `mmcblk1`. The root is found by `PARTLABEL=kwick-root` and `kwick-bootctl` looks for the SD boot partition by its `env_k1-x.txt`, so both work with either kernel.

## What to do when something does not work

Run `kwick-gpu` for the detected GPUs and package plan, `kwick-apple-boot status` on a Mac, and attach `dmesg` and the kernel config (`/usr/lib/kwick/kernels/<release>/config`). Hardware bring-up reports are the main way entries move from Built to Verified.
