KWIN_PLUGIN_DEPS="build-essential cmake extra-cmake-modules pkg-config kwin-dev libepoxy-dev libwayland-dev qt6-base-dev qt6-base-private-dev qt6-declarative-dev libkf6config-dev libkf6coreaddons-dev libkf6windowsystem-dev libkdecorations3-dev"

kwin_plugin_build() {
  if ! dpkg -s kwin-dev qt6-base-private-dev extra-cmake-modules >/dev/null 2>&1; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $KWIN_PLUGIN_DEPS
  fi
  W=$(mktemp -d)
  trap 'rm -rf "$W"' EXIT
  cmake -S "$1" -B "$W/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=OFF >/dev/null
  cmake --build "$W/build" -j"$(nproc)" >/dev/null
  DESTDIR="$2" cmake --install "$W/build" >/dev/null
}

kwin_plugin_copyright() {
  mkdir -p "$1/usr/share/doc/$2"
  cat > "$1/usr/share/doc/$2/copyright"
}
