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
   updates, snapshots, files, notifications, every setting of KwickOS Settings, apps, screenshots and computer use (pointer, keyboard,
   windows and clipboard). Every request is checked against per-agent grants, risky ones ask the user, and everything goes to an audit
   log.

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
kwick-agents control [list|stop [ID|NAME]] [--json]
kwick-agents mcp serve [--agent NAME] | mcp enable NAME | mcp disable NAME | mcp status [--json] | mcp tools [--json]
kwick-agents doctor [--json]
kwick-agents inference status|doctor|gpu|install|remove|update|models|model|use|fit|service|connect|disconnect|endpoint|key ...
kwick-agents run --local aider|claude-code [-- ARGS]
```

`kwick-agents inference` (also `kwick-inference`) serves local models: llama.cpp for the GPU of this machine on
`http://127.0.0.1:11435/v1` (and `/v1/messages`) with a key and the model name `local`, curated sha256-pinned models with fit verdicts,
a sandboxed service that is off by default, and `connect` for Cybara, opencode, Codex, Goose, Hermes, OpenClaw and oh-my-pi. See
[INFERENCE.md](INFERENCE.md).

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
| `cybara` | Cybara | 1.0.2596 | `cybara-v*-linux-*-cli` from GitHub, sha256 equal to the vendor `.sha256` and `checksums.txt` | yes | yes | no build |
| `claude-code` | Claude Code, Anthropic | 2.1.323 (stable channel) | binary from `downloads.claude.ai/claude-code-releases`, sha256 equal to the vendor `manifest.json`; auto-updater off | yes | yes | no build |
| `codex` | Codex CLI, OpenAI | 0.171.0 | `codex-*-unknown-linux-musl.tar.gz` from GitHub, sha256 equal to the release digest | yes | yes | no build |
| `gemini-cli` | Gemini CLI, Google | 0.70.0 | `gemini-cli-bundle.zip` from GitHub, sha256; runs on the Node.js runtime | yes | yes | yes |
| `opencode` | opencode, Anomaly | 1.19.6 (v1 line) | `opencode-linux-*.tar.gz` from GitHub, sha256 equal to the release digest | yes | yes | no build |
| `omp` | oh-my-pi, Stencil Labs (`can1357/oh-my-pi`) | 19.0.1 | `omp-linux-*` from GitHub, sha256 equal to the vendor `SHA256SUMS.txt` | yes | yes | no build |
| `openclaw` | OpenClaw | 2026.11.6 | `npm ci` from a `package-lock.json` shipped by KwickOS: the sha512 of every tarball (439) is checked; install scripts run sandboxed without network | yes | yes | native modules missing |
| `hermes` | Hermes Agent, Nous Research | 0.23.3 | `git clone` of tag `v0.23.3`, commit `caafe538` checked; `uv sync --frozen` with the hashes in the project's `uv.lock`; needs `git` | yes | yes | not supported upstream |
| `aider` | Aider | 0.86.2 | `uv pip install --require-hashes` from a hash-locked requirements file shipped by KwickOS (109 packages), Python 3.12 | yes | yes | no wheels |
| `goose` | Goose, Agentic AI Foundation | 1.60.2 | `goose-*-unknown-linux-gnu.tar.bz2` from GitHub, sha256 equal to the release digest | yes | yes | no build |
| `ollama` | Ollama | 0.40.16 | `ollama-linux-*.tar.zst` from GitHub (about 1.5 GB), sha256 equal to the vendor `sha256sum.txt`; no service, no extra user | yes | yes | no build |
| `llama-cpp` | llama.cpp, ggml-org | b12600 | `llama-b12600-bin-ubuntu-*.tar.gz` (CPU) from GitHub, sha256 equal to the release digest | yes | yes | no build |
| `inference` | Local models: llama.cpp, ggml-org | b12648 | one archive per backend (`cpu`, `vulkan`, `cuda12`, `cuda13` with NVIDIA's cudart and cuBLAS runtime pack, `rocm`) from GitHub, sha256 equal to the release digest; only the backend this machine needs is downloaded; managed with `kwick-agents inference` ([INFERENCE.md](INFERENCE.md)) | all five | cpu, vulkan, cuda13 | no build |

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
| `/usr/bin/kwick-agents`, `/usr/bin/kwick-mcp`, `/usr/bin/kwick-cua-driver` | the program (one binary; the other two are symlinks) |
| `/usr/lib/kwick/agents/indicator.qml` | the computer control indicator |
| `/usr/lib/kwick/agents/catalog.json`, `locks/` | catalog and lock files |
| `/usr/lib/kwick/agents/kwick-agents-priv` | the only program kwick-mcp runs as root: `install PKG...`, `upgrade SCOPE`, `snapshot TEXT`, `session DESKTOP`, `login-shell SHELL`, `auto-update KEY on\|off`, `auto-update interval HOURS` |
| `/usr/share/applications/org.kwickos.agents.desktop` | app id `org.kwickos.agents`: the name shown in the system remote control dialog and on notifications; lets kwick-agents use KWin's screenshot interface |
| `/usr/share/polkit-1/actions/org.kwickos.agents.policy` | polkit action for it (`auth_admin`, never cached) |
| `~/.local/share/kwick-agents/pkgs/NAME/VERSION` | installed agents |
| `~/.local/share/kwick-agents/runtimes/`, `python/` | Node.js, uv, Bun and uv's Python builds |
| `~/.local/share/kwick-agents/home/NAME` | the agent's private home inside the sandbox |
| `~/.local/state/kwick-agents/state.json` | installed versions |
| `~/.local/state/kwick-agents/audit.jsonl` | audit log (JSON lines, rotated at 5 MB) |
| `~/.local/state/kwick-agents/remote-desktop.token` | restore token of the remote desktop portal (mode 600), so the system dialog is shown once |
| `$XDG_RUNTIME_DIR/kwick-agents/control/ID.json` | one file per active computer control session; deleting it ends the session |
| `~/.config/kwick-agents/grants.json` | permissions and folders per agent |
| `~/.config/kwick-agents/agents/NAME.json` | sandbox profile overrides (`sandbox`, `network`, `gpu`, `project`, `rw`, `ro`, `env`) |
| `~/.config/kwick-agents/keys.json` | names of the stored keys and their backend (no values) |
| `~/.config/kwick-agents/secrets.json` | values, mode 600, only when there is no Secret Service |
| `/opt/kwick-agents`, `/var/lib/kwick-agents`, `/etc/kwick-agents` | the same for `--system` installs; `/etc/kwick-agents/grants.json` can force `deny` for an agent or `*` |
| `/var/log/kwick-agents-priv.log` | privileged actions done for agents |
| `/usr/bin/kwick-inference` | symlink to kwick-agents: the `inference` commands |
| `/usr/lib/kwick/agents/inference-models.json` | curated local models (sha256 and commit pinned) |
| `~/.local/share/kwick-inference/models/`, `~/.config/kwick-inference/` | local models; endpoint, chosen model and connected agents |
| `/usr/lib/systemd/system/kwick-inference.service`, `/usr/lib/systemd/user/kwick-inference.service`, `/usr/lib/sysusers.d/kwick-inference.conf` | the machine-wide and per-user service units (disabled by default) |

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
| Cybara | `~/.cybara/plugins/kwickos/cybara-plugin.json` and `mcp.json` | a local Cybara plugin contributing the stdio server `kwickos` (shown as "KwickOS: kwickos"); `$CYBARA_HOME` and `~/.cybara_home` are honoured |

Cybara reads MCP servers only from its database and starts none by itself. A local plugin is the one file-based route it has: at
gateway start it adds the plugin's servers to the database. kwick-agents writes that plugin and then starts the server through the
gateway API (`POST /api/mcp/ID/start` on `http://127.0.0.1:4269`, with `~/.cybara/api_key` when the gateway requires a key): right away
when the gateway is running, and on every `kwick-agents run cybara` as soon as the gateway answers (polled for three minutes). Nothing
has to be added by hand.

Cybara also has its own `computer_use` tool. It drives an external "cua-driver" over MCP (`cua-driver mcp`): on Linux it would
download trycua's `cua-driver-rs` 0.7.1 into `~/.cybara/runtime/cua-driver/`, which cannot see a Wayland session from inside the
sandbox and would bypass KwickOS's consent. Cybara lets the driver be replaced with `CYBARA_CUA_DRIVER_CMD`, so the catalog sets it to
`/usr/bin/kwick-cua-driver` (a link to kwick-agents). That driver speaks the cua-driver tool set Cybara uses (`list_windows`,
`list_apps`, `screenshot`, `get_window_state`, `bring_to_front`, `move_cursor`, `click`, `double_click`, `right_click`, `scroll`,
`drag`, `type_text`, `hotkey`, `press_key`) and forwards each call to the kwick-mcp broker of the run as the agent `cybara`, so Cybara's
own computer use goes through the same `computer.control` consent, indicator, protected-window checks, rate limits, revoke and audit
log. Window ids are numbered per driver session, and click coordinates are pixels of the last window screenshot, as cua-driver does.
Accessibility element indexes (`element_index`, `set_value`) are not available; Cybara falls back to coordinates. Cybara needs nothing
else: no X server, no ydotool and no extra sandbox binds, because input and screenshots happen in the broker outside the sandbox.
Cybara can also use the kwick-mcp tools directly (they are registered through the plugin above).

How identity works: `kwick-agents run` starts a broker on a private socket (mode 600, in `$XDG_RUNTIME_DIR/kwick-agents`) and binds it into
the sandbox at `/run/kwick-mcp.sock`. The agent starts `/usr/bin/kwick-mcp`, which only relays to that socket, so the broker outside the
sandbox knows which agent is asking and the agent cannot claim another name. Outside a sandbox `kwick-mcp` finds the broker of the
`kwick-agents run` it was started under (environment or parent processes); any other client is the agent `external`, or the name given
with `--agent`.

Tools and the capability each needs:

| Tool | Capability | Default |
|---|---|---|
| `system_info`, `permissions_get`, `packages_installed`, `packages_search`, `packages_updates`, `snapshots_list`, `settings_list`, `settings_get`, `apps_list`, `agents_list` | `system.read` | allow |
| `files_list`, `files_read` | `files.read` | allow |
| `files_write` | `files.write` | ask |
| `notify` | `notify` | allow |
| `settings_set` | `settings.write` | ask |
| `apps_launch` | `apps.launch` | ask |
| `screenshot` | `screen.capture` | ask |
| `screen_info`, `pointer_move`, `pointer_click`, `pointer_drag`, `scroll`, `key_press`, `type_text`, `windows_list`, `window_focus`, `window_close`, `window_move_resize`, `clipboard_get`, `clipboard_set`, `computer_release` | `computer.control` | ask (once per session) |
| `packages_install`, `system_upgrade` | `packages.manage` | ask |
| `snapshots_create` | `snapshots.manage` | ask |
| `inference_status`, `inference_models` | `system.read` | allow |
| `inference_start`, `inference_stop`, `inference_pull` | `inference.manage` | ask |

The resource `kwickos://docs/inference` serves [INFERENCE.md](INFERENCE.md).

File tools work only below the folder the agent was started in and folders granted with `kwick-agents folders NAME add PATH`. Paths
are resolved through symlinks before the check, and the file is then opened beneath the granted folder with `os.Root` (openat
without following links out of it), so a symlink swapped in after the check, or a dangling link, cannot lead outside; the opened file
descriptor is checked again before anything is written. kwick-agents' own folders (`~/.config/kwick-agents`,
`~/.local/state/kwick-agents`, `~/.local/share/kwick-agents`, the runtime folder and the `--system` equivalents) are never writable
through kwick-mcp, even when a granted folder contains them, and `secrets.json` is never readable.

### Settings

`settings_list` returns a typed schema of 60 settings: every page of KwickOS Settings that a user changes, plus the quick settings of
the Control Center. Each entry has `key`, `group`, `title`, `type` (`enum`, `bool`, `int`, `number`, `string`, `path`, `list`), the
allowed `values` or `min`/`max`/`step`, `privileged`, `desktops`, `available` with a `reason`, and the current `value`.
`settings_get` reads values by `keys` or `group`; `settings_set {"settings": {...}}` changes up to 20 at once (the old
`{"appearance": ..., "layout": ...}` form still works). Every value is validated against the schema before the consent dialog;
commands are run with argument vectors, never through a shell.

| Group | Keys | Backend |
|---|---|---|
| appearance | `layout`, `appearance`, `corner_radius`, `accent`, `highlight`, `sidebar_icons`, `wallpaper_tinting`, `wallpaper`, `fonts` | `kwick-layout` (`accent` falls back to `kwriteconfig6`/`plasma-apply-colorscheme`/`gsettings` without it), `plasma-apply-wallpaperimage`/`gsettings`/`swaymsg`/`hyprctl hyprpaper`, `kwick-fonts apply` |
| dock | `dock.position`, `dock.size`, `dock.autohide`, `dock.floating`, `dock.magnify`, `dock.apps` | `kwick-dock` (`sync` for the app list), then `kwick-dock apply` |
| effects | `effects.preset`, `effects.desktop_switch`, `effects.alt_tab`, `effects.open_close`, `effects.open_close_duration`, `effects.wobbly_amount`, `effects.wobbly_sway`, `effects.flame_style`, `effects.flame_height`, `effects.cube_depth`, `effects.flip_style`, `effects.wobbly`, `lamp`, `blur`, `transparency`, `sheet`, `dim`, `overview`, `cube`, `liquidglass` | `kwick-effects` |
| desktop | `desktop.default_session` (privileged), `desktop.shell` | `kwick-agents-priv session` (runs `kwick-desktop switch`), `kwick-desktop shell` (only for installed shells of the login session) |
| terminal | `shell.login` (privileged), `shell.prompt` | `kwick-agents-priv login-shell` (runs `kwick-shell --user` for the calling user only), `kwick-shell prompt` |
| display | `display.night_light`, `display.brightness`, `display.scale` | KWin `NightColor` with `kwriteconfig6 --notify` or GNOME `night-light-enabled`; PowerDevil `org.kde.ScreenBrightness` or `brightnessctl`; `kscreen-doctor`, `swaymsg output`, `hyprctl keyword monitor` |
| sound | `sound.volume`, `sound.mute` | `wpctl` on the default sink |
| notifications | `notifications.do_not_disturb` | Plasma `plasmanotifyrc [DoNotDisturb] Until` (what the Control Center's Focus writes), GNOME `show-banners` |
| network | `network.wifi`, `bluetooth.enabled`, `nearby.visibility`, `nearby.name` | `nmcli radio wifi`, `kwick-bluetooth power`, `kwick-nearby --set` |
| power | `power.profile` | power-profiles-daemon over D-Bus (`ActiveProfile`), `powerprofilesctl` as fallback |
| touch | `touch.tablet_mode`, `touch.on_screen_keyboard`, `touch.rotation` | `kwick-touch` |
| updates | `updates.check`, `updates.download`, `updates.install_system`, `updates.install_security`, `updates.install_apps`, `updates.notify`, `updates.interval_hours` (all privileged) | `kwick-agents-priv auto-update` (runs `kwick-update auto set` or `kwick-update auto interval`) |

Left out on purpose: Privacy & Security (Flatpak permissions), VPN profiles, GPU driver installs, storage pools, gaming session
switches and Wi-Fi passwords. An agent should not be able to widen app permissions or route traffic; those stay with the user.

### Computer use

The `computer.control` tools let an agent use the desktop like a person. How they work per desktop:

| | KDE Plasma (Wayland) | GNOME | sway | Hyprland |
|---|---|---|---|---|
| Pointer and keyboard | xdg-desktop-portal RemoteDesktop with ScreenCast streams (absolute positions), `persist_mode` 2 and a restore token | same portal | `swaymsg seat - cursor`, `wtype` | `hyprctl dispatch movecursor`, `wlrctl pointer`, `wtype`; `ydotool` for drags when present |
| Windows | KWin scripts over D-Bus (`workspace.stackingOrder`, `activeWindow`, `frameGeometry`, `closeWindow`) | not available | `swaymsg -t get_tree`, `[con_id=N]` commands | `hyprctl clients`, `focuswindow`, `movewindowpixel` |
| Screens | KWin `workspace.screens` | portal streams | `swaymsg -t get_outputs` | `hyprctl monitors` |
| Screenshot | KWin `ScreenShot2.CaptureWorkspace` (allowed by `org.kwickos.agents.desktop`), Spectacle as fallback | `gnome-screenshot` | `grim` | `grim` |
| Clipboard | Klipper over D-Bus | wl-clipboard | wl-clipboard | wl-clipboard |
| Stop hotkey | Meta+Alt+Escape (KWin script shortcut) | the system's screen sharing indicator | Meta+Alt+Escape (`bindsym`) | Meta+Alt+Escape (`bind`) |

`screenshot` scales the capture to fit `max_width` x `max_height` (default 1280x800, area-averaged) and returns PNG or JPEG with the
mapping to desktop coordinates; it can capture a `region`. Pointer tools take coordinates in the pixels of the last screenshot by
default, so an agent can click what it sees without arithmetic. `type_text` sends keysyms; on the portal backend characters outside
ASCII are pasted through the clipboard (`ctrl+shift+v` in terminals) and the clipboard is restored. `wtype` and `wlrctl` are in
`desktop/packages.list` for the tiling sessions.

Safety design:

* **Consent per session.** The first `computer.control` call opens the consent dialog (Allow once covers the session, Always allow
  stores `allow`). A session ends when the agent run ends (the broker stops), after 60 minutes (`KWICK_AGENTS_CONTROL_MINUTES`),
  after 15 idle minutes (`KWICK_AGENTS_CONTROL_IDLE_MINUTES`), when the agent calls `computer_release`, or when the user stops it. On
  KDE and GNOME the system remote control dialog is a second, independent approval the first time; its restore token is kept in
  `~/.local/state/kwick-agents/remote-desktop.token`.
* **Visible indicator.** While a session is active a floating capsule sits at the top centre of every screen, above all windows
  (`/usr/lib/kwick/agents/indicator.qml`, a wlr-layer-shell overlay run with `qml6`, on KDE Plasma, Hyprland and sway): the agent's
  initial on an accent-tinted badge with a pulsing "controlling" dot, "AGENT is using this computer", the end time and the hotkey,
  and a red-tinted Stop button with hover and pressed states. It follows the accent colour (`kdeglobals` AccentColor, GNOME
  accent-color, or the platform palette), light or dark appearance and the layout (capsule, Windows 11 corner radius and Selawik,
  Linux radius and Ubuntu Sans; below the menu bar on macOS and Linux, at the top edge on Windows). Agents cannot click, move or close
  it. Where layer-shell is missing (GNOME) a resident notification with a Stop action is shown instead; the portal adds its own
  screen sharing indicator. When the session ends a notification says why.
* **Revoke at any time.** The Stop button of the indicator, Meta+Alt+Escape (stops every session; Meta+Shift+Escape is taken by
  Plasma's "Disable Active Input Capture"), `kwick-agents control stop [ID|NAME]`, Stop in
  Settings > Agents, or closing the portal's screen sharing session. Each session is a file in `$XDG_RUNTIME_DIR/kwick-agents/control`
  that the broker checks twice a second; removing it ends the session.
* **Protected windows.** Before every pointer, key and typing action the window list is read (KWin, sway or Hyprland). Input is
  refused while a protected window is focused, clicks and drags are refused on a protected window, and window tools refuse to touch
  one. Protected: polkit agents, KWallet and GNOME Keyring prompts, pinentry and SSH askpass, lock screens and greeters, the portal
  dialogs, the KwickOS consent dialog, and KwickOS Settings (where grants are changed). A locked screen refuses all input. If the
  window list cannot be read on KDE, input is refused rather than sent blind.
* **Rate limits.** 15 input actions per second with a burst of 30, 2000 characters per `type_text`, 1 MB of clipboard text, 30
  wheel steps per scroll, 50 repeats per key press.
* **Audit.** Every call, including each click (with coordinates), key combination and the first 60 characters of typed text, and the
  start and end of every session with its reason and action count, goes to the audit log.

GNOME offers no way to list windows from outside the shell, so on GNOME the protected-window check is limited to the lock screen.
Treat granting `computer.control` like letting someone sit at the keyboard: an agent with it can do what you can do in an unlocked
session, except answering the prompts above.

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
`control list --json` (`sessions[]` with `id`, `agent`, `client`, `pid`, `started`, `expires`, `desktop`),
`consent list --json` (`pending[]` with `id`, `agent`, `capability`, `detail`, `time`, `expires`), `mcp status --json`, `mcp tools --json`,
`doctor --json` (`ok`, `checks[]`).

## JSON output of the other kwick tools

| Command | Since |
|---|---|
| `kwick-update status --json` | existing |
| `kwick-kernel status --json`, `kwick-kernel list --json` | existing |
| `kwick-bluetooth json`, `kwick-bluetooth status --json` | `json` existing, `status --json` new (same output) |
| `kwick-layout status [--json]` | new: `{"layout","appearance","radius","accent","highlight","sidebar","tint","desktop"}`; `kwick-layout colors --json` prints the derived accent, highlight and sidebar colours of both appearances |
| `kwick-desktop list --json` | new: `{"desktops":[{"name","session","installed","default"}]}` |
| `kwick-gpu status --json` (or `kwick-gpu --json`) | new: `{"vendors","cards":[{"card","vendor","driver"}],"devices":[{"index","vendor","name","pci","card","vram_mb","gtt_mb","compute_cap","driver","driver_version","unified","display"}],"ram_mb","memory_budget_mb","arch","packages","i386","uinput"}` |
| `kwick-agents inference status --json`, `models --json`, `fit ID --json`, `gpu --json` | new, schema 1, see [INFERENCE.md](INFERENCE.md) |
| `kwick-vpn list --json`, `kwick-vpn status --json` | new: `{"profiles":[...]}`, `{"connected":[...],"other_tunnels":[...]}` |
| `kwick-storage status --json` | new: `{"modules":[{"name","state","description","note"}]}`; `--machine` unchanged |

The human-readable output of every command is unchanged.

## Settings > Agents

`desktop/rootfs/usr/share/kwick/settings/PageAgents.qml` lists the installed agents with their sandbox, network and MCP switches, the
permission level of each capability (including computer control), agents that control the computer right now with a Stop
button, granted folders, stored key names (new keys are typed into a password dialog, never on a command
line), pending permission requests and the recent audit log. It reads everything from `helpers/agents.sh`, which calls the JSON
commands above.

## Building

`scripts/mkagentspkg.sh` builds `src/kwick-agents` (Go, standard library plus `klauspost/compress` for zstd) for amd64, arm64 and riscv64
and packages `kwick-agents_VERSION_ARCH.deb` with `desktop/agents/rootfs`. The release workflow already runs it in `kwick-builder`.
`tools/vmlab/buildrepo.sh` runs it when a Go toolchain is present; otherwise build the package with `kwick-builder` and pass it in
`EXTRA_DEBS`.

`src/kwick-agents` uses the standard library, `klauspost/compress` and `godbus/dbus` (portal, KWin, notifications, PowerDevil and
power-profiles-daemon). `desktop/Dockerfile` copies Breeze's `systemdialog` into the KwickOS look-and-feel packages before it removes
Breeze: without it every Plasma system dialog (the remote control and screen sharing portals among them) failed to load.

Package relations: `Depends: bubblewrap, ca-certificates, libstdc++6, libgomp1` (Node.js, llama.cpp and Ollama need the two C++ runtime
libraries), `Recommends: libsecret-tools, sudo`, `Suggests: git, zenity | kdialog, libnotify-bin`. Hermes needs `git`.
