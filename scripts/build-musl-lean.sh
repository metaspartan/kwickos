#!/bin/bash
set -euo pipefail
ARCH=${1:?arch}
SRC=${SRC:-/src}; OUT=${OUT:-/out}; CACHE=${CACHE:-/cache}
W=${W:-/build/musl-lean-$ARCH}
JOBS=${JOBS:-4}
PKGS=${PKGS:-ca-bundle musl curl git nginx openssh python}
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-1767225600}
export LC_ALL=C TZ=UTC
case $ARCH in
  amd64) MA=x86_64; OSSL=linux-x86_64 ;;
  arm64) MA=aarch64; OSSL=linux-aarch64 ;;
  riscv64) MA=riscv64; OSSL=linux64-riscv64 ;;
  *) echo "unknown arch $ARCH" >&2; exit 1 ;;
esac
SOURCES="$SRC/config/musl-lean/sources"
POOL="$OUT/repo/pool/main"
P="$W/prefix"
STAGE="$W/stage"
LR="$W/libressl"
MUSL_LD=/usr/lib/kwick/musl/ld-musl-$MA.so.1
mkdir -p "$W/src" "$P/lib" "$P/include" "$STAGE" "$POOL" "$CACHE/musl-lean" "$(dirname "$MUSL_LD")"
ln -sf "/lib/ld-musl-$MA.so.1" "$MUSL_LD"

apk add --no-cache build-base linux-headers perl bash coreutils findutils grep cmake pkgconf autoconf automake libtool dpkg tar xz bzip2 >/dev/null

clash=$(gcc -fstack-clash-protection -x c -c -o /dev/null /dev/null 2>/dev/null && echo -fstack-clash-protection || true)
HARD="-fstack-protector-strong $clash -D_FORTIFY_SOURCE=2"
export CFLAGS="-Os -pipe -fPIC $HARD -ffunction-sections -fdata-sections -ffile-prefix-map=$W=."
export CXXFLAGS="$CFLAGS"
export CPPFLAGS="-I$P/include"
export LDFLAGS="-L$P/lib -Wl,--gc-sections -Wl,-z,relro,-z,now"
export PKG_CONFIG_PATH="$P/lib/pkgconfig" PKG_CONFIG="pkg-config --static"
STATIC_LD="$LDFLAGS -static-pie"
LTO="-flto=auto -fno-builtin-fprintf -fno-builtin-fputs"
FLAGS_ID=$(printf %s "$CFLAGS $LDFLAGS" | sha256sum | cut -c1-8)

pin() { awk -v n="$1" '$1==n {print $'"$2"'}' "$SOURCES"; }
ver() { pin "$1" 2; }
fetch() {
  local sum url f
  sum=$(pin "$1" 3); url=$(pin "$1" 4)
  [ -n "$sum" ] || { echo "$1: not pinned in $SOURCES" >&2; exit 1; }
  f="$CACHE/musl-lean/${url##*/}"
  local v="$SRC/config/musl-lean/patches/${url##*/}"
  if [ -f "$v" ] && printf '%s  %s\n' "$sum" "$v" | sha256sum -c - >/dev/null 2>&1; then
    FILE=$v
    return
  fi
  if ! printf '%s  %s\n' "$sum" "$f" | sha256sum -c - >/dev/null 2>&1; then
    rm -f "$f"
    local n=0
    until { if command -v curl >/dev/null 2>&1; then curl -fsSL --retry 3 --retry-delay 5 -A "kwickos-build/1.0" -o "$f.part" "$url"; else wget -q -O "$f.part" "$url"; fi; }; do
      n=$((n + 1))
      [ $n -lt 6 ] || { rm -f "$f.part"; echo "$1: download failed: $url" >&2; exit 1; }
      sleep $((n * 20))
    done
    printf '%s  %s\n' "$sum" "$f.part" | sha256sum -c - >/dev/null || { rm -f "$f.part"; echo "$1: checksum mismatch for $url" >&2; exit 1; }
    mv "$f.part" "$f"
  fi
  FILE=$f
}
unpack() {
  fetch "$1"
  rm -rf "$W/src/$1"; mkdir -p "$W/src/$1"
  tar -xf "$FILE" -C "$W/src/$1" --strip-components=1
  cd "$W/src/$1"
}
log() { local n=$1; shift; "$@" >"$W/$n.log" 2>&1 || { tail -60 "$W/$n.log"; echo "!! $n failed" >&2; exit 1; }; }
key() {
  case $1 in
    openssl) echo "$(ver openssl)+$(awk '$1 ~ /^openssl\+/ {print $3}' "$SOURCES" | sha256sum | cut -c1-12)" ;;
    curl) echo "$(ver curl)-$(ver mbedtls)-$(ver nghttp2)-$(ver zlib)" ;;
    git) echo "$(ver git)-multi-$(key curl)-$(ver pcre2)-$(ver expat)" ;;
    nginx) echo "$(ver nginx)-$(ver libressl)-$(ver pcre2)-$(ver zlib)" ;;
    openssh) echo "$(ver openssh)-lto-$(ver libressl)-$(ver zlib)" ;;
    python) echo "$(ver python)-stack1m-$(key openssl)-$(ver sqlite)-$(ver libffi)-$(ver xz)-$(ver ncurses)-$(ver readline)" ;;
    *) ver "$1" ;;
  esac
}
built() { [ -f "$W/stamp-$1-$(key "$1")-$FLAGS_ID" ]; }
done_() { touch "$W/stamp-$1-$(key "$1")-$FLAGS_ID"; }

dep_zlib() {
  built zlib && return; unpack zlib
  log zlib sh -c "./configure --static --prefix='$P' && make -j$JOBS libz.a && make install"
  done_ zlib
}
dep_bzip2() {
  built bzip2 && return; unpack bzip2
  log bzip2 make -j"$JOBS" libbz2.a CFLAGS="$CFLAGS -D_FILE_OFFSET_BITS=64"
  cp libbz2.a "$P/lib/"; cp bzlib.h "$P/include/"
  done_ bzip2
}
dep_xz() {
  built xz && return; unpack xz
  log xz sh -c "./configure --prefix='$P' --disable-shared --enable-static --disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo --disable-lzma-links --disable-scripts --disable-doc --disable-nls && make -j$JOBS && make install"
  done_ xz
}
dep_libffi() {
  built libffi && return; unpack libffi
  log libffi sh -c "./configure --prefix='$P' --disable-shared --enable-static --disable-docs --disable-multi-os-directory && make -j$JOBS && make install"
  done_ libffi
}
dep_sqlite() {
  built sqlite && return; unpack sqlite
  log sqlite sh -c "CFLAGS='$CFLAGS -DSQLITE_ENABLE_FTS4 -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_ENABLE_DBSTAT_VTAB -DSQLITE_SECURE_DELETE -DSQLITE_ENABLE_MATH_FUNCTIONS -DSQLITE_ENABLE_UNLOCK_NOTIFY' ./configure --prefix='$P' --disable-shared --disable-readline && make -j$JOBS libsqlite3.a && make install"
  rm -f "$P"/lib/libsqlite3.so*
  done_ sqlite
}
dep_ncurses() {
  built ncurses && return; unpack ncurses
  log ncurses sh -c "./configure --prefix='$P' --without-shared --with-normal --enable-widec --without-cxx --without-cxx-binding --without-ada --without-progs --without-tests --without-manpages --without-debug --enable-pc-files --with-pkg-config-libdir='$P/lib/pkgconfig' --disable-db-install --with-terminfo-dirs=/etc/terminfo:/usr/share/terminfo:/lib/terminfo --with-default-terminfo-dir=/usr/share/terminfo && make -j$JOBS && make install"
  done_ ncurses
}
dep_readline() {
  built readline && return; unpack readline
  log readline sh -c "./configure --prefix='$P' --disable-shared --enable-static --with-curses --disable-install-examples && make -j$JOBS && make install"
  done_ readline
}
dep_openssl() {
  built openssl && return; unpack openssl
  local n
  for n in $(awk '$1 ~ /^openssl\+/ {print $1}' "$SOURCES"); do
    fetch "$n"
    patch -p1 -s < "$FILE" || { echo "openssl: $n does not apply" >&2; exit 1; }
  done
  log openssl sh -c "./Configure $OSSL --prefix='$P' --libdir=lib --openssldir=/etc/ssl no-shared no-module no-docs no-tests no-apps no-legacy no-engine no-comp no-ssl3 no-srp no-idea no-mdc2 no-rc5 no-seed no-whirlpool no-sm2 no-sm3 no-sm4 $CFLAGS && make -j$JOBS build_libs && make install_dev"
  done_ openssl
}
dep_libressl() {
  built libressl && return; unpack libressl
  rm -rf "$LR"
  log libressl sh -c "./configure --prefix='$LR' --libdir='$LR/lib' --disable-tests --enable-shared --enable-static --with-openssldir=/etc/ssl && make -j$JOBS -C crypto install && make -j$JOBS -C ssl install && make -C include install"
  done_ libressl
}
dep_pcre2() {
  built pcre2 && return; unpack pcre2
  log pcre2 sh -c "./configure --prefix='$P' --disable-shared --enable-static --enable-jit --disable-pcre2grep-libz --disable-pcre2grep-libbz2 && make -j$JOBS libpcre2-8.la && make install-libLTLIBRARIES install-includeHEADERS install-nodist_includeHEADERS install-pkgconfigDATA"
  done_ pcre2
}
dep_expat() {
  built expat && return; unpack expat
  log expat sh -c "./configure --prefix='$P' --disable-shared --enable-static --without-docbook --without-examples --without-tests --without-xmlwf && make -j$JOBS && make install"
  done_ expat
}
dep_mbedtls() {
  built mbedtls && return; unpack mbedtls
  local c
  c=$(grep -rl '^//#define MBEDTLS_THREADING_PTHREAD$' --include='*config.h' include tf-psa-crypto/include 2>/dev/null | head -1)
  [ -n "$c" ] || { echo "mbedtls: threading switch not found" >&2; exit 1; }
  sed -i -e 's|^//#define MBEDTLS_THREADING_C$|#define MBEDTLS_THREADING_C|' -e 's|^//#define MBEDTLS_THREADING_PTHREAD$|#define MBEDTLS_THREADING_PTHREAD|' "$c"
  rm -rf "$P/include/mbedtls" "$P/include/psa" "$P/include/tf-psa-crypto" "$P"/lib/libmbed* "$P"/lib/libtfpsacrypto* "$P/lib/cmake/MbedTLS" "$P/lib/cmake/TF-PSA-Crypto"
  log mbedtls sh -c "cmake -S . -B build -DCMAKE_BUILD_TYPE=None -DCMAKE_C_FLAGS='$CFLAGS' -DCMAKE_INSTALL_PREFIX='$P' -DCMAKE_INSTALL_LIBDIR=lib \
    -DENABLE_PROGRAMS=OFF -DENABLE_TESTING=OFF -DGEN_FILES=OFF -DUSE_STATIC_MBEDTLS_LIBRARY=ON -DUSE_SHARED_MBEDTLS_LIBRARY=OFF \
    -DUSE_STATIC_TF_PSA_CRYPTO_LIBRARY=ON -DUSE_SHARED_TF_PSA_CRYPTO_LIBRARY=OFF && cmake --build build -j$JOBS && cmake --install build"
  done_ mbedtls
}
dep_nghttp2() {
  built nghttp2 && return; unpack nghttp2
  log nghttp2 sh -c "./configure --prefix='$P' --enable-lib-only --disable-shared --enable-static && make -j$JOBS && make install"
  done_ nghttp2
}
dep_curl() {
  dep_zlib; dep_mbedtls; dep_nghttp2
  built curl && return; unpack curl
  log curl-configure ./configure --prefix=/usr --disable-shared --enable-static \
    --with-mbedtls="$P" --with-nghttp2="$P" --with-zlib="$P" \
    --without-libpsl --without-libidn2 --without-brotli --without-zstd --without-libssh2 --without-libssh --without-librtmp \
    --without-gssapi --disable-ldap --disable-ldaps --disable-docs \
    --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt --with-ca-path=/etc/ssl/certs \
    --enable-ipv6 --enable-threaded-resolver --enable-unix-sockets LDFLAGS="$STATIC_LD"
  log curl make -j"$JOBS"
  cp lib/.libs/libcurl.a "$P/lib/"
  rm -rf "$P/include/curl"; cp -r include/curl "$P/include/"
  done_ curl
}

pkg_dir() { rm -rf "$STAGE/$1"; mkdir -p "$STAGE/$1/DEBIAN"; D="$STAGE/$1"; }
strip_all() { find "$1" -type f -perm -u+x -exec strip --strip-all {} + 2>/dev/null || true; }
control() {
  local name=$1 version=$2 arch=$3 desc=$4; shift 4
  local isz
  isz=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
  {
    echo "Package: $name"
    echo "Version: $version"
    echo "Architecture: $arch"
    echo "Maintainer: KwickOS Developers <dev@kwickos.org>"
    echo "Installed-Size: $isz"
    echo "Section: kwick"
    echo "Priority: optional"
    echo "Homepage: https://github.com/metaspartan/kwickos"
    for f in "$@"; do echo "$f"; done
    printf 'Description: %s\n' "$desc"
  } > "$D/DEBIAN/control"
  rm -f "$D/DEBIAN/conffiles"
  if [ -d "$D/etc" ]; then
    find "$D/etc" -type f | sed "s|^$D||" | sort > "$D/DEBIAN/conffiles"
    [ -s "$D/DEBIAN/conffiles" ] || rm -f "$D/DEBIAN/conffiles"
  fi
}
build_deb() {
  find "$D" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
  chmod 0755 "$D/DEBIAN"; for s in postinst prerm postrm preinst; do [ -f "$D/DEBIAN/$s" ] && chmod 0755 "$D/DEBIAN/$s"; done
  local name version arch
  name=$(sed -n 's/^Package: //p' "$D/DEBIAN/control"); version=$(sed -n 's/^Version: //p' "$D/DEBIAN/control"); arch=$(sed -n 's/^Architecture: //p' "$D/DEBIAN/control")
  dpkg-deb --root-owner-group -Zxz -z9 -b "$D" "$POOL/${name}_${version#*:}_${arch}.deb" >/dev/null
  echo ">> ${name}_${version#*:}_${arch}.deb $(stat -c %s "$POOL/${name}_${version#*:}_${arch}.deb") bytes, $(sed -n 's/^Installed-Size: //p' "$D/DEBIAN/control") KiB installed"
}

do_ca_bundle() {
  fetch cacert
  local v; v=$(ver cacert)
  pkg_dir kwick-ca-bundle
  install -Dm0644 "$FILE" "$D/usr/share/kwick/ca-bundle.crt"
  cat > "$D/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
mkdir -p /etc/ssl/certs
[ -e /etc/ssl/certs/ca-certificates.crt ] || [ -L /etc/ssl/certs/ca-certificates.crt ] || ln -s /usr/share/kwick/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt
[ -e /etc/ssl/cert.pem ] || [ -L /etc/ssl/cert.pem ] || ln -s certs/ca-certificates.crt /etc/ssl/cert.pem
EOF
  cat > "$D/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = remove ] || [ "$1" = purge ]; then
  [ "$(readlink /etc/ssl/certs/ca-certificates.crt 2>/dev/null)" = /usr/share/kwick/ca-bundle.crt ] && rm -f /etc/ssl/certs/ca-certificates.crt
  [ "$(readlink /etc/ssl/cert.pem 2>/dev/null)" = certs/ca-certificates.crt ] && [ ! -e /etc/ssl/certs/ca-certificates.crt ] && rm -f /etc/ssl/cert.pem
fi
exit 0
EOF
  control kwick-ca-bundle "${v//-/.}-1" all "Mozilla CA certificate bundle for KwickOS lean builds"
  printf ' %s\n' "The Mozilla root store as published by the curl project (cacert-$v.pem), used by" \
    "the lean musl builds of curl, git and Python. If /etc/ssl/certs/ca-certificates.crt" \
    "does not exist yet it is linked to this bundle; Debian's ca-certificates replaces it." >> "$D/DEBIAN/control"
  build_deb
}

do_musl() {
  local v
  v=$(apk list -I musl 2>/dev/null | awk '$1 ~ /^musl-[0-9]/ {print substr($1, 6)}')
  pkg_dir kwick-musl
  install -Dm0755 "/lib/ld-musl-$MA.so.1" "$D$MUSL_LD"
  control kwick-musl "${v%-r*}+alpine$(cut -d. -f1,2 /etc/alpine-release)r${v##*-r}-1" "$ARCH" "musl C library runtime for KwickOS lean builds"
  printf ' %s\n' "The musl libc and dynamic linker from the Alpine builder at a private path" \
    "($MUSL_LD), used by the lean Python build. Alpine's musl installed with apk is separate." >> "$D/DEBIAN/control"
  build_deb
}

do_curl() {
  dep_curl
  local v; v=$(ver curl)
  pkg_dir kwick-curl
  install -Dm0755 "$W/src/curl/src/curl" "$D/usr/bin/curl"
  strip_all "$D"
  install -Dm0644 "$W/src/curl/COPYING" "$D/usr/share/doc/kwick-curl/copyright"
  control kwick-curl "$v-0kwick1" "$ARCH" "command line tool for transferring data with URL syntax (lean musl build)" \
    "Depends: kwick-ca-bundle" "Provides: curl (= $v-0kwick1)" "Conflicts: curl" "Replaces: curl" "X-Kwick-Lean: curl" \
    "X-Kwick-Upstream: curl $v, mbedTLS $(ver mbedtls), nghttp2 $(ver nghttp2), zlib $(ver zlib)"
  printf ' %s\n' "curl $v linked statically against musl, mbedTLS $(ver mbedtls) (TLS 1.2 and 1.3," \
    "certificate verification against /etc/ssl/certs), nghttp2 (HTTP/2) and zlib." \
    "No IDN, PSL, brotli, zstd, LDAP, RTMP, SSH or GSSAPI. Debian's full build: apt install --no-lean curl" >> "$D/DEBIAN/control"
  build_deb
}

do_git() {
  dep_curl; dep_pcre2; dep_expat
  local v; v=$(ver git)
  if ! built git; then
    unpack git
    local curllibs="-lcurl -lnghttp2 -lmbedtls -lmbedx509 -lmbedcrypto -lz"
    GITMAKE=(prefix=/usr gitexecdir=/usr/lib/git-core sysconfdir=/etc CC=gcc "CFLAGS=$CFLAGS $CPPFLAGS" "LDFLAGS=$STATIC_LD"
      NO_PERL=1 NO_TCLTK=1 NO_GETTEXT=1 NO_PYTHON=1 NO_RUST=1 NO_OPENSSL=1 NO_REGEX=YesPlease NO_INSTALL_HARDLINKS=1 INSTALL_SYMLINKS=1
      USE_LIBPCRE2=1 "LIBPCRE2DIR=$P" "CURLDIR=$P" "CURL_LDFLAGS=$curllibs"
      "EXPATDIR=$P" "ZLIB_PATH=$P" NO_SVN_TESTS=1 V=1)
    log git make -j"$JOBS" "${GITMAKE[@]}" all
    for o in remote-curl http-fetch http-push; do objcopy --redefine-sym "cmd_main=kwick_${o//-/_}_main" "$o.o" "kwick-$o.o"; done
    cat > kwick-http-multi.c <<'EOF'
#include <string.h>
int kwick_remote_curl_main(int argc, const char **argv);
int kwick_http_fetch_main(int argc, const char **argv);
int kwick_http_push_main(int argc, const char **argv);
int cmd_main(int argc, const char **argv)
{
	const char *n = strrchr(argv[0], '/');
	n = n ? n + 1 : argv[0];
	if (!strcmp(n, "git-http-fetch"))
		return kwick_http_fetch_main(argc, argv);
	if (!strcmp(n, "git-http-push"))
		return kwick_http_push_main(argc, argv);
	return kwick_remote_curl_main(argc, argv);
}
EOF
    log git-http-multi sh -c "gcc $CFLAGS -c kwick-http-multi.c -o kwick-http-multi.o && gcc $CFLAGS -o git-http-multi $STATIC_LD kwick-http-multi.o kwick-remote-curl.o kwick-http-fetch.o kwick-http-push.o http.o http-walker.o common-main.o -L$P/lib $curllibs -lexpat libgit.a -lpcre2-8 -lz -lpthread"
    rm -rf "$W/git-root"
    log git-install make "${GITMAKE[@]}" DESTDIR="$W/git-root" install
    install -m0755 git-http-multi "$W/git-root/usr/lib/git-core/git-remote-http"
    ln -sf git-remote-http "$W/git-root/usr/lib/git-core/git-http-fetch"
    ln -sf git-remote-http "$W/git-root/usr/lib/git-core/git-http-push"
    done_ git
  fi
  pkg_dir kwick-git
  cp -a "$W/git-root/." "$D/"
  rm -rf "$D/usr/share/perl5" "$D/usr/share/gitweb" "$D/usr/share/git-gui" "$D/usr/share/gitk" "$D/usr/share/man"
  for x in git-daemon git-http-backend git-imap-send git-cvsserver scalar; do rm -f "$D/usr/lib/git-core/$x" "$D/usr/bin/$x"; done
  install -Dm0644 "$W/src/git/contrib/completion/git-completion.bash" "$D/usr/share/bash-completion/completions/git"
  strip_all "$D"
  install -Dm0644 "$W/src/git/COPYING" "$D/usr/share/doc/kwick-git/copyright"
  control kwick-git "$v-0kwick1" "$ARCH" "fast, scalable, distributed revision control system (lean musl build)" \
    "Depends: kwick-ca-bundle" "Provides: git (= 1:$v-0kwick1)" "Conflicts: git" "Replaces: git" "X-Kwick-Lean: git" \
    "X-Kwick-Upstream: git $v, curl $(ver curl), mbedTLS $(ver mbedtls), PCRE2 $(ver pcre2), expat $(ver expat), zlib $(ver zlib)"
  printf ' %s\n' "git $v linked statically against musl, with HTTPS (libcurl and mbedTLS), PCRE2 and expat." \
    "Like Alpine's git it has no Perl, Tcl/Tk or Python parts (send-email, svn, gitk, git-gui)," \
    "and git-daemon, http-backend, imap-send and scalar are left out. Debian's full build: apt install --no-lean git" >> "$D/DEBIAN/control"
  build_deb
}

do_nginx() {
  dep_zlib; dep_libressl; dep_pcre2
  local v; v=$(ver nginx)
  if ! built nginx; then
    unpack nginx
    log nginx-configure ./configure --prefix=/usr/share/nginx --sbin-path=/usr/sbin/nginx --modules-path=/usr/lib/nginx/modules \
      --conf-path=/etc/nginx/nginx.conf --error-log-path=/var/log/nginx/error.log --http-log-path=/var/log/nginx/access.log \
      --pid-path=/run/nginx.pid --lock-path=/var/lock/nginx.lock \
      --http-client-body-temp-path=/var/lib/nginx/body --http-fastcgi-temp-path=/var/lib/nginx/fastcgi \
      --http-proxy-temp-path=/var/lib/nginx/proxy --http-scgi-temp-path=/var/lib/nginx/scgi --http-uwsgi-temp-path=/var/lib/nginx/uwsgi \
      --user=www-data --group=www-data --with-threads --with-file-aio \
      --with-http_ssl_module --with-http_v2_module --with-http_v3_module --with-http_realip_module --with-http_addition_module \
      --with-http_sub_module --with-http_dav_module --with-http_flv_module --with-http_mp4_module --with-http_gunzip_module \
      --with-http_gzip_static_module --with-http_auth_request_module --with-http_random_index_module --with-http_secure_link_module \
      --with-http_degradation_module --with-http_slice_module --with-http_stub_status_module --with-pcre-jit \
      --with-cc-opt="-I$LR/include $CFLAGS $CPPFLAGS" --with-ld-opt="-L$LR/lib $STATIC_LD"
    log nginx make -j"$JOBS"
    done_ nginx
  fi
  pkg_dir kwick-nginx
  install -Dm0755 "$W/src/nginx/objs/nginx" "$D/usr/sbin/nginx"
  strip_all "$D"
  mkdir -p "$D/etc/nginx/conf.d" "$D/etc/nginx/sites-available" "$D/etc/nginx/sites-enabled" "$D/etc/nginx/snippets" \
    "$D/etc/nginx/modules-enabled" "$D/var/www/html" "$D/usr/lib/systemd/system" "$D/usr/share/doc/kwick-nginx"
  for f in mime.types fastcgi_params fastcgi.conf scgi_params uwsgi_params; do install -m0644 "$W/src/nginx/conf/$f" "$D/etc/nginx/$f"; done
  cat > "$D/etc/nginx/nginx.conf" <<'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
error_log /var/log/nginx/error.log;
include /etc/nginx/modules-enabled/*.conf;

events {
	worker_connections 768;
}

http {
	sendfile on;
	tcp_nopush on;
	types_hash_max_size 2048;
	server_tokens off;

	include /etc/nginx/mime.types;
	default_type application/octet-stream;

	ssl_protocols TLSv1.2 TLSv1.3;
	ssl_prefer_server_ciphers off;

	access_log /var/log/nginx/access.log;

	gzip on;

	include /etc/nginx/conf.d/*.conf;
	include /etc/nginx/sites-enabled/*;
}
EOF
  cat > "$D/etc/nginx/sites-available/default" <<'EOF'
server {
	listen 80 default_server;
	listen [::]:80 default_server;

	root /var/www/html;
	index index.html index.htm;
	server_name _;

	location / {
		try_files $uri $uri/ =404;
	}
}
EOF
  ln -s /etc/nginx/sites-available/default "$D/etc/nginx/sites-enabled/default"
  cat > "$D/etc/nginx/snippets/fastcgi-php.conf" <<'EOF'
fastcgi_split_path_info ^(.+?\.php)(/.*)$;
try_files $fastcgi_script_name =404;
set $path_info $fastcgi_path_info;
fastcgi_param PATH_INFO $path_info;
fastcgi_index index.php;
include fastcgi.conf;
EOF
  printf '<!DOCTYPE html>\n<html><head><title>Welcome to nginx!</title></head>\n<body><h1>Welcome to nginx!</h1>\n<p>nginx on KwickOS is working.</p></body></html>\n' > "$D/var/www/html/index.nginx-kwick.html"
  cat > "$D/usr/lib/systemd/system/nginx.service" <<'EOF'
[Unit]
Description=A high performance web server and a reverse proxy server
After=network.target

[Service]
Type=forking
PIDFile=/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t -q -g 'daemon on; master_process on;'
ExecStart=/usr/sbin/nginx -g 'daemon on; master_process on;'
ExecReload=/usr/sbin/nginx -g 'daemon on; master_process on;' -s reload
ExecStop=/usr/sbin/nginx -s quit
TimeoutStopSec=5

[Install]
WantedBy=multi-user.target
EOF
  cat > "$D/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = configure ]; then
  mkdir -p /var/lib/nginx /var/log/nginx
  chmod 0755 /var/log/nginx
  [ -e /var/www/html/index.html ] || [ -e /var/www/html/index.htm ] || cp /var/www/html/index.nginx-kwick.html /var/www/html/index.html
  deb-systemd-helper enable nginx.service >/dev/null 2>&1 || true
  deb-systemd-invoke start nginx.service >/dev/null 2>&1 || true
fi
EOF
  cat > "$D/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
[ "$1" = remove ] && deb-systemd-invoke stop nginx.service >/dev/null 2>&1 || true
EOF
  install -m0644 "$W/src/nginx/LICENSE" "$D/usr/share/doc/kwick-nginx/copyright"
  control kwick-nginx "$v-0kwick1" "$ARCH" "small, powerful, scalable web/proxy server (lean musl build)" \
    "Provides: nginx (= $v-0kwick1), httpd" "Conflicts: nginx, nginx-common, nginx-core, nginx-full, nginx-light, nginx-extras" \
    "Replaces: nginx, nginx-common, nginx-core" "X-Kwick-Lean: nginx" \
    "X-Kwick-Upstream: nginx $v, LibreSSL $(ver libressl), PCRE2 $(ver pcre2), zlib $(ver zlib)"
  printf ' %s\n' "nginx $v linked statically against musl, LibreSSL $(ver libressl) (TLS 1.2/1.3, HTTP/2, HTTP/3), PCRE2 and zlib," \
    "with Debian's /etc/nginx layout and the modules of Alpine's main nginx package built in." \
    "It cannot load dynamic modules (libnginx-mod-*); installing one switches to Debian's nginx." \
    "Debian's full build: apt install --no-lean nginx" >> "$D/DEBIAN/control"
  build_deb
}

do_openssh() {
  dep_zlib; dep_libressl
  local v; v=$(ver openssh)
  if ! built openssh; then
    unpack openssh
    export LD_LIBRARY_PATH="$LR/lib"
    log openssh-configure ./configure --prefix=/usr --sysconfdir=/etc/ssh --libexecdir=/usr/lib/openssh \
      --with-privsep-path=/run/sshd --with-privsep-user=sshd --with-ssl-dir="$LR" --with-zlib="$P" --with-pid-dir=/run \
      --without-pam --without-kerberos5 --without-selinux --without-libedit --without-security-key-builtin --disable-strip \
      --with-default-path=/usr/local/bin:/usr/bin:/bin --with-superuser-path=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
      AR=gcc-ar RANLIB=gcc-ranlib CFLAGS="${CFLAGS/-fPIC/-fPIE} $LTO" \
      LDFLAGS="-L$LR/lib $LDFLAGS $LTO -Wl,--dynamic-linker=$MUSL_LD -Wl,-rpath,/usr/lib/openssh"
    log openssh make -j"$JOBS" sshd sshd-session sshd-auth sftp-server ssh-keygen
    unset LD_LIBRARY_PATH
    done_ openssh
  fi
  local s="$W/src/openssh"
  pkg_dir kwick-openssh-server
  install -Dm0755 "$s/sshd" "$D/usr/sbin/sshd"
  install -Dm0755 "$s/sshd-session" "$D/usr/lib/openssh/sshd-session"
  install -Dm0755 "$s/sshd-auth" "$D/usr/lib/openssh/sshd-auth"
  install -Dm0755 "$s/sftp-server" "$D/usr/lib/openssh/sftp-server"
  install -Dm0755 "$s/ssh-keygen" "$D/usr/lib/kwick/openssh/ssh-keygen"
  strip_all "$D"
  local so; so=$(objdump -p "$LR/lib/libcrypto.so" | awk '/SONAME/ {print $2}')
  install -Dm0644 "$(readlink -f "$LR/lib/libcrypto.so")" "$D/usr/lib/openssh/$so"
  strip --strip-unneeded "$D/usr/lib/openssh/$so"
  mkdir -p "$D/etc/ssh/sshd_config.d" "$D/usr/lib/systemd/system" "$D/usr/lib/sysusers.d" "$D/usr/share/doc/kwick-openssh-server"
  cat > "$D/etc/ssh/sshd_config" <<'EOF'
Include /etc/ssh/sshd_config.d/*.conf

KbdInteractiveAuthentication no
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOF
  printf 'u sshd - "sshd privilege separation" /run/sshd /usr/sbin/nologin\n' > "$D/usr/lib/sysusers.d/kwick-openssh-server.conf"
  cat > "$D/usr/lib/systemd/system/ssh.service" <<'EOF'
[Unit]
Description=OpenBSD Secure Shell server
After=network.target

[Service]
ExecStartPre=/usr/sbin/sshd -t
ExecStart=/usr/sbin/sshd -D
ExecReload=/usr/sbin/sshd -t
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
Restart=on-failure
RuntimeDirectory=sshd
RuntimeDirectoryMode=0755

[Install]
WantedBy=multi-user.target
Alias=sshd.service
EOF
  cat > "$D/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = configure ]; then
  [ -e /usr/bin/ssh-keygen ] || [ -L /usr/bin/ssh-keygen ] || ln -s /usr/lib/kwick/openssh/ssh-keygen /usr/bin/ssh-keygen
  systemd-sysusers kwick-openssh-server.conf >/dev/null 2>&1 || grep -q '^sshd:' /etc/passwd || adduser -S -D -H -h /run/sshd -s /usr/sbin/nologin sshd >/dev/null 2>&1 || true
  mkdir -p /run/sshd
  /usr/lib/kwick/openssh/ssh-keygen -A >/dev/null
  deb-systemd-helper enable ssh.service >/dev/null 2>&1 || true
  deb-systemd-invoke start ssh.service >/dev/null 2>&1 || true
fi
EOF
  cat > "$D/DEBIAN/prerm" <<'EOF'
#!/bin/sh
set -e
[ "$1" = remove ] && deb-systemd-invoke stop ssh.service >/dev/null 2>&1 || true
EOF
  cat > "$D/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = remove ] || [ "$1" = purge ]; then
  [ "$(readlink /usr/bin/ssh-keygen 2>/dev/null)" = /usr/lib/kwick/openssh/ssh-keygen ] && rm -f /usr/bin/ssh-keygen
fi
if [ "$1" = purge ]; then
  rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub
fi
exit 0
EOF
  install -m0644 "$s/LICENCE" "$D/usr/share/doc/kwick-openssh-server/copyright"
  control kwick-openssh-server "$v-0kwick1" "$ARCH" "secure shell (SSH) server (lean musl build)" \
    "Provides: openssh-server (= 1:$v-0kwick1), openssh-sftp-server (= 1:$v-0kwick1), ssh-server, sftp-server" \
    "Conflicts: openssh-server, openssh-sftp-server" "Replaces: openssh-server, openssh-sftp-server" "X-Kwick-Lean: openssh-server" \
    "Depends: kwick-musl" "X-Kwick-Upstream: OpenSSH $v, LibreSSL $(ver libressl), zlib $(ver zlib)"
  printf ' %s\n' "OpenSSH $v sshd, sftp-server and ssh-keygen built against musl and LibreSSL $(ver libressl)" \
    "libcrypto, kept private in /usr/lib/openssh. Like Alpine's openssh-server it has no PAM, Kerberos," \
    "SELinux or moduli file; password logins check /etc/shadow. Debian's build: apt install --no-lean openssh-server" >> "$D/DEBIAN/control"
  build_deb
}

do_python() {
  dep_zlib; dep_bzip2; dep_xz; dep_libffi; dep_sqlite; dep_ncurses; dep_readline; dep_openssl
  local v pv; v=$(ver python); pv=${v%.*}
  local PR="$W/py-root" plib="usr/lib/python$pv"
  if ! built python; then
    unpack python
    cat > Modules/Setup.local <<EOF
*static*
_ssl _ssl.c -I$P/include -L$P/lib -lssl -lcrypto
_hashlib _hashopenssl.c -I$P/include -L$P/lib -lcrypto
EOF
    log python-configure ./configure --prefix=/usr --disable-shared --without-static-libpython --with-ensurepip=no \
      --without-system-libmpdec --without-system-expat --with-dbmliborder= --enable-ipv6 --with-computed-gotos \
      --with-openssl="$P" --with-readline=readline CFLAGS="${CFLAGS/-Os/-O2} -DTHREAD_STACK_SIZE=0x100000" \
      READLINE_CFLAGS="-I$P/include" READLINE_LIBS="-L$P/lib -lreadline -lncursesw" \
      CURSES_CFLAGS="-I$P/include/ncursesw -D_XOPEN_SOURCE_EXTENDED" CURSES_LIBS="-L$P/lib -lncursesw" \
      PANEL_CFLAGS="-I$P/include/ncursesw" PANEL_LIBS="-L$P/lib -lpanelw" \
      LIBSQLITE3_CFLAGS="-I$P/include" LIBSQLITE3_LIBS="-L$P/lib -lsqlite3 -lm" \
      LIBLZMA_CFLAGS="-I$P/include" LIBLZMA_LIBS="-L$P/lib -llzma" BZIP2_CFLAGS="-I$P/include" BZIP2_LIBS="-L$P/lib -lbz2" \
      LIBFFI_CFLAGS="-I$P/include" LIBFFI_LIBS="-L$P/lib -lffi" ZLIB_CFLAGS="-I$P/include" ZLIB_LIBS="-L$P/lib -lz" \
      LDFLAGS="$LDFLAGS -Wl,--dynamic-linker=$MUSL_LD"
    log python make -j"$JOBS"
    rm -rf "$PR"
    log python-install make DESTDIR="$PR" install
    done_ python
  fi
  rm -rf "$W/py-split"; mkdir -p "$W/py-split"
  PYTHONHOME="$PR/usr" "$PR/usr/bin/python$pv" -P -s -S - "$PR/$plib" "$W/py-split" "$SOURCE_DATE_EPOCH" <<'PYEOF'
import os, sys, shutil, zipfile, importlib.util, importlib._bootstrap_external as be
lib, split, epoch = sys.argv[1], sys.argv[2], int(sys.argv[3])
keep_out = {"site-packages", "lib-dynload", "venv", "ensurepip", "__pycache__"}
extras = {"test", "idlelib", "tkinter", "turtledemo", "__phello__"}
drop = {"lib2to3"}
ver = "%d%d" % sys.version_info[:2]
zpath = os.path.join(split, "python%s.zip" % ver)
date = (1980, 1, 1, 0, 0, 0)
os.makedirs(os.path.join(split, "tests"), exist_ok=True)
entries = []
for name in sorted(os.listdir(lib)):
    full = os.path.join(lib, name)
    if name in keep_out or name.startswith("config-"):
        continue
    if name in extras:
        shutil.copytree(full, os.path.join(split, "tests", name), symlinks=True)
        continue
    if name in drop:
        continue
    if os.path.isdir(full):
        for root, dirs, files in os.walk(full):
            dirs[:] = sorted(d for d in dirs if d != "__pycache__")
            for f in sorted(files):
                entries.append(os.path.join(root, f))
    else:
        entries.append(full)
with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for p in entries:
        arc = os.path.relpath(p, lib).replace(os.sep, "/")
        data = open(p, "rb").read()
        zi = zipfile.ZipInfo(arc, date); zi.compress_type = zipfile.ZIP_DEFLATED; zi.external_attr = 0o644 << 16
        z.writestr(zi, data, compresslevel=9)
        if arc.endswith(".py"):
            try:
                code = compile(data, "/usr/lib/python%s.zip/%s" % (ver, arc), "exec", dont_inherit=True)
            except SyntaxError:
                continue
            pyc = be._code_to_hash_pyc(code, importlib.util.source_hash(data), checked=False)
            zc = zipfile.ZipInfo(arc + "c", date); zc.compress_type = zipfile.ZIP_DEFLATED; zc.external_attr = 0o644 << 16
            z.writestr(zc, bytes(pyc), compresslevel=9)
PYEOF
  pkg_dir kwick-python3
  mkdir -p "$D/usr/bin" "$D/$plib"
  cp -a "$PR/usr/bin/python$pv" "$D/usr/bin/"
  ln -s "python$pv" "$D/usr/bin/python3"
  cp "$W/py-split/python${pv/./}.zip" "$D/usr/lib/"
  for x in lib-dynload site-packages venv ensurepip; do cp -a "$PR/$plib/$x" "$D/$plib/"; done
  find "$D/$plib" -name __pycache__ -prune -exec rm -rf {} +
  PYTHONHOME="$PR/usr" "$PR/usr/bin/python$pv" -P -s -m compileall -q -j1 --invalidation-mode unchecked-hash -d "/$plib" "$D/$plib/venv" "$D/$plib/ensurepip" >/dev/null
  mkdir -p "$STAGE/py-tests-dynload"
  find "$D/$plib/lib-dynload" \( -name '_test*' -o -name 'xx*' -o -name '_ctypes_test*' \) -exec mv {} "$STAGE/py-tests-dynload/" \;
  strip_all "$D"
  find "$D/$plib/lib-dynload" -name '*.so' -exec strip --strip-unneeded {} +
  printf '[externally-managed]\nError=This Python is managed by KwickOS (kwick-python3). Use a virtual environment:\n python3 -m venv .venv && . .venv/bin/activate && pip install PACKAGE\n' > "$D/$plib/EXTERNALLY-MANAGED"
  install -Dm0644 "$W/src/python/LICENSE" "$D/usr/share/doc/kwick-python3/copyright"
  control kwick-python3 "$v-0kwick1" "$ARCH" "interactive high-level object-oriented language (lean musl build)" \
    "Depends: kwick-musl, kwick-ca-bundle" \
    "Conflicts: python3, python3-minimal, python$pv, python$pv-minimal, libpython$pv-stdlib, libpython$pv-minimal" \
    "X-Kwick-Lean: python3" \
    "X-Kwick-Upstream: CPython $v, OpenSSL $(ver openssl), SQLite $(ver sqlite), libffi $(ver libffi), xz $(ver xz), bzip2 $(ver bzip2), zlib $(ver zlib), ncurses $(ver ncurses), readline $(ver readline)"
  printf ' %s\n' "CPython $v built against musl. The standard library ships as python${pv/./}.zip with" \
    "source and compiled bytecode; ssl and hashlib are built in with OpenSSL $(ver openssl). pip, venv and" \
    "ensurepip work; modules come from PyPI's musllinux wheels. Debian's python3-* packages need" \
    "Debian's Python and replace this one when installed. Debian's build: apt install --no-lean python3" >> "$D/DEBIAN/control"
  build_deb
  pkg_dir kwick-python3-tests
  mkdir -p "$D/$plib/lib-dynload"
  cp -a "$W/py-split/tests/." "$D/$plib/"
  find "$D/$plib" -name __pycache__ -prune -exec rm -rf {} +
  cp -a "$STAGE/py-tests-dynload/." "$D/$plib/lib-dynload/"
  find "$D/$plib/lib-dynload" -name '*.so' -exec strip --strip-unneeded {} +
  control kwick-python3-tests "$v-0kwick1" "$ARCH" "Python standard library test suite and IDLE/Tk sources (lean build extra)" \
    "Depends: kwick-python3 (= $v-0kwick1)"
  printf ' %s\n' "The regression tests, their C helper modules, idlelib, tkinter and turtledemo, split out of" \
    "kwick-python3 the way Alpine splits python3-tests (Tk itself is not built)." >> "$D/DEBIAN/control"
  build_deb
}

for p in $PKGS; do
  case $p in
    ca-bundle) do_ca_bundle ;;
    musl) do_musl ;;
    curl) do_curl ;;
    git) do_git ;;
    nginx) do_nginx ;;
    openssh) do_openssh ;;
    python) do_python ;;
    *) echo "unknown package $p" >&2; exit 1 ;;
  esac
done
