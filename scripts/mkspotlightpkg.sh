#!/bin/bash
set -euo pipefail
export LC_ALL=C.UTF-8
DEST=${1:?destdir}
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/kwin-plugin.sh"
DEPS="libkf6runner-dev libkf6globalaccel-dev libkf6dbusaddons-dev libkf6kio-dev libkf6service-dev liblayershellqtinterface-dev"
if ! dpkg -s $DEPS >/dev/null 2>&1; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $KWIN_PLUGIN_DEPS $DEPS
fi
kwin_plugin_build "${SPOTLIGHT_SRC:-$HERE/../src/kwick-spotlight}" "$DEST"
kwin_plugin_copyright "$DEST" kwick-spotlight <<'COPYRIGHT'
kwick-spotlight (Spotlight Search for Plasma, GNOME and Hyprland) and the krunner_kwick KRunner
plugin (KwickOS Settings pages, quick actions and a home folder file index)

Source: src/kwick-spotlight in the KwickOS repository.
License of the source: MIT, Copyright (c) 2026 Carsen Klock.

The binaries link against Qt, KDE Frameworks (KRunner, KIO, KGlobalAccel,
KDBusAddons, KConfig, KService, KWindowSystem) and LayerShellQt.
COPYRIGHT
find "$DEST/usr" -type f \( -name kwick-spotlight -o -name krunner_kwick.so \)
