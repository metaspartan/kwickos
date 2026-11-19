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

deb_build() {
  mkdir -p "$OUT/repo/pool/main"
  dpkg-deb --root-owner-group -Zxz -b "$1" "$OUT/repo/pool/main/${2}_${3}_${4}.deb" >/dev/null
  rm -rf "$1"
  echo "packaged $2 $3${5:+ $5}"
}
