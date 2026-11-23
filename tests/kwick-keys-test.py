import importlib.machinery
import importlib.util
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "desktop", "rootfs")
DATA = os.path.join(ROOT, "usr", "share", "kwick", "keys")
TMP = tempfile.mkdtemp(prefix="kwick-keys-test-")
os.environ["KWICK_KEYS_DATA"] = DATA
os.environ["XDG_CONFIG_HOME"] = os.path.join(TMP, "config")
os.environ["XDG_STATE_HOME"] = os.path.join(TMP, "state")
os.environ["XDG_RUNTIME_DIR"] = TMP

loader = importlib.machinery.SourceFileLoader("kwickkeys", os.path.join(ROOT, "usr", "bin", "kwick-keys"))
spec = importlib.util.spec_from_loader("kwickkeys", loader)
kk = importlib.util.module_from_spec(spec)
loader.exec_module(kk)

FAILS = []


def check(name, cond, detail=""):
    print("%s %s%s" % ("ok  " if cond else "FAIL", name, (" -- " + str(detail)) if detail and not cond else ""))
    if not cond:
        FAILS.append(name)


def parses(text, want, each=None):
    try:
        got = str(kk.parse(text, each))
    except kk.ChordError as e:
        got = "error: %s" % e
    check("parse %r -> %s" % (text, want), got == want, got)


def rejects(text, words, each=None):
    try:
        got = str(kk.parse(text, each))
        check("reject %r" % text, False, "accepted as " + got)
    except kk.ChordError as e:
        check("reject %r (%s)" % (text, words), words in str(e), str(e))


parses("Meta+Space", "Meta+Space")
parses("super+space", "Meta+Space")
parses("Cmd+Option+K", "Meta+Alt+K")
parses("⌘+⇧+S", "Meta+Shift+S")
parses("Shift+Meta+s", "Meta+Shift+S")
parses("control + alt + t", "Ctrl+Alt+T")
parses("Win+Ctrl+Left", "Meta+Ctrl+Left")
parses("Meta+Enter", "Meta+Return")
parses("Meta+slash", "Meta+/")
parses("Meta+Page Up", "Meta+PgUp")
parses("Mod4+minus", "Meta+-")
parses("F5", "F5")
parses("Print", "Print")
parses("Shift+Print", "Shift+Print")
parses("ScreenSaver", "ScreenSaver")
parses("Ctrl+Alt+Del", "Ctrl+Alt+Del")
parses("Meta+Alt+3", "Meta+Alt+#", kk.EACH_DIGITS)
parses("Meta+Shift+Left", "Meta+Shift+#", kk.EACH_ARROWS)
parses("Meta+Ctrl+#", "Meta+Ctrl+#", kk.EACH_DIGITS)
rejects("", "empty")
rejects("   ", "empty")
rejects("A", "needs a modifier")
rejects("Space", "needs a modifier")
rejects("Shift+A", "Shift on its own")
rejects("Shift+Space", "Shift on its own")
rejects("Meta+Meta+A", "twice")
rejects("Meta+A+B", "more than one key")
rejects("Meta+Ctrl", "no key")
rejects("Meta+", "can't end with +")
rejects("Meta++A", "empty part")
rejects("Meta+Banana", "unknown key")
rejects("Hyper+Fn+A", "unknown key")
rejects("Ctrl+Alt+F3", "text consoles")
rejects("Ctrl+Alt+Backspace", "display server")
rejects("Meta+Shift+/", "different character")
rejects("Meta+#", "only fits numbered")
rejects("Meta+X", "use # in place", kk.EACH_DIGITS)
rejects("Meta+5", "use # in place", kk.EACH_ARROWS)

c = kk.parse("Meta+Space")
check("qt Meta+Space", c.qt() == 0x10000020, hex(c.qt()))
check("qt Ctrl+Alt+T", kk.parse("Ctrl+Alt+T").qt() == 0x0C000054, hex(kk.parse("Ctrl+Alt+T").qt()))
check("qt Meta+Shift+S", kk.parse("Meta+Shift+S").qt() == 0x12000053)
check("qt Meta+Ctrl+Right", kk.parse("Meta+Ctrl+Right").qt() == 0x14000000 | 0x01000014)
check("qt Alt+F4", kk.parse("Alt+F4").qt() == 0x08000000 | 0x01000033)
check("qt round trip", kk.qt_names([kk.parse("Meta+Alt+Esc").qt()]) == ["Meta+Alt+Esc"])
check("hyprland Meta+Space", kk.parse("Meta+Space").hypr() == ("SUPER", "Space"), kk.parse("Meta+Space").hypr())
check("hyprland Meta+Shift+S", kk.parse("Meta+Shift+S").hypr() == ("SUPER SHIFT", "S"))
check("hyprland Meta+/", kk.parse("Meta+/").hypr() == ("SUPER", "slash"))
check("hyprland Print", kk.parse("Print").hypr() == ("", "Print"))
check("sway Meta+Shift+S", kk.parse("Meta+Shift+S").sway() == "Mod4+Shift+s")
check("sway Meta+Alt+Return", kk.parse("Meta+Alt+Return").sway() == "Mod4+Mod1+Return")
check("gnome Meta+Shift+S", kk.parse("Meta+Shift+S").gnome() == "<Super><Shift>s")
check("gnome Ctrl+Alt+T", kk.parse("Ctrl+Alt+T").gnome() == "<Control><Alt>t")
check("gnome parse <Primary><Alt>t", str(kk.parse_gnome("<Primary><Alt>t")) == "Ctrl+Alt+T")
check("gnome parse <Super>Page_Down", str(kk.parse_gnome("<Super>Page_Down")) == "Meta+PgDown")
check("gnome parse junk", kk.parse_gnome("<Fancy>x") is None)
check("loose parse of KDE names", str(kk.parse_loose("Volume Up")) == "VolumeUp")
check("loose parse of Meta+Shift+?", kk.parse_loose("Meta+Shift+Question") is None)
check("caps macOS", kk.caps(kk.parse("Meta+Shift+S"), "macos") == ["⇧", "⌘", "S"], kk.caps(kk.parse("Meta+Shift+S"), "macos"))
check("caps macOS order", kk.caps(kk.parse("Meta+Ctrl+Alt+Shift+K"), "macos") == ["⌃", "⌥", "⇧", "⌘", "K"])
check("caps Windows", kk.caps(kk.parse("Meta+Shift+S"), "windows") == ["Win", "Shift", "S"])
check("caps Linux", kk.caps(kk.parse("Meta+Return"), "linux") == ["Super", "Enter"])
check("caps macOS Return", kk.caps(kk.parse("Meta+Return"), "macos") == ["⌘", "↩"])
check("caps each", kk.caps(kk.parse("Meta+Ctrl+#", kk.EACH_DIGITS), "macos", "1–9") == ["⌃", "⌘", "1–9"])

km = kk.Keymap()
check("defaults load", len(km.actions) > 30, len(km.actions))
check("ids unique", len(km.by_id) == len(km.actions))
for s in kk.SESSIONS:
    for l in kk.LAYOUTS:
        found = kk.conflicts(km, s, l)
        check("no conflicts in defaults: %s/%s" % (s, l), not found, found)
check("every action works somewhere", all(any(a.available(s, l) for s in kk.SESSIONS for l in kk.LAYOUTS) for a in km.actions),
      [a.id for a in km.actions if not any(a.available(s, l) for s in kk.SESSIONS for l in kk.LAYOUTS)])
check("cheat sheet is Meta+K on Linux", [str(c) for c in km.chords(km.by_id["keys"], "kde", "linux")] == ["Meta+K"])
check("cheat sheet is Cmd+/ on macOS", [str(c) for c in km.chords(km.by_id["keys"], "kde", "macos")] == ["Meta+/"])
check("cheat sheet has both on tiling", [str(c) for c in km.chords(km.by_id["keys"], "hyprland", "macos")] == ["Meta+K", "Meta+/"])
check("Spotlight on Windows has Win+S", [str(c) for c in km.chords(km.by_id["spotlight"], "kde", "windows")] == ["Meta+S", "Meta+Space"])
check("Spotlight on GNOME Windows keeps Super+S for the overview", [str(c) for c in km.chords(km.by_id["spotlight"], "gnome", "windows")] == ["Meta+Space"])
check("launcher only on tiling", not km.by_id["launcher"].available("kde", "macos") and km.by_id["launcher"].available("sway", "linux"))
check("snap layouts only in the Windows layout", km.by_id["snaplayouts"].available("kde", "windows") and not km.by_id["snaplayouts"].available("kde", "macos"))
check("agent stop is reserved", km.by_id["agents.stop"].fixed and not kk.runnable(km.by_id["agents.stop"], "kde", "macos"))

km.overrides = {"spotlight": [kk.parse("Meta+W")]}
found = kk.conflicts(km, "kde", "macos")
check("override clash with Overview", any(x["action"] == "spotlight" and x["withId"] == "overview" for x in found), found)
found = kk.conflicts(km, "hyprland", "macos")
check("override clash with Close Window on Hyprland", any(x["action"] == "spotlight" and x["withId"] == "window.close" for x in found), found)
found = kk.all_internal(km, km.overrides, "spotlight", "kde", "macos")
check("all_internal names where", any(x["withId"] == "window.close" and "Hyprland" in x["where"] for x in found), found)
km.overrides = {"workspace": [kk.parse("Meta+Alt+#", kk.EACH_DIGITS)], "inputsource": [kk.parse("Meta+Alt+3")]}
found = kk.conflicts(km, "kde", "linux")
check("each expansion clashes on a single number", any(x["action"] == "inputsource" and x["chord"] == "Meta+Alt+3" for x in found), found)
km.overrides = {}

rc = """[$Version]
update_info=kglobalaccel.upd:kde6

[kwin]
_k_friendly_name=KWin
Overview=Meta+W,Meta+W,Toggle Overview
Window Close=Alt+F4,Alt+F4,Close Window
Expose=Ctrl+F9,Ctrl+F9,Toggle Present Windows (Current desktop)
Window Quick Tile Top=none,Meta+Up,Quick Tile Window to the Top
Activate Window Demanding Attention=Meta+Ctrl+A,Meta+Ctrl+A,Activate Window Demanding Attention

[plasmashell]
_k_friendly_name=plasmashell
activate application launcher=Meta\\tAlt+F1,Meta\\tAlt+F1,Activate Application Launcher
show-on-mouse-pos=Meta+K,Meta+V,Show Clipboard Items at Mouse Position

[services][org.kde.konsole.desktop]
_launch=Ctrl+Alt+T

[services][org.kde.kcalc.desktop]
_launch=Meta+E\\tCalculator
"""
entries, names = kk.read_kde_rc(text=rc)
check("rc reads kwin", entries[("kwin", "Overview")][0] == ["Meta+W"])
check("rc reads none", entries[("kwin", "Window Quick Tile Top")][0] == [])
check("rc reads services", entries[("org.kde.konsole.desktop", "_launch")][0] == ["Ctrl+Alt+T"])
check("rc friendly name", names.get("kwin") == "KWin")
check("rc escaped comma", kk.split_rc_value("Meta+\\,,Meta+\\,,Comma") == ["Meta+,", "Meta+,", "Comma"])
foreign = kk.foreign_bindings(km, "kde", "linux", kde_text=rc)
found = kk.conflicts(km, "kde", "linux", foreign)
check("KDE: our own targets are not foreign", not any(x["with"].startswith("Toggle Overview") or "Close Window" in x["with"] for x in found), found)
check("KDE: Klipper on Meta+K clashes with the cheat sheet", any(x["action"] == "keys" and "Clipboard" in x["with"] for x in found), found)
check("KDE: a calculator on Meta+E clashes with Files", any(x["action"] == "files" and x["target"] == ["kde", "org.kde.kcalc.desktop", "_launch"] for x in found), found)
check("KDE: unrelated shortcuts are ignored", not any(x["chord"] == "Ctrl+F9" for x in found))

gv = {
    ("org.gnome.desktop.wm.keybindings", "close"): ["<Alt>F4"],
    ("org.gnome.desktop.wm.keybindings", "panel-run-dialog"): ["<Super>k"],
    ("org.gnome.shell.keybindings", "toggle-message-tray"): ["<Super>v", "<Super>m"],
    ("custom:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/", "Notes"): ["<Super>e"],
}
found = kk.conflicts(km, "gnome", "linux", kk.foreign_bindings(km, "gnome", "linux", gnome_values=gv))
check("GNOME: close is ours", not any("close" in x["with"] for x in found), found)
check("GNOME: Super+K clashes", any(x["action"] == "keys" and "panel run dialog" in x["with"] for x in found), found)
check("GNOME: message tray on Super+V clashes with the clipboard", any(x["action"] == "clipboard" for x in found), found)
check("GNOME: custom binding clashes with Files", any(x["action"] == "files" and "custom" in x["with"] for x in found), found)

binds = [
    {"modmask": 64, "key": "Space", "dispatcher": "exec", "arg": "kwick-search"},
    {"modmask": 64, "key": "W", "dispatcher": "killactive", "arg": ""},
    {"modmask": 64, "key": "N", "dispatcher": "exec", "arg": "notes"},
    {"modmask": 64, "key": "K", "dispatcher": "exec", "arg": "kitty"},
    {"modmask": 0, "key": "XF86AudioMute", "dispatcher": "exec", "arg": "wpctl"},
    {"modmask": 64, "key": "mouse:272", "dispatcher": "movewindow", "arg": "", "mouse": True},
]
found = kk.conflicts(km, "hyprland", "linux", kk.foreign_bindings(km, "hyprland", "linux", hypr_binds=binds))
check("Hyprland: generated binds are not conflicts", not any(x["chord"] in ("Meta+Space", "Meta+W") for x in found), found)
check("Hyprland: user bind on Super+K clashes", any(x["action"] == "keys" and x["chord"] == "Meta+K" for x in found), found)
check("Hyprland: unrelated user bind is fine", not any(x["chord"] == "Meta+N" for x in found))

sway = """set $mod Mod4
bindsym $mod+Return exec foot
bindsym $mod+n exec notes
bindsym --locked XF86AudioMute exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
mode "resize" {
  bindsym Return mode default
}
"""
found = kk.conflicts(km, "sway", "linux", kk.foreign_bindings(km, "sway", "linux", sway_text=sway))
check("sway: user bind on Mod4+Return clashes with Terminal", any(x["action"] == "terminal" for x in found), found)
check("sway: bindings inside modes are skipped", sum(1 for x in found if x["chord"] == "Return") == 0)

real_run = kk.run
kk.run = lambda argv, input_text=None, timeout=10: (0, "([('Grid View', 'Toggle Grid View', 'kwin', 'KWin', 'default', 'Default Context', [268435527], [268435527]), ('_launch', 'Launch', 'org.kde.it\\'s.desktop', 'It\\'s', 'default', 'Default Context', [268435527], [])],)\n")
check("KDE live lookup by key", kk.kde_who(268435527) == [("kwin", "KWin", "Grid View", "Toggle Grid View"), ("org.kde.it\\'s.desktop", "It\\'s", "_launch", "Launch")], kk.kde_who(268435527))
kk.run = real_run

conf = kk.hypr_conf(km, "linux")
check("Hyprland include has the cheat sheet", "bind = SUPER, K, exec, kwick-keys show" in conf)
check("Hyprland include has workspaces", "bind = SUPER SHIFT, 9, movetoworkspace, 9" in conf)
check("Hyprland include has the record submap", "submap = kwick-record" in conf)
check("Hyprland include leaves the agent hotkey alone", "Escape" not in conf)
conf = kk.sway_conf(km, "linux")
check("sway include has focus", "bindsym Mod4+Left focus left" in conf)
check("sway include has reload", "bindsym Mod4+Shift+c reload" in conf)
check("GNOME grabs", kk.gnome_grabs(km, "linux") == {"clipboard": ["<Super>v"], "capture": ["<Super><Shift>s"]})

check("write once when the default is already there", not kk.should_write({"written": {}}, "t", ["Meta+L"], ["Meta+L", "ScreenSaver"], False))
check("write when the default is missing", kk.should_write({"written": {}}, "t", ["Meta+W"], ["Meta+Tab"], False))
check("respect a later change made outside kwick-keys", not kk.should_write({"written": {"t": ["Meta+W"]}}, "t", ["Meta+W"], ["Meta+Tab"], False))
check("restore after a reset", kk.should_write({"written": {"t": ["Meta+Q"]}}, "t", ["Meta+W"], ["Meta+Q"], False))
check("custom always wins", kk.should_write({"written": {"t": ["Meta+Q"]}}, "t", ["Meta+Q"], ["Meta+Tab"], True))

out = os.path.join(TMP, "export.json")
km.overrides = {"spotlight": [kk.parse("Meta+Alt+Space")]}
km.save()
check("save writes canonical chords", json.load(open(kk.USER_FILE, encoding="utf-8"))["bindings"] == {"spotlight": ["Meta+Alt+Space"]})
km2 = kk.Keymap()
check("user override loads", [str(c) for c in km2.chords(km2.by_id["spotlight"], "kde", "macos")] == ["Meta+Alt+Space"])
with open(kk.USER_FILE, "w", encoding="utf-8") as f:
    json.dump({"bindings": {"spotlight": ["Q"], "agents.stop": ["Meta+X"], "nope": ["Meta+X"]}}, f)
km3 = kk.Keymap()
check("bad user overrides are ignored", not km3.overrides, km3.overrides)

print()
if FAILS:
    print("%d failed: %s" % (len(FAILS), ", ".join(FAILS)))
    sys.exit(1)
print("all passed")
