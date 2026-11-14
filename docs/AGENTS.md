# kwick-agents: AI agent tooling

`kwick-agents` is an optional, modular installer for AI agent tooling. Nothing is installed by default. It is built by
`scripts/mkagentspkg.sh` into a tiny `kwick-agents` package.

```
kwick-agents list
kwick-agents status [--machine]
kwick-agents install [--latest] <module...>
kwick-agents remove <module...>
kwick-agents all
```

| Module | What | Arch | Source |
|---|---|---|---|
| `cybara` | Cybara self-hosted agent platform (CLI and gateway) | amd64, arm64 | official GitHub release, pinned, sha256 |
| `inference` | KwickOS multi-GPU inference engine (coming later) | n/a | not available yet |

New modules are one file each in `/usr/lib/kwick/agents/` defining `<name>_arch`, `<name>_desc`, `<name>_state`, `<name>_install` and
`<name>_remove`, plus one line in `MODULES` in `kwick-agents`.

## Cybara

[Cybara](https://cybara.ai) is a self-hosted, open-source (MIT) AI agent platform by Carsen Klock: a Bun gateway that runs
persistent, tool-using agents, with a web dashboard, a terminal UI, desktop apps (Tauri, native macOS), mobile apps, MCP support
and messaging channels. The `cybara` command is a single self-contained executable; `cybara start` launches the gateway in the
background and serves the dashboard on `http://localhost:4269`. It is a CLI plus a local service, and the desktop app is a separate
download. The website itself carries only a tagline; the install facts below come from the project's README, its install script
and its GitHub releases (`metaspartan/cybara`).

Official install methods on Linux:

- `curl -fsSL https://cybara.ai/install.sh | bash` (the vendor's documented one-liner). The script downloads the
  `cybara-<tag>-linux-<x64|arm64>-cli` release asset, checks it against the asset's published `.sha256` file and installs it to
  `~/.local/bin` (or `/usr/local/bin` when writable).
- `bunx cybara` or `npm install -g cybara`, a launcher that fetches the same binary.
- Desktop app packages (`.deb`, `.rpm`, AppImage) from [cybara.ai/download](https://cybara.ai/download) and GitHub Releases.

Supported Linux architectures: x86_64 and arm64. There is no riscv64 build.

`kwick-agents install cybara` does the same thing as the install script without running it: it downloads the identical release
asset for the machine architecture from GitHub, compares it with the sha256 pinned in `/usr/lib/kwick/agents/pins.env` (which matches
the vendor's `.sha256` sidecar for that release), and installs it to `/usr/local/bin/cybara`. Nothing from the network is executed as
a script. The URL and expected hash are printed before the download. Pinned version: 1.0.2586.

`--latest` resolves the newest release through the GitHub API and verifies against the vendor's `.sha256` sidecar instead. That
checksum is served from the same origin as the binary, so it only detects corruption, not a compromised release. The pinned default
is the stronger option.

`kwick-agents remove cybara` deletes the binary and leaves your Cybara data and settings in your home directory.

Not done: the vendor ships `.sig` signatures for its packages, but publishes no key or verification instructions that I could find,
so signatures are not checked. The desktop app is not wrapped; install its `.deb` from the download page if you want it.

## inference

A placeholder for a KwickOS multi-GPU inference engine. `kwick-agents install inference` prints "not available yet" and does nothing.
