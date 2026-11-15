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

| Generation | Kernel | GPU | Status |
| --- | --- | --- | --- |
| M1, M1 Pro, M1 Max, M1 Ultra | Asahi tree | `asahi` DRM driver with Mesa asahi (OpenGL) and honeykrisp (Vulkan) from trixie-backports | Built |
| M2, M2 Pro, M2 Max, M2 Ultra | Asahi tree | same | Built |
| M3 family | boots in the Asahi tree, work in progress (daily use is not yet realistic per Asahi) | not supported | Unsupported for now; device trees are present, nothing else is promised |
| M4 and M5 | device trees only reached the mailing list | none | Unsupported |
| Intel Macs (T2 or not) | not an Apple Silicon target | | Unsupported by this variant; the generic amd64 kernel may boot, T2 hardware needs out-of-tree drivers |

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
| Raspberry Pi 4 and 5 | Unsupported: no board firmware or device tree handling is shipped and nothing was tried. A UEFI firmware for the Pi (edk2) might let the generic flavor boot, untested |
| Other Arm boards with device trees (Rockchip, Allwinner, Amlogic, i.MX) | Unsupported |
| Apple Silicon virtualization (UTM, Lima, Parallels) | Verified with the arm64 virt images |

## riscv64

| Hardware | Status |
| --- | --- |
| QEMU virt with OpenSBI and UEFI | Verified (boot test in CI) |
| Banana Pi BPI-F3 (SpacemiT K1) | Verified on the vendor 6.1.15 kernel (eMMC install, both Ethernet ports, ssh, apt). The `k1` flavor (SpacemiT BSP 6.6.63) is built and packaged as `linux-image-kwick-k1`; the mainline `generic` flavor is built but does not boot with the board's 2024 vendor firmware yet. See below |
| Other SpacemiT K1 boards (Milk-V Jupiter, Muse Pi Pro, Orange Pi RV2) | Upstream: same kernel and mainline device trees, not tried |
| VisionFive 2, Milk-V, HiFive boards | Unsupported: no board device trees or vendor firmware handling; the generic flavor is built only in release CI |

### Banana Pi BPI-F3

The board keeps its vendor boot chain (BootROM, FSBL, OpenSBI 1.3 and U-Boot 2022.10 from SpacemiT, on the SD card of an Armbian image). The BootROM tries the SD card first, then the medium the boot DIP switch selects (eMMC, SPI NOR or SPI NAND). KwickOS does not replace the bootloader. It lives on the eMMC user area: a GPT disk with a 512 MiB vfat ESP (`KWICKESP`) and an ext4 `kwick-root` partition. Armbian stays on the SD card as the fallback system.

**What boots today.** The SD card's U-Boot imports `/boot/env_k1-x.txt` from the SD card's FAT partition. KwickOS adds a few `kwick_*` variables to that file (the original is kept as `env_k1-x.txt.armbian`). By default U-Boot boots the vendor 6.1.15 kernel, initrd and `k1-x_deb1.dtb` from the SD card with `root=/dev/mmcblk2p2 init=/usr/lib/kwick/init-crumb`, exactly the way Armbian boots except for the root. The vendor kernel needs an initrd: its power-management co-processor loads `esos.elf` at about 4 s, before the root filesystem exists, and without it the boot stalls.

**Fallback.** Before every KwickOS boot U-Boot writes `kwick-attempt` to the SD card's FAT partition. `kwick-boot-ok.service` deletes it once the system has had an IPv4 address for 60 s. If U-Boot finds `kwick-attempt` at the next boot, the previous boot failed: it deletes the file, creates `kwick-mode-armbian` and boots Armbian. A bad kernel therefore costs one power cycle and lands on Armbian, and stays there until switched back. `init-crumb` logs to `/var/log/kinit-start`, starts the SoC watchdog when the device tree enables it, and reboots after 120 s without an IPv4 address (logs in `/var/log/boot-dmesg-safety`).

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
| Vendor 6.1.15 (Armbian `legacy-k1`, from the SD card) | Verified: eMMC, NVMe, USB, both Ethernet ports (`eth0`/`eth1`; Armbian's udev calls them `end0`/`end1`), Wi-Fi modules load, `/dev/dri` (PowerVR BXE-2-32 kernel driver and the SpacemiT HDMI KMS driver) |
| `k1` flavor: SpacemiT BSP 6.6.63 (`gitee.com/spacemit-buildroot/linux-6.6` tag `k1-bl-v2.2.11-release`, commit `31c449ae`, `k1_defconfig` plus `config/kernel/k1.config`) | Built and packaged (`linux-image-kwick-k1`): FIT `Image.itb` loading at `0x600000`, `k1-x_deb1.dtb` with the watchdog enabled, and an initrd with kinit and the v2.2.11 `esos.elf`. Its device tree expects the v2.2.x firmware memory layout; not yet booted on the 2024 firmware |
| `generic` flavor, mainline 7.3.x | Built; does not come up on the 2024 vendor firmware |

**Firmware.** The newest SpacemiT K1 bootloader release is `k1-bl-v2.2.11-release`; Armbian builds `k1-bl-v2.2.9-release` with an MBR patch. Stock vendor firmware finds OpenSBI, U-Boot and the boot partition by GPT partition name, so it does not boot an MBR card like Armbian's. Neither release adds SBI system reset, so a kernel panic on the vendor kernels only reboots when the watchdog is enabled in the device tree. Back up the first 100 MiB of the card (bootinfo, FSBL, OpenSBI at sector 1280, U-Boot at sector 2048) before writing new firmware.

**Graphics.** The PowerVR GPU needs SpacemiT's closed userspace driver, which Debian does not ship, so a desktop on the vendor kernels renders with Mesa's llvmpipe on the HDMI KMS output.

U-Boot numbers the SD card `mmc 0` and the eMMC `mmc 2`; the vendor kernels name them `mmcblk0` and `mmcblk2`.

## What to do when something does not work

Run `kwick-gpu` for the detected GPUs and package plan, `kwick-apple-boot status` on a Mac, and attach `dmesg` and the kernel config (`/usr/lib/kwick/kernels/<release>/config`). Hardware bring-up reports are the main way entries move from Built to Verified.
