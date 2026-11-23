package main

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestSettingsSchemaIsComplete(t *testing.T) {
	seen := map[string]bool{}
	groups := map[string]bool{}
	for _, st := range settingsTable() {
		if seen[st.Key] {
			t.Fatalf("duplicate key %s", st.Key)
		}
		seen[st.Key] = true
		groups[st.Group] = true
		if st.get == nil || st.set == nil {
			t.Fatalf("%s has no getter or setter", st.Key)
		}
		if st.Title == "" || st.Group == "" {
			t.Fatalf("%s has no title or group", st.Key)
		}
		switch st.Type {
		case "enum":
			if len(st.Values) == 0 {
				t.Fatalf("%s: enum without values", st.Key)
			}
		case "int", "number":
			if st.Max <= st.Min {
				t.Fatalf("%s: bad range", st.Key)
			}
		case "list":
			if st.MaxItems <= 0 || st.Pattern == nil {
				t.Fatalf("%s: list needs max_items and a pattern", st.Key)
			}
		case "bool", "string", "path":
		default:
			t.Fatalf("%s: unknown type %s", st.Key, st.Type)
		}
		if _, err := json.Marshal(st.describe()); err != nil {
			t.Fatalf("%s: %v", st.Key, err)
		}
	}
	for _, k := range []string{"layout", "appearance", "accent", "wallpaper", "corner_radius", "fonts", "dock.position", "dock.size", "dock.apps",
		"effects.preset", "effects.wobbly", "effects.open_close", "desktop.default_session", "desktop.shell", "shell.login", "shell.prompt",
		"display.night_light", "display.brightness", "display.scale", "sound.volume", "sound.mute", "notifications.do_not_disturb",
		"network.wifi", "bluetooth.enabled", "nearby.visibility", "power.profile", "updates.check", "updates.install_security", "updates.interval_hours",
		"touch.tablet_mode"} {
		if !seen[k] {
			t.Fatalf("missing setting %s", k)
		}
	}
	for _, k := range []string{"desktop.default_session", "shell.login", "updates.check", "updates.interval_hours"} {
		if !settingByKey(k).Privileged {
			t.Fatalf("%s must be privileged", k)
		}
	}
	for _, k := range []string{"appearance", "sound.volume", "display.night_light", "dock.size"} {
		if settingByKey(k).Privileged {
			t.Fatalf("%s must not be privileged", k)
		}
	}
}

func TestValidateSetting(t *testing.T) {
	ok := []struct {
		key  string
		in   any
		want any
	}{
		{"appearance", "light", "light"},
		{"dock.autohide", true, true},
		{"dock.autohide", "on", true},
		{"dock.autohide", "false", false},
		{"dock.autohide", float64(0), false},
		{"dock.size", float64(56), 56},
		{"dock.size", "64", 64},
		{"sound.volume", "40%", 40},
		{"display.scale", float64(1.25), 1.25},
		{"display.scale", "2", 2.0},
		{"updates.interval_hours", float64(12), 12},
		{"nearby.name", "Kitchen Laptop", "Kitchen Laptop"},
		{"wallpaper", "/usr/share/wallpapers/Next/contents/images/1920x1080.png", "/usr/share/wallpapers/Next/contents/images/1920x1080.png"},
		{"effects.open_close", "flame", "flame"},
	}
	for _, c := range ok {
		got, err := validateSetting(settingByKey(c.key), c.in)
		if err != nil {
			t.Fatalf("%s=%v: %v", c.key, c.in, err)
		}
		if gb, _ := json.Marshal(got); string(gb) != mustJSON(c.want) {
			t.Fatalf("%s=%v: got %v want %v", c.key, c.in, got, c.want)
		}
	}
	bad := []struct {
		key string
		in  any
	}{
		{"appearance", "pink"},
		{"appearance", "dark; rm -rf ~"},
		{"appearance", float64(1)},
		{"layout", "$(reboot)"},
		{"dock.autohide", "maybe"},
		{"dock.autohide", float64(2)},
		{"dock.size", float64(31)},
		{"dock.size", float64(97)},
		{"dock.size", float64(48.5)},
		{"dock.size", "big"},
		{"corner_radius", float64(-1)},
		{"sound.volume", float64(101)},
		{"display.scale", float64(1.3)},
		{"display.scale", float64(4)},
		{"updates.interval_hours", float64(0)},
		{"nearby.name", ""},
		{"nearby.name", "-rf"},
		{"nearby.name", "name\nwith newline"},
		{"nearby.name", strings.Repeat("a", 41)},
		{"wallpaper", "relative/path.png"},
		{"wallpaper", float64(3)},
		{"dock.apps", []any{"firefox-esr.desktop", "../../etc/passwd"}},
		{"dock.apps", []any{"firefox-esr.desktop", float64(1)}},
		{"dock.apps", "firefox-esr.desktop"},
		{"effects.open_close", "--help"},
	}
	for _, c := range bad {
		if v, err := validateSetting(settingByKey(c.key), c.in); err == nil {
			t.Fatalf("%s=%v was accepted as %v", c.key, c.in, v)
		}
	}
	many := []any{}
	for i := 0; i < 31; i++ {
		many = append(many, "a.desktop")
	}
	if _, err := validateSetting(settingByKey("dock.apps"), many); err == nil {
		t.Fatal("31 dock apps accepted")
	}
	v, err := validateSetting(settingByKey("dock.apps"), []any{"a.desktop", "b.desktop", "a.desktop"})
	if err != nil || len(v.([]string)) != 2 {
		t.Fatalf("dedupe: %v %v", v, err)
	}
}

func mustJSON(v any) string {
	b, _ := json.Marshal(v)
	return string(b)
}

func TestParseSettingChanges(t *testing.T) {
	ch, err := parseSettingChanges(map[string]any{"settings": map[string]any{"appearance": "light", "dock.size": float64(56), "layout": "windows"}})
	if err != nil {
		t.Fatal(err)
	}
	if len(ch) != 3 || ch[0].st.Key != "layout" || ch[1].st.Key != "appearance" {
		t.Fatalf("order: %v %v", ch[0].st.Key, ch[1].st.Key)
	}
	ch, err = parseSettingChanges(map[string]any{"appearance": "dark"})
	if err != nil || len(ch) != 1 || ch[0].val != "dark" {
		t.Fatalf("legacy argument: %v %v", ch, err)
	}
	ch, err = parseSettingChanges(map[string]any{"settings": map[string]any{"radius": float64(8)}})
	if err != nil || ch[0].st.Key != "corner_radius" {
		t.Fatalf("legacy key radius: %v", err)
	}
	for _, a := range []map[string]any{
		{},
		{"settings": map[string]any{}},
		{"settings": "appearance=light"},
		{"settings": map[string]any{"nope": true}},
		{"settings": map[string]any{"appearance": "blue"}},
		{"theme": "light"},
	} {
		if _, err := parseSettingChanges(a); err == nil {
			t.Fatalf("%v was accepted", a)
		}
	}
	big := map[string]any{}
	for i, st := range settingsTable() {
		if i > 20 {
			break
		}
		big[st.Key] = true
	}
	if _, err := parseSettingChanges(map[string]any{"settings": big}); err == nil {
		t.Fatal("more than 20 settings accepted")
	}
	d := settingsDetail(nil, map[string]any{"settings": map[string]any{"appearance": "light", "updates.check": false}})
	if !strings.Contains(d, "Appearance to light") || !strings.Contains(d, "administrator") {
		t.Fatalf("detail %q", d)
	}
}

func TestSettingsAvailability(t *testing.T) {
	t.Setenv("XDG_CURRENT_DESKTOP", "GNOME")
	t.Setenv("HYPRLAND_INSTANCE_SIGNATURE", "")
	t.Setenv("SWAYSOCK", "")
	if ok, _ := settingByKey("effects.alt_tab").available(); ok {
		t.Fatal("alt_tab should be KDE only")
	}
	if ok, why := settingByKey("display.scale").available(); ok || !strings.Contains(why, "gnome") {
		t.Fatalf("display.scale on GNOME: %v %s", ok, why)
	}
	t.Setenv("XDG_CURRENT_DESKTOP", "KDE")
	if ok, _ := settingByKey("display.night_light").available(); !ok {
		t.Fatal("night light should be available on KDE")
	}
	t.Setenv("XDG_CURRENT_DESKTOP", "")
	if ok, why := settingByKey("accent").available(); ok || !strings.Contains(why, "desktop session") {
		t.Fatalf("accent without a desktop: %v %s", ok, why)
	}
}

func TestParseKDateTime(t *testing.T) {
	for _, s := range []string{"2027,11,22,10,0,0", "2027-11-22T10:00:00", "2027,11,22,10,0,0.5"} {
		tm, err := parseKDateTime(s)
		if err != nil || tm.Year() != 2027 || tm.Hour() != 10 {
			t.Fatalf("%s: %v %v", s, tm, err)
		}
	}
	if _, err := parseKDateTime("x"); err == nil {
		t.Fatal("bad date accepted")
	}
	if tm, err := parseKDateTime(dndUntil()); err != nil || tm.Year() < 2026 {
		t.Fatalf("dndUntil round trip: %v %v", tm, err)
	}
}
