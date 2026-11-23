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
   `snapshots_create`, `settings_set`, `apps_launch`, `files_write`, `screenshot` and computer control tools ask the user for you.
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
| `system_info`, `permissions_get`, `packages_installed`, `packages_search`, `packages_updates`, `snapshots_list`, `settings_list`, `settings_get`, `apps_list`, `agents_list` | `system.read` | allow |
| `files_list`, `files_read` | `files.read` | allow (project folder and granted folders only) |
| `files_write` | `files.write` | ask |
| `notify` | `notify` | allow |
| `settings_set` | `settings.write` | ask; settings marked `privileged` also ask for an administrator password |
| `apps_launch` | `apps.launch` | ask |
| `screenshot` | `screen.capture` | ask (covered by an active computer control session) |
| `screen_info`, `pointer_move`, `pointer_click`, `pointer_drag`, `scroll`, `key_press`, `type_text`, `windows_list`, `window_focus`, `window_close`, `window_move_resize`, `clipboard_get`, `clipboard_set`, `computer_release` | `computer.control` | ask once per session |
| `packages_install`, `system_upgrade` | `packages.manage` | ask, then an administrator password |
| `snapshots_create` | `snapshots.manage` | ask, then an administrator password |

"ask" shows a dialog on the desktop. On a headless machine the request waits up to 90 seconds for the user to answer with
`kwick-agents consent` in another terminal. Every call and decision is written to `~/.local/state/kwick-agents/audit.jsonl`.

## Changing settings

Do not edit files in `~/.config` or run `kwriteconfig6`, `gsettings` or `kwick-*` commands to change the desktop. Use the settings
tools; they call the same backends as KwickOS Settings and check every value first.

1. `settings_list` returns every setting with `key`, `group`, `type` (`enum`, `bool`, `int`, `number`, `string`, `path`, `list`),
   the allowed `values` or `min`/`max`, `privileged`, `available` (false with a `reason` when the current desktop lacks it) and the
   current `value`. Pass `group` (appearance, dock, effects, desktop, terminal, display, sound, notifications, network, power, touch,
   updates) or `keys` to read less.
2. `settings_set {"settings": {"appearance": "light", "dock.size": 56}}` changes up to 20 settings in one request, so the user
   answers one dialog. Unknown keys and invalid values are rejected before anything changes. The answer has `changed`, `failed` and
   `now` (the values read back).
3. Settings marked `privileged` (`desktop.default_session`, `shell.login`, `updates.*`) also ask for an administrator password through
   polkit. Without a desktop they fail with the command the user should run.

Useful keys: `layout` (macos, windows, linux), `appearance`, `accent`, `wallpaper` (absolute path of an image), `corner_radius`, `fonts`,
`dock.position`, `dock.size`, `dock.autohide`, `dock.apps` (desktop ids from `apps_list`, in order), `effects.preset`, `effects.<name>`,
`desktop.default_session`, `desktop.shell`, `shell.login`, `shell.prompt`, `display.night_light`, `display.brightness`, `display.scale`,
`sound.volume`, `sound.mute`, `notifications.do_not_disturb`, `network.wifi`, `bluetooth.enabled`, `nearby.visibility`, `nearby.name`,
`power.profile`, `touch.tablet_mode`, `updates.check`, `updates.install_security`, `updates.interval_hours`. Layout and appearance
changes take 10 to 60 seconds; do not repeat the request while it runs.

## Using the desktop (computer use)

On the desktop edition you can see the screen and use the mouse, keyboard, windows and clipboard. The first `computer.control` tool
call asks the user once; the approval lasts for your run (at most 60 minutes, ended after 15 idle minutes). On KDE Plasma and GNOME
the system also shows its own remote control dialog the first time; it remembers the answer. While you are in control the user sees a
capsule at the top of the screen with a Stop button and can press Meta+Alt+Escape at any time; the capsule is part of the screen
you see in screenshots and you cannot click it. When a tool says the session ended, stop using the
desktop and tell the user.

The loop that works best:

1. `screenshot` (default 1280x800 at most). The answer gives `width`, `height`, `scale` and `origin_x/origin_y`. Coordinates you pass to
   pointer tools are pixels of that image (`"space": "image"`, the default after a screenshot); use `"space": "screen"` for desktop
   coordinates from `screen_info` or `windows_list`. For small text take a `region` screenshot of the area at full size.
2. Act: `pointer_click {"x": 412, "y": 230}`, `type_text {"text": "..."}`, `key_press {"keys": "ctrl+s"}` or a list
   (`{"keys": ["ctrl+a", "delete"]}`), `scroll {"x": 640, "y": 400, "dy": 3}`, `pointer_drag`.
3. `screenshot` again to check the result before the next step. Do not chain many clicks blindly.

Windows: `windows_list` gives `id`, `title`, `app`, position, size, `active` and `protected`, topmost first. Prefer `window_focus` to
clicking on a window, `window_move_resize` to dragging title bars, and `apps_launch` to hunting for icons. Keyboard shortcuts are often
more reliable than clicks (`ctrl+l` for a browser address bar, `ctrl+n`, `alt+f4`). `clipboard_set` followed by `key_press ctrl+v`
(`ctrl+shift+v` in terminals) pastes long text faster than typing it; `type_text` already pastes characters outside ASCII that way and
restores the clipboard.

Limits you will hit, by design:

* Password, unlock and permission prompts (polkit, KWallet, GNOME Keyring, pinentry, SSH askpass, the lock screen, the KwickOS consent
  dialog, the system remote control dialog) and KwickOS Settings are protected: typing, key presses and clicks are refused while one
  is focused or under the pointer, and window tools refuse them. Ask the user to answer such prompts. Change settings with
  `settings_set`.
* At most 15 input actions per second and 2000 characters per `type_text` call.
* GNOME offers no window list to other programs; `windows_list` and `window_*` work on KDE Plasma, Hyprland and sway.
* Call `computer_release` when the task is done.

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
| `~/.local/state/kwick-agents/audit.jsonl` | audit log (every tool call, including each click and key press) |
| `/var/log/kwick-agents-priv.log` | privileged actions carried out for agents (root only) |
| `/usr/lib/kwick/agents/catalog.json` | the agent catalog with pinned versions and checksums |
