# kwick-agents: AI agents on KwickOS

`kwick-agents` makes KwickOS a good home for AI agents. It is an optional package (`apt install kwick-agents`) with one static Go
binary that does four things:

1. **Catalog.** Installs coding agents and local model runtimes per user (or for every user with `--system`), each pinned to a
   release and verified against a sha256, a lock file or a git commit. No vendor install script is ever piped into a shell.
2. **Sandbox.** Starts every agent in a bubblewrap sandbox that sees only its own configuration folder and the project folder it was
   started in.
3. **Keys.** Keeps API keys in the Secret Service (KWallet or GNOME Keyring) on the desktop, or in a mode 600 file on headless
   machines, and hands them to an agent as environment variables when it starts.
4. **kwick-mcp.** A Model Context Protocol server that gives agents permissioned access to KwickOS: system information, packages,
   updates, snapshots, files, notifications, desktop settings, apps and screenshots. Every request is checked against per-agent
   grants, risky ones ask the user, and everything goes to an audit log.

The guide that tells an agent how to behave on KwickOS is `/usr/share/doc/kwickos/AGENTS.md` (in the base system, source
`rootfs/usr/share/doc/kwickos/AGENTS.md`; the package carries a copy in `/usr/share/doc/kwick-agents/`). kwick-mcp serves it as the
resource `kwickos://docs/agents`.

## Commands

```
kwick-agents list [--json] [--installed]
kwick-agents info NAME [--json]
kwick-agents install NAME... [--system] [--no-mcp]
kwick-agents remove NAME... [--system]
kwick-agents update [NAME...] [--json]
kwick-agents run NAME [--cmd C] [--no-sandbox] [--offline] [-- ARGS]
kwick-agents shell NAME [-- COMMAND]
kwick-agents status [--json|--machine]
kwick-agents key set NAME VAR [--dialog] | key rm NAME VAR | key list [NAME] [--json]
kwick-agents grants [NAME] [--json] | grant NAME CAPABILITY allow|ask|deny|default
kwick-agents folders NAME [add|rm PATH]
kwick-agents sandbox NAME [on|off] | network NAME [on|off]
kwick-agents consent [list|allow ID|always ID|deny ID] [--json]
kwick-agents audit [--json] [-n N] [--agent NAME]
kwick-agents mcp serve [--agent NAME] | mcp enable NAME | mcp disable NAME | mcp status [--json] | mcp tools [--json]
kwick-agents doctor [--json]
```

`install` writes a small launcher for each command of the agent into `~/.local/bin` (`/usr/local/bin` with `--system`), so `claude`,
`codex`, `gemini` and so on start the agent through `kwick-agents run`. An existing file that kwick-agents did not write is never
replaced. `/etc/profile.d/30-kwick-agents.sh` puts `~/.local/bin` on the PATH.

`run` passes the rest of the command line to the agent: `kwick-agents run claude-code -- --help`. `--cmd` picks another command of the
same entry (`kwick-agents run llama-cpp --cmd llama-cli`).

`shell` opens `/bin/sh` inside an agent's sandbox, with the same environment, keys and folders the agent gets. It is the quickest way
to see what an agent can see.

The old interface keeps working: `status --machine` prints `name|yes|no|na|description|note`, `all` installs every agent this machine
supports, `install --latest cybara` installs the newest Cybara release verified against the vendor's `.sha256` sidecar only.

## Catalog

All versions were checked against the projects' own release pages, registries and checksum files on 2026-11-20. The pins live in
`desktop/agents/rootfs/usr/lib/kwick/agents/catalog.json` and ship inside the signed KwickOS package, so the checksums are covered by the
KwickOS repository key.

| Name | Project | Version | Install method and verification | amd64 | arm64 | riscv64 |
|---|---|---|---|---|---|---|
| `claude-code` | Claude Code, Anthropic | 2.1.323 (stable channel) | binary from `downloads.claude.ai/claude-code-releases`, sha256 equal to the vendor `manifest.json`; auto-updater off | yes | yes | no build |
| `codex` | Codex CLI, OpenAI | 0.171.0 | `codex-*-unknown-linux-musl.tar.gz` from GitHub, sha256 equal to the release digest | yes | yes | no build |
| `gemini-cli` | Gemini CLI, Google | 0.70.0 | `gemini-cli-bundle.zip` from GitHub, sha256; runs on the Node.js runtime | yes | yes | yes |
| `opencode` | opencode, Anomaly | 1.19.6 (v1 line) | `opencode-linux-*.tar.gz` from GitHub, sha256 equal to the release digest | yes | yes | no build |
| `omp` | oh-my-pi, Stencil Labs (`can1357/oh-my-pi`) | 19.0.1 | `omp-linux-*` from GitHub, sha256 equal to the vendor `SHA256SUMS.txt` | yes | yes | no build |
| `openclaw` | OpenClaw | 2026.11.6 | `npm ci` from a `package-lock.json` shipped by KwickOS: the sha512 of every tarball (439) is checked; install scripts run sandboxed without network | yes | yes | native modules missing |
| `hermes` | Hermes Agent, Nous Research | 0.23.3 | `git clone` of tag `v0.23.3`, commit `caafe538` checked; `uv sync --frozen` with the hashes in the project's `uv.lock`; needs `git` | yes | yes | not supported upstream |
| `aider` | Aider | 0.86.2 | `uv pip install --require-hashes` from a hash-locked requirements file shipped by KwickOS (109 packages), Python 3.12 | yes | yes | no wheels |
| `goose` | Goose, Agentic AI Foundation | 1.60.2 | `goose-*-unknown-linux-gnu.tar.bz2` from GitHub, sha256 equal to the release digest | yes | yes | no build |
| `cybara` | Cybara | 1.0.2596 | `cybara-v*-linux-*-cli` from GitHub, sha256 equal to the vendor `.sha256` and `checksums.txt` | yes | yes | no build |
| `ollama` | Ollama | 0.40.16 | `ollama-linux-*.tar.zst` from GitHub (about 1.5 GB), sha256 equal to the vendor `sha256sum.txt`; no service, no extra user | yes | yes | no build |
| `llama-cpp` | llama.cpp, ggml-org | b12600 | `llama-b12600-bin-ubuntu-*.tar.gz` (CPU) from GitHub, sha256 equal to the release digest | yes | yes | no build |
| `inference` | KwickOS inference engine | - | placeholder, "not available yet" | - | - | - |

Runtimes, installed automatically when an agent needs them and private to kwick-agents:

| Name | Version | Source and verification |
|---|---|---|
| `node` | 24.22.3 (LTS) | `nodejs.org/dist` tarball, sha256 equal to `SHASUMS256.txt`; riscv64 from `unofficial-builds.nodejs.org` |
| `uv` | 0.13.9 | GitHub musl tarball, sha256 equal to the `.sha256` sidecar; uv checks the sha256 of every Python build it downloads |
| `bun` | 1.4.5 | GitHub zip, sha256 equal to `SHASUMS256.txt` |

What the vendor scripts would have done, and why kwick-agents does it differently:

* Claude Code `install.sh` downloads the same binary and checks it against `manifest.json`, then runs `claude install`, which adds a
  launcher and an auto-updater. kwick-agents pins the stable channel, turns the auto-updater off (`DISABLE_AUTOUPDATER=1`) and updates
  through `kwick-agents update`.
* opencode, Goose and Ollama scripts check no checksum at all. Ollama's script also creates a system user and a systemd service and may
  add the NVIDIA CUDA repository. kwick-agents installs the same archives, verified, into the user's data folder; `ollama serve` runs in
  the sandbox with the GPU devices when the user starts it.
* OpenClaw's script installs Node.js through NodeSource with sudo, build tools and a gateway service, then runs `npm install -g`.
  kwick-agents uses its private Node.js and a lock file and leaves the gateway to `openclaw gateway`.
* Hermes's script clones the repository, installs uv, its own package manager, Node.js and Chromium, and a gateway service. kwick-agents
  does the clone and the locked `uv sync`; the browser tools and TTS extras are not installed.
* The OMP and Cybara scripts verify sha256 like kwick-agents does; kwick-agents adds the KwickOS pin on top.

Updating the pins is a maintainer task: change the version, URL and sha256 in `catalog.json` (and regenerate
`locks/aider/requirements.txt` with `uv pip compile --universal --generate-hashes --no-annotate` or `locks/openclaw/package-lock.json`
with `npm install --package-lock-only --ignore-scripts`), then rebuild the package. `kwick-agents update` moves installed agents to the
new pins.

## Where things are

| Path | What |
|---|---|
| `/usr/bin/kwick-agents`, `/usr/bin/kwick-mcp` | the program (one binary, `kwick-mcp` is a symlink) |
| `/usr/lib/kwick/agents/catalog.json`, `locks/` | catalog and lock files |
| `/usr/lib/kwick/agents/kwick-agents-priv` | the only program kwick-mcp runs as root: `install PKG...`, `upgrade SCOPE`, `snapshot TEXT` |
| `/usr/share/polkit-1/actions/org.kwickos.agents.policy` | polkit action for it (`auth_admin`, never cached) |
| `~/.local/share/kwick-agents/pkgs/NAME/VERSION` | installed agents |
| `~/.local/share/kwick-agents/runtimes/`, `python/` | Node.js, uv, Bun and uv's Python builds |
| `~/.local/share/kwick-agents/home/NAME` | the agent's private home inside the sandbox |
| `~/.local/state/kwick-agents/state.json` | installed versions |
| `~/.local/state/kwick-agents/audit.jsonl` | audit log (JSON lines, rotated at 5 MB) |
| `~/.config/kwick-agents/grants.json` | permissions and folders per agent |
| `~/.config/kwick-agents/agents/NAME.json` | sandbox profile overrides (`sandbox`, `network`, `gpu`, `project`, `rw`, `ro`, `env`) |
| `~/.config/kwick-agents/keys.json` | names of the stored keys and their backend (no values) |
| `~/.config/kwick-agents/secrets.json` | values, mode 600, only when there is no Secret Service |
| `/opt/kwick-agents`, `/var/lib/kwick-agents`, `/etc/kwick-agents` | the same for `--system` installs; `/etc/kwick-agents/grants.json` can force `deny` for an agent or `*` |
| `/var/log/kwick-agents-priv.log` | privileged actions done for agents |

## Sandbox

`kwick-agents run` starts the agent with `bwrap --unshare-all` (user, mount, pid, ipc, uts and cgroup namespaces, plus network unless it
is shared). The new root contains:

* `/usr`, `/etc`, `/opt`, `/sys` read-only, a private `/proc`, `/dev`, `/tmp`, `/var/tmp` and `/run`;
* a private home (`~/.local/share/kwick-agents/home/NAME`) mounted on `$HOME`, with the agent's own folders from the catalog bound in
  read-write (for example `~/.claude` and `~/.claude.json`, `~/.codex`, `~/.gemini`, `~/.config/opencode`), so sign-ins are shared with
  the same agent run outside the sandbox;
* `~/.gitconfig` and `~/.config/git` read-only;
* the agent's install folder and runtime read-only;
* the current folder read-write, unless it is `$HOME`, `/` or a system folder (then the agent starts in its private home and says so);
* `/run/kwick-mcp.sock`, the socket of the kwick-mcp broker of this run.

The environment is rebuilt from scratch: terminal and locale variables, proxies, `HOME`, `USER`, a `PATH` with the agent and its
runtime, `KWICK_AGENT=NAME`, `KWICK_AGENT_SANDBOX=1`, the catalog's variables (for example `DISABLE_AUTOUPDATER=1`) and the stored keys.
No D-Bus, display or SSH agent is passed.

When stdin is a terminal the agent gets its own pseudo-terminal: kwick-agents relays the input and output and window size changes, so
nothing inside the sandbox can push keystrokes into your terminal (TIOCSTI). Without a terminal `bwrap --new-session` is used.

Opt-outs: `kwick-agents sandbox NAME off` (per agent), `kwick-agents run --no-sandbox NAME` (once), `kwick-agents network NAME off` or
`run --offline`. GPU devices (`/dev/dri`, `/dev/kfd`, `/dev/nvidia*`) are given to Ollama by default and to others with `"gpu": true` in
the profile file. Extra folders go in the profile file (`"rw": ["~/notes"]`).

Install steps are sandboxed as well: `npm ci`, `uv` and `git clone` run with only the install folder and their cache writable, and npm
install scripts run without network.

## Keys

```
kwick-agents key set claude-code ANTHROPIC_API_KEY        # prompts without echo
printf '%s\n' "$KEY" | kwick-agents key set shared OPENROUTER_API_KEY
kwick-agents key list --json                               # names and backend, never values
```

`shared` keys go to every agent; an agent's own key with the same name wins. On the desktop the values are stored with `secret-tool`
in the Secret Service (`service=kwick-agents agent=NAME var=VAR`), which KWallet (Plasma 6) and GNOME Keyring both provide. Without a
Secret Service (headless, or `KWICK_AGENTS_KEYSTORE=file`) they go to `~/.config/kwick-agents/secrets.json` with mode 600 in a mode 700
folder. Keys reach the agent only as environment variables of its process.

## kwick-mcp

`kwick-mcp` speaks MCP over stdio (protocol versions 2025-11-25, 2025-06-18, 2025-03-26 and 2024-11-05). It is registered automatically
in the agent's own MCP configuration when an agent is installed (undo with `kwick-agents mcp disable NAME`, skip with `--no-mcp`):

| Agent | File | Entry |
|---|---|---|
| Claude Code | `~/.claude.json` | `mcpServers.kwickos` |
| Codex | `~/.codex/config.toml` | `[mcp_servers.kwickos]` |
| Gemini CLI | `~/.gemini/settings.json` | `mcpServers.kwickos` (Gemini enables MCP servers only in trusted folders) |
| opencode | `~/.config/opencode/opencode.json` | `mcp.kwickos` |
| oh-my-pi | `~/.omp/agent/mcp.json` | `mcpServers.kwickos` |
| Goose | `~/.config/goose/config.yaml` | `extensions.kwickos` |
| Hermes | `~/.hermes/config.yaml` | `mcp_servers.kwickos` |
| OpenClaw | `~/.openclaw/openclaw.json` | `mcp.servers.kwickos` (only while the file is plain JSON) |
| Cybara | its database | add `/usr/bin/kwick-mcp` under Settings > MCP Servers |

How identity works: `kwick-agents run` starts a broker on a private socket (mode 600, in `$XDG_RUNTIME_DIR/kwick-agents`) and binds it into
the sandbox at `/run/kwick-mcp.sock`. The agent starts `/usr/bin/kwick-mcp`, which only relays to that socket, so the broker outside the
sandbox knows which agent is asking and the agent cannot claim another name. Outside a sandbox `kwick-mcp` finds the broker of the
`kwick-agents run` it was started under (environment or parent processes); any other client is the agent `external`, or the name given
with `--agent`.

Tools and the capability each needs:

| Tool | Capability | Default |
|---|---|---|
| `system_info`, `permissions_get`, `packages_installed`, `packages_search`, `packages_updates`, `snapshots_list`, `settings_get`, `apps_list`, `agents_list` | `system.read` | allow |
| `files_list`, `files_read` | `files.read` | allow |
| `files_write` | `files.write` | ask |
| `notify` | `notify` | allow |
| `settings_set` | `settings.write` | ask |
| `apps_launch` | `apps.launch` | ask |
| `screenshot` | `screen.capture` | ask |
| `packages_install`, `system_upgrade` | `packages.manage` | ask |
| `snapshots_create` | `snapshots.manage` | ask |

File tools work only below the folder the agent was started in and folders granted with `kwick-agents folders NAME add PATH`; paths are
resolved through symlinks before the check.

"ask" opens a dialog with Allow once, Always allow and Deny: `kdialog` on KDE, `zenity` elsewhere, a notification with actions
(`notify-send --wait`) as the last resort. Without a desktop the request waits 90 seconds (`KWICK_AGENTS_CONSENT_WAIT`) for an answer from
`kwick-agents consent` in another terminal. Always allow stores `allow` in `grants.json`. Privileged tools then run
`pkexec /usr/lib/kwick/agents/kwick-agents-priv`, so polkit asks for an administrator password as a second, independent confirmation;
without polkit they use `sudo -n` when that works and otherwise tell the agent which command the user should run.

`snapshots_*` call `kwick-snapshot list --json` and `kwick-snapshot create TEXT` when kwick-snapshot is installed.

## Stable JSON for other programs

The Store app and Settings > Agents use these outputs. Fields are only ever added; `schema` changes if one is removed or changes meaning.

`kwick-agents list --json`:

```json
{
  "schema": 1,
  "arch": "amd64",
  "catalog_updated": "2026-11-20",
  "agents": [
    {
      "name": "claude-code", "title": "Claude Code", "kind": "agent", "vendor": "Anthropic",
      "description": "...", "homepage": "https://...", "source": "https://...", "license": "...",
      "version": "2.1.323",
      "supported": true, "unsupported_reason": "",
      "installed": true, "installed_version": "2.1.323", "scope": "user", "update_available": false,
      "commands": ["claude"], "keys": ["ANTHROPIC_API_KEY"], "keys_set": ["ANTHROPIC_API_KEY"],
      "sandbox": true, "network": true, "mcp_supported": true, "mcp_enabled": true,
      "download_size": 362435088, "runtime": ""
    }
  ]
}
```

`kind` is `agent`, `local-models` or `runtime`. `unsupported_reason`, `installed_version`, `scope`, `download_size` and `runtime` are
omitted when empty. `info NAME --json` adds `method`, `verify`, `upstream_install`, `asset` (`url`, `sha256`, `size`, `format`), `git`,
`commit`, `install_dir`, `shims`, `profile`, `home_paths`, `ports`, `mcp_config`, `first_run`, `notes`, `grants`, `folders`.

`install`, `remove` and `update` print progress on stderr and exit 0 on success, 1 when one of the names failed, 2 for usage errors.
Without root they act on the calling user's installs and need no password. `update --json` prints
`{"schema":1,"updated":[{"name","from","to","scope","ok","error"}]}`. A GUI should run them in a terminal or read stderr for progress.

Other JSON outputs: `grants --json` (`capabilities` and `agents.NAME.caps/folders`), `key list --json` (`backend`, `keys[].agent/var/backend`),
`audit --json` (`path`, `entries[]` with `time`, `agent`, `client`, `tool`, `capability`, `decision`, `ok`, `summary`, `error`),
`consent list --json` (`pending[]` with `id`, `agent`, `capability`, `detail`, `time`, `expires`), `mcp status --json`, `mcp tools --json`,
`doctor --json` (`ok`, `checks[]`).

## JSON output of the other kwick tools

| Command | Since |
|---|---|
| `kwick-update status --json` | existing |
| `kwick-kernel status --json`, `kwick-kernel list --json` | existing |
| `kwick-bluetooth json`, `kwick-bluetooth status --json` | `json` existing, `status --json` new (same output) |
| `kwick-layout status [--json]` | new: `{"layout","appearance","radius","desktop"}` |
| `kwick-desktop list --json` | new: `{"desktops":[{"name","session","installed","default"}]}` |
| `kwick-gpu status --json` (or `kwick-gpu --json`) | new: `{"vendors","cards":[{"card","vendor","driver"}],"arch","packages","i386","uinput"}` |
| `kwick-vpn list --json`, `kwick-vpn status --json` | new: `{"profiles":[...]}`, `{"connected":[...],"other_tunnels":[...]}` |
| `kwick-storage status --json` | new: `{"modules":[{"name","state","description","note"}]}`; `--machine` unchanged |

The human-readable output of every command is unchanged.

## Settings > Agents

`desktop/rootfs/usr/share/kwick/settings/PageAgents.qml` lists the installed agents with their sandbox, network and MCP switches, the
permission level of each capability, granted folders, stored key names (new keys are typed into a password dialog, never on a command
line), pending permission requests and the recent audit log. It reads everything from `helpers/agents.sh`, which calls the JSON
commands above.

## Building

`scripts/mkagentspkg.sh` builds `src/kwick-agents` (Go, standard library plus `klauspost/compress` for zstd) for amd64, arm64 and riscv64
and packages `kwick-agents_VERSION_ARCH.deb` with `desktop/agents/rootfs`. The release workflow already runs it in `kwick-builder`.
`tools/vmlab/buildrepo.sh` runs it when a Go toolchain is present; otherwise build the package with `kwick-builder` and pass it in
`EXTRA_DEBS`.

Package relations: `Depends: bubblewrap, ca-certificates, libstdc++6, libgomp1` (Node.js, llama.cpp and Ollama need the two C++ runtime
libraries), `Recommends: libsecret-tools, sudo`, `Suggests: git, zenity | kdialog, libnotify-bin`. Hermes needs `git`.
