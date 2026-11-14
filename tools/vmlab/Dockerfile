FROM debian:trixie
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      qemu-system-x86 qemu-system-modules-opengl qemu-system-gui qemu-utils ovmf \
      libvirglrenderer1 libegl1 libgl1 libgbm1 libgl1-mesa-dri libegl-mesa0 mesa-utils-bin mesa-utils xvfb x11-utils xdotool libsdl2-2.0-0 \
      python3 socat netcat-openbsd imagemagick ffmpeg gifsicle xz-utils zstd curl ca-certificates \
      openssh-client sshpass unzip git fontconfig fdisk e2fsprogs dpkg-dev gnupg apt-utils nginx-light procps iproute2 \
      xorriso isolinux syslinux-common mtools dosfstools erofs-utils kmod grub-common grub-efi-amd64-bin grub-pc-bin \
    && rm -rf /var/lib/apt/lists/*
COPY qmp.py /usr/local/bin/qmp
COPY vm.sh /usr/local/bin/vm
COPY serve-repo.sh /usr/local/bin/serve-repo
COPY buildrepo.sh /usr/local/bin/buildrepo
COPY sh.py /usr/local/bin/sh2
COPY mkdisk.sh /usr/local/bin/mkdisk
COPY mountdisk.sh /usr/local/bin/mountdisk
COPY mkgif.sh /usr/local/bin/mkgif
COPY grab.sh /usr/local/bin/grab
COPY login.sh /usr/local/bin/vmlogin
COPY asuser.sh /usr/local/share/vmlab-asuser.sh
COPY fx-wobbly.sh /usr/local/bin/fx-wobbly
COPY fx-lamp.sh /usr/local/bin/fx-lamp
COPY fx-flame.sh /usr/local/bin/fx-flame
COPY shots-layouts.sh /usr/local/bin/shots-layouts
COPY shots-tiling.sh /usr/local/bin/shots-tiling
COPY fx-cube.sh /usr/local/bin/fx-cube
COPY mkiso.sh /usr/local/bin/mkiso
RUN chmod +x /usr/local/bin/*
ENV LD_LIBRARY_PATH=/usr/lib/wsl/lib
ENV GALLIUM_DRIVER=d3d12
ENV MESA_D3D12_DEFAULT_ADAPTER_NAME=AMD
WORKDIR /work
