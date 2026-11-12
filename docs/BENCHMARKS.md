# Benchmarks

All numbers below were measured on 2026-11-12 with KwickOS 0.1.0 (Linux 7.3.4) on one
machine: Windows 11 host, Docker Desktop 29.9 on WSL2 (kernel 6.6), 32 threads, and
QEMU 10.0 with KVM inside a Debian 13 container. Comparison systems are the latest releases
on that date: **Alpine 3.24.4**, **Debian 13 (trixie-slim)**, and **Ubuntu 24.04**.

Reproduce:

```sh
bash bench/container.sh kwickos:<tag>                          # needs docker
docker run --rm --device /dev/kvm -v $PWD:/src -v $PWD/out:/out kwick-builder bash /src/bench/vm.sh 5
```

## 1. Virtual machines: boot time and memory

Method (`bench/vm.sh`): each system boots under QEMU/KVM with identical settings
(q35, 2 vCPU, 512 MiB, virtio-net) and its kernel+initramfs loaded directly by QEMU. The
script then logs in on the serial console, exactly as a user would. Live systems use their
ISO as the root medium over virtio-scsi. Measured: wall time from QEMU start to the shell prompt;
`/proc/uptime` at that prompt; `MemTotal − MemAvailable`; and the number of userspace
processes. For Alpine, the 1.5 s the script waits after typing `root` is subtracted from uptime.
Values are the median of 5 runs.

| system | QEMU start → shell prompt | guest boot time (uptime at shell) | memory in use | user processes |
|---|---:|---:|---:|---:|
| Alpine 3.24.4 `virt` (live ISO) | 3730 ms | 3.10 s | 69.7 MiB | 13 |
| **KwickOS live ISO** (erofs + overlay) | **1169 ms** | **0.75 s** | **38.3 MiB** | 6 |
| **KwickOS installed** (ext4 on virtio-blk) | **1003 ms** | **0.60 s** | **34.7 MiB** | 9 |
| **KwickOS microVM** (QEMU `microvm`, whole OS in RAM) | **472 ms** | **0.22 s** | 41.4 MiB* | 9 |

\* includes the root filesystem itself, which lives in RAM in this mode.

Like for like (live ISO vs live ISO), KwickOS reaches a shell **3.2× faster** (4.1× by
guest boot time) and uses **45% less memory**. The q35 machines spend most of their wall
time in SeaBIOS/iPXE; the `microvm` machine has no firmware or PCI, which is why it is the
recommended target for agent sandboxes.

Boot-test harness results (`tests/boot-matrix.sh`; "ready" is when kinit has started all
services, measured from kernel start):

| arch | accel | microvm | RAM (q35/virt) | disk | UEFI disk | UEFI ISO |
|---|---|---:|---:|---:|---:|---:|
| amd64 | KVM | 196 ms | 587 ms | 719 ms | 578 ms | 1362 ms (generic kernel) |
| arm64 | TCG (emulated) | – | 3.2 s | 5.7 s | 5.4 s | 5.3 s |
| riscv64 | TCG (emulated) | – | 2.6 s | 3.1 s | – | – |

A full microVM cycle (QEMU start, boot, run a command, clean poweroff) takes **0.95 s** of wall time.

## 2. Containers

`docker image inspect` size, `docker save | gzip` size (≈ registry pull size), files in
the image, and the anonymous memory plus page tables of a `sh` process (from the container's
`memory.stat`, median of 5).

| image | uncompressed | gzip (pull size) | files | `sh` memory (anon+pagetables) |
|---|---:|---:|---:|---:|
| **KwickOS 0.1.0** | **5.53 MB** | **2.60 MB** | **492** | **56 KiB** |
| Alpine 3.24.4 | 8.43 MB | 3.72 MB | 518 | 88 KiB |
| Debian 13 slim | 78.86 MB | 30.04 MB | 3274 | 324 KiB |
| Ubuntu 24.04 | 78.20 MB | 29.97 MB | 3445 | 320 KiB |

KwickOS is **34% smaller than Alpine** uncompressed, **30% smaller** compressed, and its
shell uses **~36% less memory** (static binaries: no dynamic loader and no relocations).
`docker run --rm IMAGE true` latency was 0.7–1.1 s for **every** image and varied more
between runs than between images. On Docker Desktop it is dominated by Docker itself, so we
don't claim a difference.

### Installing software

Fresh container per row. Times include `update` and downloads from the public mirrors
(network variance applies).

| image | task | wall time | rootfs after | after removing package indexes/caches |
|---|---|---:|---:|---:|
| **KwickOS** (Debian packages) | install curl | 9.8 s | 61 MB | 50 MB |
| Alpine 3.24 | install curl | 2.2 s | 14 MB | 14 MB |
| Debian 13 slim | install curl | 10.5 s | 117 MB | 97 MB |
| Ubuntu 24.04 | install curl | 17.5 s | 143 MB | 90 MB |
| **KwickOS** (Debian packages) | install python3 | 16.7 s | 98 MB | 87 MB |
| Alpine 3.24 | install python3 | 4.8 s | 52 MB | 52 MB |
| Debian 13 slim | install python3 | 17.9 s | 141 MB | 120 MB |
| Ubuntu 24.04 | install python3 | 26.7 s | 178 MB | 125 MB |

Reading this honestly:

* With the same Debian packages, KwickOS ends up **~45–50% smaller than Debian slim**
  (50 vs 97 MB with curl, 87 vs 120 MB with python3) and installs as fast or faster.
* Alpine remains smaller and faster *for the same software* because its packages are
  built differently: Alpine's curl has far fewer optional features, while Debian's curl
  links GnuTLS, Kerberos, LDAP and RTMP libraries. That is the price of binary compatibility
  with Debian's ~69,000 packages. KwickOS's *base* is the smallest, and what you add costs
  what Debian's packages cost.
* kpkg decompresses packages in parallel. On this machine that cut a python3 install
  from 25 s to 8 s (excluding `apt update`).

## 3. Artifact sizes (amd64)

| artifact | KwickOS | Alpine 3.24.4 equivalent |
|---|---:|---:|
| rootfs tarball (gzip) | 2.6 MB | 3.7 MB (minirootfs) |
| live ISO | 23.6 MB (generic kernel + modules) | 70.3 MB (`virt` ISO) |
| VM disk (qcow2, compressed) | 10.0 MB | – |
| kernel (`virt`, EFI app incl. kinit) | 6.8 MB | – |
| whole OS as initramfs | 2.2 MB | – |

arm64: EFI kernel 5.0 MB, ISO 9.5 MB, qcow2 8.1 MB. riscv64: EFI kernel 4.7 MB, ISO 9.1 MB,
qcow2 7.9 MB. (Those ISOs use the `virt` kernel; release CI builds `generic` ISOs.)
