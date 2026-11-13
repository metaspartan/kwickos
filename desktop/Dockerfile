# KwickOS Desktop root filesystem, built on top of the KwickOS base image.
#   docker build --build-arg BASE=kwickos:<ver>-amd64 -t kwickos-desktop desktop/
# The result is exported (docker export) and turned into a live ISO by
# scripts/mkdesktop-iso.sh.
ARG BASE=kwickos:dev
FROM ${BASE}
SHELL ["/bin/sh", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

COPY packages.list packages.amd64.list /tmp/
RUN sed -i 's/^Components: main$/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources \
 && apt update \
 && PK="$(grep -hv '^#' /tmp/packages.list | tr '\n' ' ')"; [ "$(dpkg --print-architecture)" = amd64 ] && PK="$PK $(grep -hv '^#' /tmp/packages.amd64.list | tr '\n' ' ')"; apt install -y $PK \
 && apt clean && rm -rf /var/lib/apt/lists/* /tmp/packages*.list

# Burn-My-Windows: compiz-style open/close effects for KWin 6 (fire, TV,
# hexagon, pixelate, wisps, doom, energize, ...). Wobbly windows and magic
# lamp are KWin built-ins. All are toggled in System Settings > Desktop Effects.
ARG BMW_VERSION=v49
RUN mkdir -p /usr/share/kwin/effects /tmp/bmw && cd /tmp/bmw \
 && curl -fsSL -o bmw.tgz https://github.com/Schneegans/Burn-My-Windows/releases/download/${BMW_VERSION}/burn_my_windows_kwin6.tar.gz \
 && tar xzf bmw.tgz && cp -r $(find . -mindepth 1 -maxdepth 2 -type d -name 'kwin6_effect_*' -o -mindepth 1 -maxdepth 2 -type d -name 'burn_my_windows_*' | grep -v '\.tgz') /usr/share/kwin/effects/ 2>/dev/null || true; \
    rm -rf /tmp/bmw; ls /usr/share/kwin/effects | head -30

COPY rootfs/ /
RUN set -e; \
    find /usr/lib/kwick /usr/bin/kwick-gaming /usr/bin/kwick-desktop /usr/bin/kwick-fonts /usr/bin/kwick-layout /usr/bin/kwick-effects /usr/bin/steam -type f -exec chmod 755 {} +; \
    rm -f /etc/systemd/system/multi-user.target.wants/networking.service; \
    W=/etc/systemd/system/multi-user.target.wants; mkdir -p $W; \
    for u in dbus kwick-elogind systemd-udevd kwick-udev-trigger kwick-session-report NetworkManager bluetooth polkit sddm upower udisks2 power-profiles-daemon rtkit-daemon; do \
      f=$(ls /usr/lib/systemd/system/$u.service 2>/dev/null || true); \
      if [ -n "$f" ]; then ln -sf $f $W/$u.service; else echo "note: no unit $u"; fi; \
    done; \
    # live user with passwordless sudo, autologin into Plasma (Wayland)
    adduser --disabled-password --gecos "KwickOS Live" kwick 2>/dev/null || adduser -D -g "KwickOS Live" kwick; \
    for g in sudo video render audio input netdev bluetooth plugdev users; do grep -q "^$g:" /etc/group && adduser kwick $g >/dev/null 2>&1 || true; done; \
    passwd -d kwick >/dev/null 2>&1 || true; \
    echo 'kwick ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/kwick-live; chmod 440 /etc/sudoers.d/kwick-live; \
    printf '[Autologin]\nUser=kwick\nSession=plasma\nRelogin=false\n' > /etc/sddm.conf.d/20-autologin.conf; \
    rm -f /etc/kinit/autologin; \
    echo "KwickOS Desktop $(cat /etc/kwick-release | cut -d' ' -f2)" > /etc/kwick-edition; \
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true; \
    ls -l /usr/libexec/elogind /usr/lib/systemd/systemd-udevd /usr/bin/startplasma-wayland

# wait-for-dbus drop-ins: kinit starts services in parallel, these register
# D-Bus names and must not race dbus-daemon.
RUN for u in NetworkManager bluetooth upower rtkit-daemon polkit udisks2 power-profiles-daemon; do \
      mkdir -p /etc/systemd/system/$u.service.d; \
      printf '[Service]\nExecStartPre=/usr/lib/kwick/wait-for dbus\nRestart=on-failure\n' > /etc/systemd/system/$u.service.d/kwick.conf; \
    done

# Trim: docs, man pages and non-English translations (keeps the live ISO under
# the 2 GiB GitHub release-asset limit; `apt install` can bring them back).
RUN rm -rf /usr/share/doc /usr/share/man /usr/share/info /usr/share/help /usr/share/lintian \
 && find /usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en*' ! -name 'locale.alias' -exec rm -rf {} + \
 && rm -rf /var/cache/apt /var/lib/apt/lists/*

# Discover: KwickOS has no PackageKit (kpkg is the package manager); keep only the Flatpak backend
RUN rm -f /usr/lib/*/qt6/plugins/discover/packagekit-backend.so /usr/lib/*/qt6/plugins/discover/kns-backend.so

