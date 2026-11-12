# Debian package compatibility

Each package is installed with `apt install -y PKG` on a fresh KwickOS 0.1.0 container (amd64) from the
unmodified Debian 13 archive, followed by a smoke test (`tests/compat.sh`). Measured 2026-11-12.
GNU tools that maintainer scripts needed were installed automatically by kpkg's
self-healing step (for example procps and findutils for MariaDB, and coreutils for locales/PostgreSQL).

**Result: 31/31 pass.** Reproduce with `bash tests/compat.sh kwickos:<tag>`.

| package | result | time | rootfs after | smoke output |
|---|---|---|---|---|
| apache2 | PASS | 34s | 151 MB | 	-f	Hide errors |
| bash | PASS | 29s | 41 MB | bash 5.2.37(1)-release v |
| build-essential | PASS | 70s | 383 MB | gcc ok |
| ca-certificates | PASS | 31s | 58 MB | certs ok |
| coreutils | PASS | 35s | 65 MB | ls (GNU coreutils) 9.7 |
| cron | PASS | 39s | 61 MB | cron ok |
| curl | PASS | 27s | 61 MB | curl 8.14.1 (x86_64-pc-linux-gnu) libcurl/8.14.1 OpenSSL/3.5 |
| docker.io | PASS | 66s | 283 MB | Docker version 26.1.5+dfsg1, build 411e817 |
| git | PASS | 36s | 178 MB | git version 2.47.3 |
| golang-go | PASS | 61s | 302 MB | go version go1.24.4 linux/amd64 |
| htop | PASS | 32s | 34 MB | htop 3.4.1 |
| iproute2 | PASS | 35s | 65 MB | ip utility, iproute2-6.15.0, libbpf 1.5.0 |
| jq | PASS | 26s | 34 MB | 1 |
| mariadb-server | PASS | 74s | 497 MB | mariadbd  Ver 11.8.6-MariaDB-0+deb13u1 from Debian for debia |
| nginx | PASS | 24s | 56 MB | nginx: configuration file /etc/nginx/nginx.conf test is succ |
| nodejs | PASS | 49s | 147 MB | node v20.19.2 |
| openjdk-21-jre-headless | PASS | 76s | 264 MB | openjdk version "21.0.13" 2026-10-20 |
| openssh-server | PASS | 19s | 104 MB | `systemctl start ssh`: active, /run/sshd created (RuntimeDirectory=) |
| php-cli | PASS | 43s | 81 MB | php 8.4.27 |
| postgresql | PASS | 98s | 487 MB | 17  main    5432 down   postgres /var/lib/postgresql/17/main |
| python3 | PASS | 34s | 98 MB | py 3.13.5 |
| python3-pip | PASS | 42s | 121 MB | pip 25.1.1 from /usr/lib/python3/dist-packages/pip (python 3 |
| redis-server | PASS | 25s | 79 MB | Redis server v=8.0.2 sha=00000000:0 malloc=jemalloc-5.3.0 bi |
| rsync | PASS | 29s | 44 MB | rsync  version 3.5.0  protocol version 32 |
| rsyslog | PASS | 36s | 38 MB | rsyslogd  8.2504.0 (aka 2025.04) compiled with: |
| ruby | PASS | 48s | 98 MB | ruby 3.3.13 |
| sudo | PASS | 29s | 67 MB | Sudo version 1.9.16p2 |
| supervisor | PASS | 53s | 106 MB | 4.2.5 |
| tzdata | PASS | 25s | 47 MB | lrwxrwxrwx    1 root     root            27 Nov 12 11:14 /et |
| vim | PASS | 38s | 93 MB | VIM - Vi IMproved 9.1 (2024 Jan 02, compiled Nov 04 2026 22: |
| wget | PASS | 26s | 48 MB | GNU Wget 1.25.0 built on linux-gnu. |
