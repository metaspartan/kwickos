# KwickOS builder: everything needed to cross-build kernels, assemble
# images and boot-test them under QEMU for amd64 / arm64 / riscv64.
FROM debian:trixie-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential bc bison flex libssl-dev libelf-dev cpio xz-utils zstd lz4 \
      gcc-aarch64-linux-gnu gcc-riscv64-linux-gnu \
      curl ca-certificates git python3 kmod rsync file jq bsdextrautils \
      xorriso isolinux syslinux-common mtools dosfstools e2fsprogs fdisk erofs-utils squashfs-tools \
      qemu-system-x86 qemu-system-arm qemu-system-misc qemu-utils \
      ovmf qemu-efi-aarch64 opensbi \
      dpkg-dev gnupg golang-go \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
