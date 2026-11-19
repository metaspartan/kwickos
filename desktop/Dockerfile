ARG BASE=kwickos:dev

FROM debian:trixie AS kwinflip
COPY --from=kwinflipsrc . /flip/src/kwin-flip
COPY --from=kwickscripts mkflippkg.sh kwin-plugin.sh /flip/scripts/
RUN bash /flip/scripts/mkflippkg.sh /flip/out

FROM debian:trixie AS kwinglass
COPY --from=kwinglasssrc . /glass/src/kwin-liquidglass
COPY --from=kwickscripts mkglasspkg.sh kwin-plugin.sh /glass/scripts/
RUN bash /glass/scripts/mkglasspkg.sh /glass/out

FROM debian:trixie AS macstyle
COPY --from=macstylesrc . /style/src/kwick-macstyle
COPY --from=kwickscripts mkmacstylepkg.sh kwin-plugin.sh /style/scripts/
RUN bash /style/scripts/mkmacstylepkg.sh /style/out

FROM ${BASE}
SHELL ["/bin/sh", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

COPY packages.list packages.amd64.list packages.arm64.list packages.riscv64.list /tmp/
RUN sed -i 's/^Components: main$/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources \
 && apt update \
 && PK="$(grep -hv '^#' /tmp/packages.list | tr '\n' ' ')"; PK="$PK $(grep -hv '^#' /tmp/packages.$(dpkg --print-architecture).list 2>/dev/null | tr '\n' ' ')"; apt install -y $PK \
 && apt clean && rm -rf /var/lib/apt/lists/* /tmp/packages*.list

COPY rootfs/ /
COPY gaming/rootfs/ /
COPY --from=kwinflip /flip/out/ /
COPY --from=kwinglass /glass/out/ /
COPY --from=macstyle /style/out/ /
RUN sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen || echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen; locale-gen && update-locale LANG=en_US.UTF-8
RUN chmod 755 /usr/lib/kwick/fetch-fonts /usr/lib/kwick/fetch-effects && /usr/lib/kwick/fetch-fonts / all && fc-cache -f && /usr/lib/kwick/fetch-effects / all && glib-compile-schemas /usr/share/glib-2.0/schemas
RUN set -e; \
    find /usr/lib/kwick /usr/bin/kwick-* /usr/bin/steam /usr/bin/steamos-session-select -type f -exec chmod 755 {} +; \
    /usr/lib/kwick/desktop-units enable; \
    kwick-shell --default zsh; \
    adduser --disabled-password --gecos "KwickOS Live" --shell /bin/zsh kwick 2>/dev/null || adduser -D -g "KwickOS Live" -s /bin/zsh kwick; \
    for g in sudo video render audio input netdev bluetooth plugdev users; do grep -q "^$g:" /etc/group && adduser kwick $g >/dev/null 2>&1 || true; done; \
    passwd -d kwick >/dev/null 2>&1 || true; \
    mkdir -p /var/lib/AccountsService/icons /var/lib/AccountsService/users; cp /usr/share/kwick/faces/kwickos.png /var/lib/AccountsService/icons/kwick; chmod 644 /var/lib/AccountsService/icons/kwick; printf '[User]\nIcon=/var/lib/AccountsService/icons/kwick\nSystemAccount=false\n' > /var/lib/AccountsService/users/kwick; chmod 600 /var/lib/AccountsService/users/kwick; \
    echo 'kwick ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/kwick-live; chmod 440 /etc/sudoers.d/kwick-live; \
    printf '[Autologin]\nUser=kwick\nSession=plasma\nRelogin=false\n' > /etc/sddm.conf.d/20-autologin.conf; \
    rm -f /etc/kinit/autologin; \
    mkdir -p /etc/xdg; printf '[Daemon]\nAutolock=false\nLockOnResume=false\n' > /etc/xdg/kscreenlockerrc; \
    echo "KwickOS Desktop $(cat /etc/kwick-release | cut -d' ' -f2)" > /etc/kwick-edition; \
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true; \
    ls -l /usr/libexec/elogind /usr/lib/systemd/systemd-udevd /usr/bin/startplasma-wayland

RUN rm -rf /usr/share/doc /usr/share/man /usr/share/info /usr/share/help /usr/share/lintian \
 && find /usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en*' ! -name 'locale.alias' -exec rm -rf {} + \
 && rm -rf /var/cache/apt /var/lib/apt/lists/*

RUN rm -f /usr/lib/*/qt6/plugins/discover/packagekit-backend.so /usr/lib/*/qt6/plugins/discover/kns-backend.so

RUN (for t in KwickOS KwickOS-Fluent KwickOS-Linux hicolor; do gtk-update-icon-cache -f -t /usr/share/icons/$t || true; done) \
 && rm -rf /usr/share/plasma/look-and-feel/org.kde.breeze.desktop /usr/share/plasma/look-and-feel/org.kde.breezedark.desktop /usr/share/plasma/look-and-feel/org.kde.breezetwilight.desktop /usr/share/plasma/look-and-feel/org.debian.desktop \
 && for l in macos windows linux; do cp /usr/share/kwick/plasma/$l.js /usr/share/plasma/look-and-feel/org.kwickos.$l/contents/layouts/org.kde.plasma.desktop-layout.js; done \
 && touch -r /usr /etc/.updated /var/.updated \
 && su -s /bin/sh kwick -c 'cd && XDG_CURRENT_DESKTOP=KDE dbus-run-session /usr/lib/kwick/session-init kde' \
 && test -e /home/kwick/.config/kwick/kde.applied

