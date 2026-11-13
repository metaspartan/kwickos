#!/bin/sh
set -e

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

KWICK_BASE=${KWICK_BASE:-https://metaspartan.github.io/kwickos/apple}

export VERSION_FLAG=${VERSION_FLAG:-https://cdn.asahilinux.org/installer/latest}
export INSTALLER_BASE=${INSTALLER_BASE:-https://cdn.asahilinux.org/installer}
export INSTALLER_DATA=${INSTALLER_DATA:-$KWICK_BASE/installer_data.json}
export REPO_BASE=${REPO_BASE:-$KWICK_BASE}

if [ "$(uname -s)" != Darwin ]; then
  echo "KwickOS for Apple Silicon is installed from macOS or recoveryOS on the Mac itself." >&2
  exit 1
fi

TMP=/tmp/kwickos-install
if [ -e "$TMP" ]; then mv "$TMP" "$TMP.old.$(date +%Y%m%d%H%M%S)"; fi
mkdir -p "$TMP"
cd "$TMP"

echo "Downloading the Asahi installer (the boot chain installer used by every Linux distribution on Apple Silicon)"
PKG_VER=$(curl -fsSL "$VERSION_FLAG")
curl -fsSL -o installer.tar.gz "$INSTALLER_BASE/installer-$PKG_VER.tar.gz"
curl -fsSL -o installer_data.json "$INSTALLER_DATA"
tar xf installer.tar.gz

echo "Starting the installer. KwickOS is added as a new OS next to macOS; nothing is erased unless you choose so."
if [ "$USER" = root ]; then
  exec caffeinate -dis ./install.sh "$@"
else
  exec sudo caffeinate -dis ./install.sh "$@"
fi
