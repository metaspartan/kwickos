# Operating KwickOS: a guide for AI agents

You are running on KwickOS, a small Linux distribution that is binary compatible with Debian 13 "trixie" (glibc, amd64, arm64 and
riscv64). Read this before you change anything on the machine. A copy is served by the KwickOS MCP server as the resource
`kwickos://docs/agents`.

## What is different from Debian

| Area | KwickOS | Notes |
|---|---|---|
| PID 1 | `kinit` | `systemctl` and `journalctl` exist as compatibility commands; unit files in `/usr/lib/systemd/system` are honoured for simple services. There is no full systemd. |
| Base tools | BusyBox | `ls`, `sed`, `awk`, `tar`, `grep` are BusyBox applets. GNU-only flags may be missing; install `coreutils`, `gawk`, `grep` or `tar` with apt if you need them. |
| Packages | `kpkg` | `apt`, `apt-get`, `apt-cache`, `dpkg` and `dpkg-query` are kpkg. Debian 13 packages install unchanged. `apk add` installs Alpine (musl) packages into a separate prefix. |
| Editions | headless or desktop | Desktop: KDE Plasma, GNOME or Hyprland with the `kwick-*` desktop tools. Check with `system_info` (field `edition`) or `test -x /usr/bin/kwick-settings`. |
| Updates | `kwick-update` | Never run `apt full-upgrade` on your own. Kernels are tried once and roll back automatically (`kwick-kernel`). |

## Rules

1. Prefer the MCP tools of `kwick-mcp` over shell commands for anything outside your project folder. They are permissioned, audited
   and they work inside the sandbox.
2. Ask before you install, remove or upgrade software, and before you change settings. The `packages_install`, `system_upgrade`,
   `snapshots_create`, `settings_set`, `apps_launch`, `files_write` and `screenshot` tools ask the user for you.
3. If a tool answers "Denied", do not try another route to the same result. Tell the user which capability you need; they can
   change it in Settings > Agents or with `kwick-agents grant AGENT CAPABILITY allow`.
4. Take a snapshot (`snapshots_create`) before risky system changes when `kwick-snapshot` is installed.
5. Never print, log or copy API keys. They are in your environment because the user stored them with `kwick-agents key set`.
6. Use `--json` on `kwick-*` commands and parse the result; never scrape the human-readable output.

## Your sandbox

Agents installed with `kwick-agents` run in a bubblewrap sandbox unless the user turned it off (`KWICK_AGENT_SANDBOX=1` in your
environment means you are inside one):

* Read-only: `/usr`, `/etc`, `/opt`, `/sys`. You cannot change the system from inside; use the MCP tools.
* Read-write: the folder you were started in (the project) and your own configuration folder (for example `~/.claude`, `~/.codex`,
  `~/.gemini`, `~/.config/opencode`, `~/.omp`, `~/.hermes`).
* Your home directory is private to you. Other files of the user are not visible.
* `/tmp` is private and empty at start. The network is shared with the host unless the user started you with `--offline`.
* No D-Bus, no display, no other processes of the user. `kill`, `ps` and `top` only see your own processes.

The MCP server is reachable inside the sandbox through `/usr/bin/kwick-mcp` (it connects to `/run/kwick-mcp.sock`, which belongs to
the `kwick-agents run` process that started you). Your identity is the agent name you were started as; you cannot change it.

## MCP tools

| Tool | Capability | Default |
|---|---|---|
| `system_info`, `permissions_get`, `packages_installed`, `packages_search`, `packages_updates`, `snapshots_list`, `settings_get`, `apps_list`, `agents_list` | `system.read` | allow |
| `files_list`, `files_read` | `files.read` | allow (project folder and granted folders only) |
| `files_write` | `files.write` | ask |
| `notify` | `notify` | allow |
| `settings_set` | `settings.write` | ask |
| `apps_launch` | `apps.launch` | ask |
| `screenshot` | `screen.capture` | ask |
| `packages_install`, `system_upgrade` | `packages.manage` | ask, then an administrator password |
| `snapshots_create` | `snapshots.manage` | ask, then an administrator password |

"ask" shows a dialog on the desktop. On a headless machine the request waits up to 90 seconds for the user to answer with
`kwick-agents consent` in another terminal. Every call and decision is written to `~/.local/state/kwick-agents/audit.jsonl`.

## Command line tools with JSON output

| Command | Output |
|---|---|
| `kwick-agents list --json`, `info NAME --json`, `status --json` | agent catalog, installed versions, sandbox, keys (names only) |
| `kwick-agents grants --json`, `audit --json`, `mcp tools --json`, `doctor --json` | permissions, audit log, MCP tools, health checks |
| `kwick-update status --json` | last update check, settings, running task (read only, no root needed) |
| `kwick-kernel status --json`, `kwick-kernel list --json` | boot path, running/default/previous kernel, trial state |
| `kwick-layout status --json` | desktop layout, appearance, corner radius, session |
| `kwick-desktop list --json` | installed desktop sessions and the default one |
| `kwick-gpu status --json` | detected GPUs and drivers |
| `kwick-vpn list --json`, `kwick-vpn status --json` | VPN profiles and connections |
| `kwick-storage status --json` | storage modules |
| `kwick-bluetooth json` | Bluetooth adapter and devices |

Commands that change the system (`kwick-update upgrade`, `kwick-kernel try`, `apt install`) need root. Do not use `sudo` yourself
unless the user asked you to; use the MCP tools so the user sees a prompt.

## Installing software for a task

* Debian packages: `packages_search`, then `packages_install` (the user approves).
* Python tools: use a virtual environment in the project (`uv venv`, `uv pip install`). `uv` is in your PATH when you were installed
  with a Python runtime; otherwise ask the user to `kwick-agents install uv`.
* Node.js tools: `npx` works when you run on the kwick-agents Node.js runtime; install into the project, not globally.
* Other agents or local models: `kwick-agents install NAME` (per user, no root). See `kwick-agents list`.

## Files and paths

| Path | What |
|---|---|
| `/etc/kwick-release`, `/etc/os-release` | KwickOS version |
| `~/.config/kwick/` | desktop layout, appearance, dock (owned by the `kwick-*` tools; change them through `settings_set`) |
| `~/.local/share/kwick-agents/` | agents installed for this user, their private homes and runtimes |
| `~/.config/kwick-agents/` | grants, sandbox profiles, key index (and `secrets.json` mode 600 when there is no Secret Service) |
| `~/.local/state/kwick-agents/audit.jsonl` | audit log |
| `/var/log/kwick-agents-priv.log` | privileged actions carried out for agents (root only) |
| `/usr/lib/kwick/agents/catalog.json` | the agent catalog with pinned versions and checksums |
