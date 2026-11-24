kwick_version() { tr -d '\r\n' < "$SRC/VERSION"; }

deb_stage_tree() {
  cp -r --no-preserve=ownership "$2/." "$1/"
  find "$1" -type d -exec chmod 755 {} +
  find "$1" -type f -exec chmod 644 {} +
  chmod 755 "$1"/usr/bin/*
}

deb_control() {
  local size=${6:-$(du -sk "$1" | cut -f1)}
  {
    printf 'Package: %s\nVersion: %s\nArchitecture: %s\n' "$2" "$3" "$4"
    printf 'Maintainer: KwickOS Developers <dev@kwickos.org>\nSection: %s\nPriority: optional\nInstalled-Size: %s\n' "$5" "$size"
    cat
  } > "$1/DEBIAN/control"
}

deb_script() {
  cat > "$1/DEBIAN/$2"
  chmod 755 "$1/DEBIAN/$2"
}

kernel_deb_version() { echo "$1-2"; }

deb_conffiles() {
  [ -d "$1/etc" ] || return 0
  find "$1/etc" -type f ! -path "$1/etc/skel/*" | sed "s|^$1||" | LC_ALL=C sort > "$1/DEBIAN/conffiles"
  [ -s "$1/DEBIAN/conffiles" ] || rm -f "$1/DEBIAN/conffiles"
}

deb_register() {
  local R=$1 deb=$2 pkg x f
  pkg=$(dpkg-deb -f "$deb" Package)
  x=$(mktemp -d)
  mkdir -p "$R/var/lib/dpkg/info"
  dpkg-deb -x "$deb" "$R"
  dpkg-deb -e "$deb" "$x"
  for s in preinst postinst prerm postrm md5sums conffiles triggers; do
    [ -f "$x/$s" ] && cp -p "$x/$s" "$R/var/lib/dpkg/info/$pkg.$s"
  done
  dpkg-deb --fsys-tarfile "$deb" | tar -t | sed -e 's|^\./|/|' -e 's|/$||' -e 's|^$|/.|' | LC_ALL=C sort -u > "$R/var/lib/dpkg/info/$pkg.list"
  {
    echo
    dpkg-deb -f "$deb" | awk '{ print } /^Package:/ { print "Status: install ok installed" }'
    if [ -s "$x/conffiles" ]; then
      echo "Conffiles:"
      while read -r f; do
        [ -n "$f" ] && [ -f "$R$f" ] && echo " $f $(md5sum < "$R$f" | cut -d' ' -f1)"
      done < "$x/conffiles"
    fi
    echo
  } >> "$R/var/lib/dpkg/status"
  rm -rf "$x"
  chmod 755 "$R"
  echo "registered $pkg $(dpkg-deb -f "$deb" Version)"
}

deb_base_pkgs() {
  local arch=$1 t=$2 tar=$3
  if ! ls "$t"/repo/pool/main/kwick-core_*_"$arch".deb >/dev/null 2>&1; then
    mkdir -p "$t"
    OUT=$t SRC=$SRC bash "$SRC/scripts/mkupdatepkg.sh" >/dev/null
    OUT=$t SRC=$SRC bash "$SRC/scripts/mkcorepkg.sh" "$arch" "$tar" >/dev/null
  fi
  ls "$t"/repo/pool/main/kwick-update_*_all.deb "$t"/repo/pool/main/kwick-core_*_"$arch".deb
}

deb_core_links() {
  local b s d
  for b in sbin/kinit bin/kpkg; do
    s="$1/usr/lib/kwick/core/${b#*/}"; d="$1/usr/$b"
    [ -f "$s" ] && [ -f "$d" ] && cmp -s "$s" "$d" && ln -f "$d" "$s"
  done
  return 0
}

deb_check_deps() {
  python3 -I "$SRC/scripts/dpkg-depcheck.py" "$1/var/lib/dpkg/status"
}

deb_build() {
  mkdir -p "$OUT/repo/pool/main"
  dpkg-deb --root-owner-group -Zxz -b "$1" "$OUT/repo/pool/main/${2}_${3}_${4}.deb" >/dev/null
  rm -rf "$1"
  echo "packaged $2 $3${5:+ $5}"
}
