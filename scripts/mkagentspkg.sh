#!/bin/bash
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}
. "$(cd "$(dirname "$0")" && pwd)/deb.sh"
VER=$(kwick_version)
P=$(mktemp -d); mkdir -p "$P/DEBIAN"
deb_stage_tree "$P" "$SRC/desktop/agents/rootfs"
deb_control "$P" kwick-agents "$VER" all utils 40 <<EOF
Depends: curl, ca-certificates
Recommends: sudo
Description: KwickOS AI agent tooling modules
 Optional AI agent modules. 'kwick-agents install cybara' installs the Cybara
 self-hosted agent platform CLI from the official release, pinned to a version
 and verified against its sha256. Nothing is installed by default. amd64 and
 arm64 only for Cybara.
EOF
deb_script "$P" postinst <<'EOF'
#!/bin/sh
[ "$1" = configure ] || exit 0
mkdir -p /var/lib/kwick-agents
exit 0
EOF
deb_build "$P" kwick-agents "$VER" all
