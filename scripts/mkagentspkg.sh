#!/bin/bash
set -euo pipefail
SRC=${SRC:-/src}; OUT=${OUT:-/out}
. "$(cd "$(dirname "$0")" && pwd)/deb.sh"
VER=$(kwick_version)
export GOTOOLCHAIN=${GOTOOLCHAIN:-auto}
export GOPATH=${GOPATH:-/cache/go} GOCACHE=${GOCACHE:-/cache/go-build} GOFLAGS=-mod=mod CGO_ENABLED=0
B=$(mktemp -d)
(
  cd "$SRC/src/kwick-agents"
  go vet ./...
  for arch in ${ARCHES:-amd64 arm64 riscv64}; do
    GOOS=linux GOARCH=$arch go build -trimpath -buildvcs=false -ldflags="-s -w -buildid= -X main.version=$VER" -o "$B/kwick-agents-$arch" .
  done
)
for arch in ${ARCHES:-amd64 arm64 riscv64}; do
  P=$(mktemp -d); mkdir -p "$P/DEBIAN" "$P/usr/bin" "$P/usr/share/doc/kwick-agents"
  cp -r --no-preserve=ownership "$SRC/desktop/agents/rootfs/." "$P/"
  find "$P" -type f -exec grep -Iq . {} \; -exec sed -i 's/\r$//' {} +
  find "$P" -type d -exec chmod 755 {} +
  find "$P" -type f -exec chmod 644 {} +
  install -m 755 "$B/kwick-agents-$arch" "$P/usr/bin/kwick-agents"
  ln -sf kwick-agents "$P/usr/bin/kwick-mcp"
  chmod 755 "$P/usr/lib/kwick/agents/kwick-agents-priv"
  sed 's/\r$//' "$SRC/rootfs/usr/share/doc/kwickos/AGENTS.md" > "$P/usr/share/doc/kwick-agents/AGENTS.md"
  sed 's/\r$//' "$SRC/docs/AGENTS.md" > "$P/usr/share/doc/kwick-agents/README.md"
  deb_control "$P" kwick-agents "$VER" "$arch" utils <<EOF
Depends: bubblewrap, ca-certificates, libstdc++6, libgomp1
Recommends: libsecret-tools, sudo
Suggests: git, zenity | kdialog, libnotify-bin
Description: KwickOS AI agents: catalog, sandbox, keys and MCP server
 kwick-agents installs AI agents (Claude Code, Codex, Gemini CLI, opencode,
 oh-my-pi, OpenClaw, Hermes, Aider, Goose, Cybara) and local model runtimes
 (Ollama, llama.cpp) per user, each pinned to a release and verified against
 a sha256, a lock file or a git commit. Agents run in bubblewrap sandboxes
 with their API keys taken from the Secret Service or a mode 600 keystore.
 kwick-mcp is a Model Context Protocol server that gives agents permissioned
 access to KwickOS (system, packages, snapshots, files, settings, apps,
 screenshots) with consent prompts and an audit log.
EOF
  deb_script "$P" postinst <<'EOF'
#!/bin/sh
[ "$1" = configure ] || exit 0
mkdir -p /var/lib/kwick-agents
chmod 755 /var/lib/kwick-agents
exit 0
EOF
  deb_build "$P" kwick-agents "$VER" "$arch"
done
rm -rf "$B"
