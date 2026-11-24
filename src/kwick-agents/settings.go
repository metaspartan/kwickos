package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode"
)

type setting struct {
	Key         string
	Group       string
	Title       string
	Description string
	Type        string
	Values      []string
	Min         float64
	Max         float64
	Step        float64
	Pattern     *regexp.Regexp
	MaxItems    int
	Privileged  bool
	Desktops    []string
	Needs       []string
	get         func(c *setCtx) (any, error)
	set         func(c *setCtx, v any) error
}

type setCtx struct {
	agent string
	mu    sync.Mutex
	memo  map[string]memoVal
	log   []string
}

type memoVal struct {
	out string
	err error
}

func newSetCtx(agent string) *setCtx { return &setCtx{agent: agent, memo: map[string]memoVal{}} }

func (c *setCtx) out(name string, args ...string) (string, error) {
	k := name + "\x00" + strings.Join(args, "\x00")
	c.mu.Lock()
	if m, ok := c.memo[k]; ok {
		c.mu.Unlock()
		return m.out, m.err
	}
	c.mu.Unlock()
	o, err := cmdText(30*time.Second, name, args...)
	c.mu.Lock()
	c.memo[k] = memoVal{o, err}
	c.mu.Unlock()
	return o, err
}

func (c *setCtx) run(timeout time.Duration, name string, args ...string) error {
	o, err := cmdText(timeout, name, args...)
	c.mu.Lock()
	if o != "" {
		c.log = append(c.log, o)
	}
	c.memo = map[string]memoVal{}
	c.mu.Unlock()
	return err
}

func (c *setCtx) priv(args ...string) error {
	o, err := runPrivileged(c.agent, args...)
	c.mu.Lock()
	if o = strings.TrimSpace(o); o != "" {
		c.log = append(c.log, o)
	}
	c.memo = map[string]memoVal{}
	c.mu.Unlock()
	return err
}

func cmdText(timeout time.Duration, name string, args ...string) (string, error) {
	if lookPath(name) == "" {
		return "", fmt.Errorf("%s is not installed", name)
	}
	out, err := runTimeout(timeout, name, args...)
	o := strings.TrimSpace(string(out))
	if err != nil {
		if len(o) > 400 {
			o = o[len(o)-400:]
		}
		return o, fmt.Errorf("%s %s failed: %v %s", name, strings.Join(args, " "), err, o)
	}
	return o, nil
}

func desktopKind() string {
	d := strings.ToLower(os.Getenv("XDG_CURRENT_DESKTOP"))
	switch {
	case os.Getenv("HYPRLAND_INSTANCE_SIGNATURE") != "" || strings.Contains(d, "hyprland"):
		return "hyprland"
	case os.Getenv("SWAYSOCK") != "" || strings.Contains(d, "sway"):
		return "sway"
	case strings.Contains(d, "kde"):
		return "kde"
	case strings.Contains(d, "gnome"):
		return "gnome"
	}
	return ""
}

func (st *setting) available() (bool, string) {
	if len(st.Desktops) > 0 {
		dk := desktopKind()
		ok := false
		for _, d := range st.Desktops {
			if d == dk {
				ok = true
			}
		}
		if !ok {
			if dk == "" {
				return false, "needs a desktop session (" + strings.Join(st.Desktops, ", ") + ")"
			}
			return false, "not available on " + dk + " (only " + strings.Join(st.Desktops, ", ") + ")"
		}
	}
	if len(st.Needs) > 0 {
		for _, n := range st.Needs {
			if lookPath(n) != "" {
				return true, ""
			}
		}
		return false, strings.Join(st.Needs, " or ") + " is not installed"
	}
	return true, ""
}

func (st *setting) describe() map[string]any {
	m := map[string]any{"key": st.Key, "group": st.Group, "title": st.Title, "type": st.Type, "description": st.Description}
	switch st.Type {
	case "enum":
		m["values"] = st.Values
	case "int", "number":
		m["min"] = st.Min
		m["max"] = st.Max
		if st.Step > 0 {
			m["step"] = st.Step
		}
		if len(st.Values) > 0 {
			var vs []float64
			for _, v := range st.Values {
				f, _ := strconv.ParseFloat(v, 64)
				vs = append(vs, f)
			}
			m["values"] = vs
		}
	case "list":
		m["max_items"] = st.MaxItems
	}
	if st.Pattern != nil {
		m["pattern"] = st.Pattern.String()
	}
	if st.Privileged {
		m["privileged"] = true
	}
	if len(st.Desktops) > 0 {
		m["desktops"] = st.Desktops
	}
	ok, why := st.available()
	m["available"] = ok
	if !ok {
		m["reason"] = why
	}
	return m
}

func validateSetting(st *setting, v any) (any, error) {
	bad := func(want string) error {
		b, _ := json.Marshal(v)
		return fmt.Errorf("%s: %s is not valid; expected %s", st.Key, string(b), want)
	}
	switch st.Type {
	case "bool":
		switch x := v.(type) {
		case bool:
			return x, nil
		case string:
			switch strings.ToLower(x) {
			case "on", "true", "yes", "1":
				return true, nil
			case "off", "false", "no", "0":
				return false, nil
			}
		case float64:
			if x == 0 || x == 1 {
				return x == 1, nil
			}
		}
		return nil, bad("true or false")
	case "enum":
		s := ""
		switch x := v.(type) {
		case string:
			s = x
		case float64:
			if x == math.Trunc(x) {
				s = strconv.FormatInt(int64(x), 10)
			}
		}
		for _, a := range st.Values {
			if s == a {
				return s, nil
			}
		}
		return nil, bad("one of " + strings.Join(st.Values, ", "))
	case "int", "number":
		var f float64
		switch x := v.(type) {
		case float64:
			f = x
		case int:
			f = float64(x)
		case string:
			p, err := strconv.ParseFloat(strings.TrimSpace(strings.TrimSuffix(x, "%")), 64)
			if err != nil {
				return nil, bad("a number")
			}
			f = p
		default:
			return nil, bad("a number")
		}
		if math.IsNaN(f) || math.IsInf(f, 0) {
			return nil, bad("a number")
		}
		rng := fmt.Sprintf("a number from %s to %s", fmtNum(st.Min), fmtNum(st.Max))
		if st.Type == "int" {
			if f != math.Trunc(f) {
				return nil, bad("a whole " + rng[2:])
			}
			rng = "a whole " + rng[2:]
		}
		if f < st.Min || f > st.Max {
			return nil, bad(rng)
		}
		if len(st.Values) > 0 {
			for _, a := range st.Values {
				if af, _ := strconv.ParseFloat(a, 64); math.Abs(af-f) < 1e-9 {
					return af, nil
				}
			}
			return nil, bad("one of " + strings.Join(st.Values, ", "))
		}
		if st.Type == "int" {
			return int(f), nil
		}
		return f, nil
	case "string", "path":
		s, ok := v.(string)
		if !ok {
			return nil, bad("a string")
		}
		if len(s) == 0 || len(s) > 512 || !utf8Clean(s) {
			return nil, bad("a non-empty string without control characters, at most 512 bytes")
		}
		if st.Pattern != nil && !st.Pattern.MatchString(s) {
			return nil, bad("a value matching " + st.Pattern.String())
		}
		if st.Type == "path" && !filepath.IsAbs(expandHome(s)) {
			return nil, bad("an absolute path")
		}
		return s, nil
	case "list":
		arr, ok := v.([]any)
		if !ok {
			return nil, bad("an array of strings")
		}
		if len(arr) > st.MaxItems {
			return nil, bad(fmt.Sprintf("at most %d items", st.MaxItems))
		}
		out := []string{}
		seen := map[string]bool{}
		for _, x := range arr {
			s, ok := x.(string)
			if !ok || (st.Pattern != nil && !st.Pattern.MatchString(s)) {
				return nil, bad("an array of values matching " + st.Pattern.String())
			}
			if !seen[s] {
				seen[s] = true
				out = append(out, s)
			}
		}
		return out, nil
	}
	return nil, fmt.Errorf("%s: unsupported type", st.Key)
}

func fmtNum(f float64) string { return strconv.FormatFloat(f, 'f', -1, 64) }

func utf8Clean(s string) bool {
	for _, r := range s {
		if r == unicode.ReplacementChar || unicode.IsControl(r) {
			return false
		}
	}
	return true
}

func onOff(v any) string {
	if b, _ := v.(bool); b {
		return "on"
	}
	return "off"
}

var (
	accentNames  = []string{"blue", "purple", "pink", "red", "orange", "yellow", "green", "graphite", "deepblue", "indigo", "teal", "forest", "crimson", "burntorange", "plum", "brown", "slate"}
	highlights   = append([]string{"accent"}, accentNames...)
	accentRGB    = map[string]string{"blue": "10,132,255", "purple": "191,90,242", "pink": "255,55,95", "red": "255,69,58", "orange": "255,159,10", "yellow": "255,214,10", "green": "48,209,88", "graphite": "152,152,157"}
	accentHex    = map[string]string{"blue": "#0a84ff", "purple": "#bf5af2", "pink": "#ff375f", "red": "#ff453a", "orange": "#ff9f0a", "yellow": "#ffd60a", "green": "#30d158", "graphite": "#98989d"}
	ocStyles     = []string{"none", "scale", "fade", "glide", "flip", "flame", "dissolve", "fallapart", "apparition", "aura-glow", "broken-glass", "doom", "energize-a", "energize-b", "fire", "focus", "glitch", "hexagon", "incinerate", "matrix", "mushroom", "paint-brush", "pixelate", "pixel-wheel", "pixel-wipe", "portal", "rgbwarp", "snap", "team-rocket", "trex", "tv", "tv-glitch", "wisps"}
	fxToggles    = []struct{ name, title string }{{"wobbly", "Wobbly windows"}, {"lamp", "Magic lamp minimize"}, {"blur", "Blur behind panels and menus"}, {"transparency", "Translucent inactive windows"}, {"sheet", "Sheet dialogs"}, {"dim", "Dim inactive windows"}, {"overview", "Overview"}, {"cube", "3D desktop cube"}, {"liquidglass", "Liquid Glass"}}
	desktopIDPat = regexp.MustCompile(`^[A-Za-z0-9._-]{1,120}\.desktop$`)
	aliasPat     = regexp.MustCompile(`^[\p{L}\p{N}][\p{L}\p{N} ._'()-]{0,39}$`)
	wallExt      = map[string]bool{".png": true, ".jpg": true, ".jpeg": true, ".webp": true, ".svg": true, ".jxl": true, ".avif": true}
)

func kwickConfPath(name string) string {
	return filepath.Join(xdg("XDG_CONFIG_HOME", ".config"), "kwick", name)
}

func keyFile(path, key, def string) string {
	f, err := os.Open(path)
	if err != nil {
		return def
	}
	defer f.Close()
	v := def
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		if l := sc.Text(); strings.HasPrefix(l, key+"=") {
			v = strings.TrimSpace(l[len(key)+1:])
		}
	}
	return v
}

func layoutStatus(c *setCtx) (map[string]any, error) {
	o, err := c.out("kwick-layout", "status", "--json")
	if err != nil {
		return nil, err
	}
	var m map[string]any
	if err := json.Unmarshal([]byte(o), &m); err != nil {
		return nil, fmt.Errorf("kwick-layout status did not print JSON")
	}
	return m, nil
}

func layoutField(k string) func(c *setCtx) (any, error) {
	return func(c *setCtx) (any, error) {
		m, err := layoutStatus(c)
		if err != nil {
			return nil, err
		}
		if k == "radius" {
			switch x := m[k].(type) {
			case float64:
				return int(x), nil
			case string:
				if n, err := strconv.Atoi(strings.Fields(x + " ")[0]); err == nil {
					return n, nil
				}
			}
			return nil, nil
		}
		return m[k], nil
	}
}

func effectsStatus(c *setCtx) map[string]string {
	o, _ := c.out("kwick-effects", "status")
	m := map[string]string{}
	for _, l := range strings.Split(o, "\n") {
		f := strings.Fields(l)
		if len(f) == 2 {
			m[f[0]] = f[1]
		}
	}
	return m
}

func lineOf(c *setCtx, name string, args ...string) (any, error) {
	o, err := c.out(name, args...)
	if err != nil {
		return nil, err
	}
	o = strings.TrimSpace(strings.Split(o, "\n")[0])
	if o == "" || o == "na" {
		return nil, nil
	}
	return o, nil
}

func intOf(c *setCtx, idx int, name string, args ...string) (any, error) {
	o, err := c.out(name, args...)
	if err != nil {
		return nil, err
	}
	f := strings.Fields(o)
	if idx >= len(f) {
		return nil, nil
	}
	n, err := strconv.Atoi(strings.TrimSuffix(f[idx], "%"))
	if err != nil {
		return nil, nil
	}
	return n, nil
}

func kread(c *setCtx, file, group, key string) string {
	o, _ := c.out("kreadconfig6", "--file", file, "--group", group, "--key", key)
	return strings.TrimSpace(o)
}

func gsetGet(c *setCtx, schema, key string) string {
	o, _ := c.out("gsettings", "get", schema, key)
	return strings.Trim(strings.TrimSpace(o), "'")
}

func jsonOf(c *setCtx, name string, args ...string) map[string]any {
	o, err := c.out(name, args...)
	if err != nil {
		return nil
	}
	var m map[string]any
	if json.Unmarshal([]byte(o), &m) != nil {
		return nil
	}
	return m
}

func updateAuto(c *setCtx) (map[string]any, error) {
	m := jsonOf(c, "kwick-update", "status", "--json")
	if m == nil {
		return nil, fmt.Errorf("kwick-update status --json failed")
	}
	a, _ := m["auto"].(map[string]any)
	if a == nil {
		return nil, fmt.Errorf("kwick-update reports no automatic update settings")
	}
	return a, nil
}

func kdeWallpaper() string {
	f, err := os.Open(filepath.Join(xdg("XDG_CONFIG_HOME", ".config"), "plasma-org.kde.plasma.desktop-appletsrc"))
	if err != nil {
		return ""
	}
	defer f.Close()
	in := false
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		l := strings.TrimSpace(sc.Text())
		if strings.HasPrefix(l, "[") {
			in = strings.HasSuffix(l, "[Wallpaper][org.kde.image][General]")
			continue
		}
		if in && strings.HasPrefix(l, "Image=") {
			return strings.TrimPrefix(strings.TrimPrefix(l, "Image="), "file://")
		}
	}
	return ""
}

func wallpaperAllowed(p string) (string, error) {
	p = filepath.Clean(expandHome(p))
	r, err := filepath.EvalSymlinks(p)
	if err != nil {
		return "", fmt.Errorf("wallpaper: %s does not exist", p)
	}
	st, err := os.Stat(r)
	if err != nil || !st.Mode().IsRegular() {
		return "", fmt.Errorf("wallpaper: %s is not a file", p)
	}
	if !wallExt[strings.ToLower(filepath.Ext(r))] {
		return "", fmt.Errorf("wallpaper: %s is not a PNG, JPEG, WebP, AVIF, JPEG XL or SVG image", p)
	}
	if isProtected(r) {
		return "", fmt.Errorf("wallpaper: %s belongs to kwick-agents", p)
	}
	return r, nil
}

func audioSink(c *setCtx) (float64, bool, error) {
	o, err := c.out("wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@")
	if err != nil {
		return 0, false, err
	}
	f := strings.Fields(o)
	if len(f) < 2 {
		return 0, false, fmt.Errorf("wpctl printed %q", o)
	}
	v, err := strconv.ParseFloat(f[1], 64)
	if err != nil {
		return 0, false, fmt.Errorf("wpctl printed %q", o)
	}
	return v, strings.Contains(o, "[MUTED]"), nil
}

func dndUntil() string {
	return time.Now().AddDate(1, 0, 0).Format("2006,1,2,15,4,5")
}

var settingsOnce []*setting

func settingsTable() []*setting {
	if settingsOnce != nil {
		return settingsOnce
	}
	desk := []string{"kde", "gnome", "hyprland", "sway"}
	ss := []*setting{
		{Key: "layout", Group: "appearance", Title: "Desktop layout", Type: "enum", Values: []string{"macos", "windows", "linux"}, Needs: []string{"kwick-layout"},
			Description: "Panels, dock, window buttons, shortcuts and fonts like macOS, Windows or a classic Linux desktop.",
			get:         layoutField("layout"),
			set:         func(c *setCtx, v any) error { return c.run(120*time.Second, "kwick-layout", v.(string)) }},
		{Key: "appearance", Group: "appearance", Title: "Appearance", Type: "enum", Values: []string{"dark", "light"}, Needs: []string{"kwick-layout"},
			Description: "Dark or light colors for the desktop and apps.",
			get:         layoutField("appearance"),
			set:         func(c *setCtx, v any) error { return c.run(60*time.Second, "kwick-layout", "appearance", v.(string)) }},
		{Key: "highlight", Group: "appearance", Title: "Highlight color", Type: "enum", Values: highlights, Needs: []string{"kwick-layout"},
			Description: "Color of list and text selection: the accent color, graphite (neutral grey) or any accent name.",
			get: func(c *setCtx) (any, error) {
				o, err := c.out("kwick-layout", "highlight")
				return strings.TrimSpace(o), err
			},
			set: func(c *setCtx, v any) error { return c.run(60*time.Second, "kwick-layout", "highlight", v.(string)) }},
		{Key: "sidebar_icons", Group: "appearance", Title: "Sidebar icon color", Type: "enum", Values: []string{"neutral", "accent"}, Needs: []string{"kwick-layout"},
			Description: "Sidebar icons in Files, Settings and other apps: neutral (white or dark grey) or the accent color.",
			get: func(c *setCtx) (any, error) {
				o, err := c.out("kwick-layout", "sidebar")
				return strings.TrimSpace(o), err
			},
			set: func(c *setCtx, v any) error { return c.run(60*time.Second, "kwick-layout", "sidebar", v.(string)) }},
		{Key: "wallpaper_tinting", Group: "appearance", Title: "Allow wallpaper tinting in windows", Type: "bool", Needs: []string{"kwick-layout"},
			Description: "Translucent, blurred window backgrounds and sidebars tinted by the wallpaper.",
			get: func(c *setCtx) (any, error) {
				o, err := c.out("kwick-layout", "tint")
				return strings.TrimSpace(o) == "on", err
			},
			set: func(c *setCtx, v any) error {
				return c.run(60*time.Second, "kwick-layout", "tint", map[bool]string{true: "on", false: "off"}[v.(bool)])
			}},
		{Key: "corner_radius", Group: "appearance", Title: "Window corner radius", Type: "int", Min: 0, Max: 24, Step: 1, Needs: []string{"kwick-layout"},
			Description: "Rounding of window corners in pixels.",
			get:         layoutField("radius"),
			set: func(c *setCtx, v any) error {
				return c.run(60*time.Second, "kwick-layout", "radius", strconv.Itoa(v.(int)))
			}},
		{Key: "accent", Group: "appearance", Title: "Accent color", Type: "enum", Values: accentNames, Desktops: desk,
			Description: "Accent color for buttons, switches, focus rings and, when highlight is accent, selection.",
			get: func(c *setCtx) (any, error) {
				if lookPath("kwick-layout") != "" {
					if o, err := c.out("kwick-layout", "accent"); err == nil && strings.TrimSpace(o) != "" {
						return strings.TrimSpace(o), nil
					}
				}
				if desktopKind() == "gnome" {
					g := gsetGet(c, "org.gnome.desktop.interface", "accent-color")
					if g == "slate" {
						return "graphite", nil
					}
					return g, nil
				}
				rgb := strings.ReplaceAll(kread(c, "kdeglobals", "General", "AccentColor"), " ", "")
				for n, v := range accentRGB {
					if v == rgb {
						return n, nil
					}
				}
				if rgb == "" {
					return nil, nil
				}
				return "custom (" + rgb + ")", nil
			},
			set: func(c *setCtx, v any) error {
				n := v.(string)
				if lookPath("kwick-layout") != "" {
					return c.run(60*time.Second, "kwick-layout", "accent", n)
				}
				if accentRGB[n] == "" {
					return fmt.Errorf("%s needs kwick-layout", n)
				}
				var errs []string
				if lookPath("kwriteconfig6") != "" {
					if err := c.run(20*time.Second, "kwriteconfig6", "--file", "kdeglobals", "--group", "General", "--key", "AccentColor", accentRGB[n]); err != nil {
						errs = append(errs, err.Error())
					}
				}
				if desktopKind() == "kde" && lookPath("plasma-apply-colorscheme") != "" {
					if err := c.run(30*time.Second, "plasma-apply-colorscheme", "--accent-color", accentHex[n]); err != nil {
						errs = append(errs, err.Error())
					}
				}
				if lookPath("gsettings") != "" {
					g := n
					if g == "graphite" {
						g = "slate"
					}
					c.run(20*time.Second, "gsettings", "set", "org.gnome.desktop.interface", "accent-color", g)
				}
				if len(errs) > 0 {
					return fmt.Errorf("%s", strings.Join(errs, "; "))
				}
				return nil
			}},
		{Key: "wallpaper", Group: "appearance", Title: "Wallpaper", Type: "path", Desktops: desk,
			Description: "Absolute path of an image file (PNG, JPEG, WebP, AVIF, JPEG XL or SVG), for example one of /usr/share/wallpapers/*/contents/images/*.png.",
			get: func(c *setCtx) (any, error) {
				switch desktopKind() {
				case "kde":
					if w := kdeWallpaper(); w != "" {
						return w, nil
					}
				case "gnome":
					u := gsetGet(c, "org.gnome.desktop.background", "picture-uri")
					if cs := gsetGet(c, "org.gnome.desktop.interface", "color-scheme"); cs == "prefer-dark" {
						if d := gsetGet(c, "org.gnome.desktop.background", "picture-uri-dark"); d != "" {
							u = d
						}
					}
					return strings.TrimPrefix(u, "file://"), nil
				}
				return nil, nil
			},
			set: func(c *setCtx, v any) error {
				p, err := wallpaperAllowed(v.(string))
				if err != nil {
					return err
				}
				switch desktopKind() {
				case "kde":
					return c.run(30*time.Second, "plasma-apply-wallpaperimage", p)
				case "gnome":
					if err := c.run(20*time.Second, "gsettings", "set", "org.gnome.desktop.background", "picture-uri", "file://"+p); err != nil {
						return err
					}
					return c.run(20*time.Second, "gsettings", "set", "org.gnome.desktop.background", "picture-uri-dark", "file://"+p)
				case "sway":
					return c.run(20*time.Second, "swaymsg", "output", "*", "bg", p, "fill")
				case "hyprland":
					if err := c.run(20*time.Second, "hyprctl", "hyprpaper", "preload", p); err != nil {
						return err
					}
					return c.run(20*time.Second, "hyprctl", "hyprpaper", "wallpaper", ","+p)
				}
				return fmt.Errorf("no desktop session")
			}},
		{Key: "fonts", Group: "appearance", Title: "Font set", Type: "enum", Values: []string{"macos", "windows", "linux"}, Needs: []string{"kwick-fonts"},
			Description: "Interface, document and monospace fonts matching a layout (Inter, Segoe-like Selawik, or Ubuntu Sans).",
			get: func(c *setCtx) (any, error) {
				b, err := os.ReadFile(filepath.Join(xdg("XDG_CONFIG_HOME", ".config"), "fontconfig", "conf.d", "60-kwick-layout.conf"))
				if err != nil {
					return nil, nil
				}
				s := string(b)
				switch {
				case strings.Contains(s, "<family>Inter</family>"):
					return "macos", nil
				case strings.Contains(s, "<family>Selawik</family>"):
					return "windows", nil
				case strings.Contains(s, "<family>Ubuntu Sans</family>"):
					return "linux", nil
				}
				return nil, nil
			},
			set: func(c *setCtx, v any) error { return c.run(120*time.Second, "kwick-fonts", "apply", v.(string)) }},

		{Key: "dock.position", Group: "dock", Title: "Dock position", Type: "enum", Values: []string{"bottom", "left", "right"}, Needs: []string{"kwick-dock"},
			Description: "Screen edge of the dock (macOS layout).",
			get:         func(c *setCtx) (any, error) { return keyFile(kwickConfPath("dock.conf"), "position", "bottom"), nil },
			set:         dockSet("position")},
		{Key: "dock.size", Group: "dock", Title: "Dock icon size", Type: "int", Min: 32, Max: 96, Step: 1, Needs: []string{"kwick-dock"},
			Description: "Icon size of the dock in pixels.",
			get: func(c *setCtx) (any, error) {
				n, _ := strconv.Atoi(keyFile(kwickConfPath("dock.conf"), "iconSize", "48"))
				return n, nil
			},
			set: dockSet("size")},
		{Key: "dock.autohide", Group: "dock", Title: "Hide the dock automatically", Type: "bool", Needs: []string{"kwick-dock"},
			get: dockBool("autohide", "off"), set: dockSet("autohide")},
		{Key: "dock.floating", Group: "dock", Title: "Floating dock", Type: "bool", Needs: []string{"kwick-dock"},
			get: dockBool("floating", "on"), set: dockSet("floating")},
		{Key: "dock.magnify", Group: "dock", Title: "Magnify icons on hover", Type: "bool", Needs: []string{"kwick-dock"},
			get: dockBool("magnify", "on"), set: dockSet("magnify")},
		{Key: "dock.apps", Group: "dock", Title: "Apps in the dock", Type: "list", MaxItems: 30, Pattern: desktopIDPat, Needs: []string{"kwick-dock"},
			Description: "Desktop file ids pinned to the dock, in order (ids come from apps_list).",
			get: func(c *setCtx) (any, error) {
				v := keyFile(kwickConfPath("dock.conf"), "pinned", "")
				out := []string{}
				for _, x := range strings.Split(v, ",") {
					if x = strings.TrimSpace(x); x != "" {
						out = append(out, x)
					}
				}
				return out, nil
			},
			set: func(c *setCtx, v any) error {
				ids := v.([]string)
				for _, id := range ids {
					if findDesktop(id) == "" {
						return fmt.Errorf("dock.apps: no application with id %q (see apps_list)", id)
					}
				}
				if len(ids) == 0 {
					return fmt.Errorf("dock.apps: keep at least one app")
				}
				if err := c.run(30*time.Second, "kwick-dock", "sync", strings.Join(ids, ",")); err != nil {
					return err
				}
				return c.run(30*time.Second, "kwick-dock", "apply")
			}},

		{Key: "effects.preset", Group: "effects", Title: "Effects preset", Type: "enum", Values: []string{"off", "subtle", "fluid", "full"}, Needs: []string{"kwick-effects"},
			Description: "off: no animations; subtle: scale, fades, blur, magic lamp; fluid: plus wobbly windows, sheets, 3D flip and Liquid Glass; full: plus flames, translucency, dimming and the cube. Reads 'custom' after single effects were changed.",
			get:         func(c *setCtx) (any, error) { return lineOf(c, "kwick-effects") },
			set:         func(c *setCtx, v any) error { return c.run(90*time.Second, "kwick-effects", v.(string)) }},
		{Key: "effects.desktop_switch", Group: "effects", Title: "Desktop switch animation", Type: "enum", Values: []string{"slide", "fade", "cube", "none"}, Needs: []string{"kwick-effects"},
			get: func(c *setCtx) (any, error) { return lineOf(c, "kwick-effects", "switch") },
			set: func(c *setCtx, v any) error { return c.run(60*time.Second, "kwick-effects", "switch", v.(string)) }},
		{Key: "effects.alt_tab", Group: "effects", Title: "Alt+Tab style", Type: "enum", Values: []string{"windows", "cover", "flip", "grid"}, Desktops: []string{"kde"}, Needs: []string{"kwick-effects"},
			get: func(c *setCtx) (any, error) { return lineOf(c, "kwick-effects", "tabbox") },
			set: func(c *setCtx, v any) error { return c.run(60*time.Second, "kwick-effects", "tabbox", v.(string)) }},
		{Key: "effects.open_close", Group: "effects", Title: "Open and close animation", Type: "enum", Values: ocStyles, Needs: []string{"kwick-effects"},
			Description: "Window open/close animation. Not every style works on every desktop; 'kwick-effects open-close list' shows which do.",
			get:         func(c *setCtx) (any, error) { return lineOf(c, "kwick-effects", "open-close") },
			set:         func(c *setCtx, v any) error { return c.run(60*time.Second, "kwick-effects", "open-close", v.(string)) }},
		{Key: "effects.open_close_duration", Group: "effects", Title: "Open and close duration", Type: "int", Min: 100, Max: 5000, Step: 10, Needs: []string{"kwick-effects"},
			Description: "Length of the current open/close animation in milliseconds.",
			get:         func(c *setCtx) (any, error) { return intOf(c, 0, "kwick-effects", "param", "duration") },
			set: func(c *setCtx, v any) error {
				return c.run(60*time.Second, "kwick-effects", "param", "duration", strconv.Itoa(v.(int)))
			}},
		{Key: "effects.wobbly_amount", Group: "effects", Title: "Wobble amount", Type: "int", Min: 1, Max: 10, Step: 1, Needs: []string{"kwick-effects"},
			get: func(c *setCtx) (any, error) { return intOf(c, 0, "kwick-effects", "param", "wobbly") },
			set: wobblySet(0)},
		{Key: "effects.wobbly_sway", Group: "effects", Title: "Wobble sway", Type: "int", Min: 1, Max: 10, Step: 1, Needs: []string{"kwick-effects"},
			get: func(c *setCtx) (any, error) { return intOf(c, 1, "kwick-effects", "param", "wobbly") },
			set: wobblySet(1)},
		{Key: "effects.flame_style", Group: "effects", Title: "Flame style", Type: "enum", Values: []string{"classic", "inferno", "ember", "blue", "legacy"}, Needs: []string{"kwick-effects"},
			get: func(c *setCtx) (any, error) { return lineOf(c, "kwick-effects", "flame-style") },
			set: func(c *setCtx, v any) error { return c.run(60*time.Second, "kwick-effects", "flame-style", v.(string)) }},
		{Key: "effects.flame_height", Group: "effects", Title: "Flame height", Type: "int", Min: 50, Max: 200, Step: 5, Needs: []string{"kwick-effects"},
			Description: "How high the flames rise, in percent.",
			get:         func(c *setCtx) (any, error) { return intOf(c, 0, "kwick-effects", "flame-height") },
			set: func(c *setCtx, v any) error {
				return c.run(60*time.Second, "kwick-effects", "flame-height", strconv.Itoa(v.(int)))
			}},
		{Key: "effects.cube_depth", Group: "effects", Title: "Window depth on the cube", Type: "int", Min: 0, Max: 10, Step: 1, Desktops: []string{"kde"}, Needs: []string{"kwick-effects"},
			get: func(c *setCtx) (any, error) { return intOf(c, 0, "kwick-effects", "param", "depth") },
			set: func(c *setCtx, v any) error {
				return c.run(60*time.Second, "kwick-effects", "param", "depth", strconv.Itoa(v.(int)))
			}},
		{Key: "effects.flip_style", Group: "effects", Title: "3D open/close style", Type: "enum", Values: []string{"flip", "door", "tilt"}, Desktops: []string{"kde"}, Needs: []string{"kwick-effects"},
			get: func(c *setCtx) (any, error) { return lineOf(c, "kwick-effects", "param", "flip") },
			set: func(c *setCtx, v any) error {
				return c.run(60*time.Second, "kwick-effects", "param", "flip", v.(string))
			}},

		{Key: "desktop.default_session", Group: "desktop", Title: "Desktop at login", Type: "enum", Values: []string{"kde", "gnome", "hyprland", "sway"}, Privileged: true, Needs: []string{"kwick-desktop"},
			Description: "Desktop session started at the next login. Needs an administrator password; takes effect after logging out.",
			get: func(c *setCtx) (any, error) {
				m := jsonOf(c, "kwick-desktop", "list", "--json")
				ds, _ := m["desktops"].([]any)
				for _, d := range ds {
					if dm, _ := d.(map[string]any); dm != nil && dm["default"] == true {
						return dm["name"], nil
					}
				}
				return nil, nil
			},
			set: func(c *setCtx, v any) error {
				m := jsonOf(c, "kwick-desktop", "list", "--json")
				ds, _ := m["desktops"].([]any)
				for _, d := range ds {
					if dm, _ := d.(map[string]any); dm != nil && dm["name"] == v && dm["installed"] != true {
						return fmt.Errorf("desktop.default_session: %s is not installed (Settings > Desktop installs it)", v)
					}
				}
				return c.priv("session", v.(string))
			}},
		{Key: "desktop.shell", Group: "desktop", Title: "Desktop shell", Type: "enum", Values: []string{"plasma", "gnome", "hyprland", "sway", "dms", "noctalia"}, Needs: []string{"kwick-desktop"},
			Description: "Bar, dock and launcher used at login. Only installed shells whose session is already the login session can be chosen here; change desktop.default_session first otherwise.",
			get:         func(c *setCtx) (any, error) { return lineOf(c, "kwick-desktop", "shell", "current") },
			set: func(c *setCtx, v any) error {
				m := jsonOf(c, "kwick-desktop", "shell", "list", "--json")
				var row map[string]any
				shells, _ := m["shells"].([]any)
				for _, x := range shells {
					if xm, _ := x.(map[string]any); xm != nil && xm["name"] == v {
						row = xm
					}
				}
				if row == nil {
					return fmt.Errorf("desktop.shell: %s is not known here", v)
				}
				if row["installed"] != true {
					return fmt.Errorf("desktop.shell: %s is not installed; install it in Settings > Shells", v)
				}
				def, _ := c.out("kwick-desktop", "shell", "current")
				if sess, _ := row["session"].(string); sess != "" && !sessionMatches(c, sess) && strings.TrimSpace(def) != v {
					return fmt.Errorf("desktop.shell: %s runs in the %s session, which is not the login session; set desktop.default_session to it first", v, sess)
				}
				return c.run(120*time.Second, "kwick-desktop", "shell", v.(string))
			}},

		{Key: "shell.login", Group: "terminal", Title: "Login shell", Type: "enum", Values: []string{"zsh", "bash", "fish", "ash", "nushell", "elvish", "xonsh", "powershell"}, Privileged: true, Needs: []string{"kwick-shell"},
			Description: "Shell of your user account in terminals. The shell must already be installed (Settings > Shells). Needs an administrator password.",
			get: func(c *setCtx) (any, error) {
				m := jsonOf(c, "kwick-shell", "list", "--json")
				if m == nil {
					return nil, nil
				}
				return m["current"], nil
			},
			set: func(c *setCtx, v any) error {
				m := jsonOf(c, "kwick-shell", "list", "--json")
				shells, _ := m["shells"].([]any)
				for _, x := range shells {
					if xm, _ := x.(map[string]any); xm != nil && xm["name"] == v && xm["installed"] != true {
						return fmt.Errorf("shell.login: %s is not installed; install it in Settings > Shells", v)
					}
				}
				return c.priv("login-shell", v.(string))
			}},
		{Key: "shell.prompt", Group: "terminal", Title: "Prompt style", Type: "enum", Values: []string{"kwick", "minimal", "powerline", "starship"}, Needs: []string{"kwick-shell"},
			get: func(c *setCtx) (any, error) {
				m := jsonOf(c, "kwick-shell", "list", "--json")
				if m == nil {
					return nil, nil
				}
				return m["prompt"], nil
			},
			set: func(c *setCtx, v any) error {
				if v == "starship" && lookPath("starship") == "" {
					return fmt.Errorf("shell.prompt: starship is not installed; install it in Settings > Shells")
				}
				return c.run(60*time.Second, "kwick-shell", "prompt", v.(string))
			}},

		{Key: "display.night_light", Group: "display", Title: "Night Light", Type: "bool", Desktops: []string{"kde", "gnome"},
			Description: "Warmer screen colors to reduce blue light (always on while enabled).",
			get: func(c *setCtx) (any, error) {
				if desktopKind() == "gnome" {
					return gsetGet(c, "org.gnome.settings-daemon.plugins.color", "night-light-enabled") == "true", nil
				}
				return kread(c, "kwinrc", "NightColor", "Active") == "true", nil
			},
			set: func(c *setCtx, v any) error {
				on := v.(bool)
				if desktopKind() == "gnome" {
					return c.run(20*time.Second, "gsettings", "set", "org.gnome.settings-daemon.plugins.color", "night-light-enabled", strconv.FormatBool(on))
				}
				if on {
					if err := c.run(20*time.Second, "kwriteconfig6", "--notify", "--file", "kwinrc", "--group", "NightColor", "--key", "Mode", "Constant"); err != nil {
						return err
					}
				}
				return c.run(20*time.Second, "kwriteconfig6", "--notify", "--file", "kwinrc", "--group", "NightColor", "--key", "Active", strconv.FormatBool(on))
			}},
		{Key: "display.brightness", Group: "display", Title: "Screen brightness", Type: "int", Min: 1, Max: 100, Step: 1, Desktops: desk,
			Description: "Brightness of the built-in or first display in percent (needs a backlight or a DDC/CI monitor).",
			get:         getBrightness, set: setBrightness},
		{Key: "display.scale", Group: "display", Title: "Display scale", Type: "number", Min: 1, Max: 3, Values: []string{"1", "1.25", "1.5", "1.75", "2", "2.25", "2.5", "3"}, Desktops: []string{"kde", "sway", "hyprland"},
			Description: "Scale factor applied to every connected display.",
			get:         getScale, set: setScale},

		{Key: "sound.volume", Group: "sound", Title: "Output volume", Type: "int", Min: 0, Max: 100, Step: 1, Needs: []string{"wpctl"},
			Description: "Volume of the default output device in percent.",
			get: func(c *setCtx) (any, error) {
				v, _, err := audioSink(c)
				if err != nil {
					return nil, err
				}
				return int(math.Round(v * 100)), nil
			},
			set: func(c *setCtx, v any) error {
				return c.run(20*time.Second, "wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", strconv.FormatFloat(float64(v.(int))/100, 'f', 2, 64))
			}},
		{Key: "sound.mute", Group: "sound", Title: "Mute output", Type: "bool", Needs: []string{"wpctl"},
			get: func(c *setCtx) (any, error) {
				_, m, err := audioSink(c)
				if err != nil {
					return nil, err
				}
				return m, nil
			},
			set: func(c *setCtx, v any) error {
				b := "0"
				if v.(bool) {
					b = "1"
				}
				return c.run(20*time.Second, "wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", b)
			}},

		{Key: "notifications.do_not_disturb", Group: "notifications", Title: "Do Not Disturb (Focus)", Type: "bool", Desktops: []string{"kde", "gnome"},
			Description: "Silence notification popups until turned off again.",
			get: func(c *setCtx) (any, error) {
				if desktopKind() == "gnome" {
					return gsetGet(c, "org.gnome.desktop.notifications", "show-banners") == "false", nil
				}
				u := kread(c, "plasmanotifyrc", "DoNotDisturb", "Until")
				if u == "" {
					return false, nil
				}
				t, err := parseKDateTime(u)
				return err == nil && t.After(time.Now()), nil
			},
			set: func(c *setCtx, v any) error {
				on := v.(bool)
				if desktopKind() == "gnome" {
					return c.run(20*time.Second, "gsettings", "set", "org.gnome.desktop.notifications", "show-banners", strconv.FormatBool(!on))
				}
				if on {
					return c.run(20*time.Second, "kwriteconfig6", "--notify", "--file", "plasmanotifyrc", "--group", "DoNotDisturb", "--key", "Until", dndUntil())
				}
				return c.run(20*time.Second, "kwriteconfig6", "--notify", "--file", "plasmanotifyrc", "--group", "DoNotDisturb", "--key", "Until", "--delete")
			}},

		{Key: "network.wifi", Group: "network", Title: "Wi-Fi", Type: "bool", Needs: []string{"nmcli"},
			Description: "Turn the Wi-Fi radio on or off. Connecting to networks is left to the user.",
			get: func(c *setCtx) (any, error) {
				o, err := c.out("nmcli", "-t", "radio", "wifi")
				if err != nil {
					return nil, err
				}
				return strings.TrimSpace(o) == "enabled", nil
			},
			set: func(c *setCtx, v any) error { return c.run(30*time.Second, "nmcli", "radio", "wifi", onOff(v)) }},
		{Key: "bluetooth.enabled", Group: "network", Title: "Bluetooth", Type: "bool", Needs: []string{"kwick-bluetooth"},
			get: func(c *setCtx) (any, error) {
				m := jsonOf(c, "kwick-bluetooth", "json")
				if m == nil {
					return nil, fmt.Errorf("kwick-bluetooth json failed")
				}
				if m["available"] != true {
					return nil, fmt.Errorf("no Bluetooth adapter")
				}
				return m["powered"], nil
			},
			set: func(c *setCtx, v any) error { return c.run(30*time.Second, "kwick-bluetooth", "power", onOff(v)) }},
		{Key: "nearby.visibility", Group: "network", Title: "Send Nearby visibility", Type: "enum", Values: []string{"off", "contacts", "everyone"}, Needs: []string{"kwick-nearby"},
			Description: "Who can see this computer for Send Nearby; 'everyone' falls back to 'contacts' after 10 minutes.",
			get: func(c *setCtx) (any, error) {
				m := jsonOf(c, "kwick-nearby", "--status")
				if m == nil {
					return nil, fmt.Errorf("kwick-nearby --status failed")
				}
				if e, ok := m["effective"]; ok {
					return e, nil
				}
				return m["visibility"], nil
			},
			set: func(c *setCtx, v any) error {
				return c.run(30*time.Second, "kwick-nearby", "--set", "visibility", v.(string))
			}},
		{Key: "nearby.name", Group: "network", Title: "Send Nearby device name", Type: "string", Pattern: aliasPat, Needs: []string{"kwick-nearby"},
			get: func(c *setCtx) (any, error) {
				m := jsonOf(c, "kwick-nearby", "--status")
				if m == nil {
					return nil, fmt.Errorf("kwick-nearby --status failed")
				}
				return m["alias"], nil
			},
			set: func(c *setCtx, v any) error {
				return c.run(30*time.Second, "kwick-nearby", "--set", "alias", v.(string))
			}},
		{Key: "power.profile", Group: "power", Title: "Power mode", Type: "enum", Values: []string{"power-saver", "balanced", "performance"},
			Description: "Power profile from power-profiles-daemon; 'performance' is only offered on hardware that supports it.",
			get:         getPowerProfile, set: setPowerProfile},

		{Key: "touch.tablet_mode", Group: "touch", Title: "Tablet mode", Type: "enum", Values: []string{"auto", "on", "off"}, Needs: []string{"kwick-touch"},
			get: func(c *setCtx) (any, error) { return keyFile(kwickConfPath("touch"), "tablet", "auto"), nil },
			set: func(c *setCtx, v any) error { return c.run(60*time.Second, "kwick-touch", "tablet", v.(string)) }},
		{Key: "touch.on_screen_keyboard", Group: "touch", Title: "On-screen keyboard", Type: "bool", Needs: []string{"kwick-touch"},
			get: func(c *setCtx) (any, error) { return keyFile(kwickConfPath("touch"), "osk", "on") == "on", nil },
			set: func(c *setCtx, v any) error { return c.run(60*time.Second, "kwick-touch", "osk", onOff(v)) }},
		{Key: "touch.rotation", Group: "touch", Title: "Screen rotation", Type: "enum", Values: []string{"auto", "locked"}, Needs: []string{"kwick-touch"},
			get: func(c *setCtx) (any, error) { return keyFile(kwickConfPath("touch"), "rotation", "auto"), nil },
			set: func(c *setCtx, v any) error { return c.run(60*time.Second, "kwick-touch", "rotation", v.(string)) }},
	}
	for _, k := range []struct{ key, cli, title string }{
		{"updates.check", "check", "Check for updates automatically"},
		{"updates.download", "download", "Download new updates when available"},
		{"updates.install_system", "system", "Install system updates automatically"},
		{"updates.install_security", "security", "Install security updates automatically"},
		{"updates.install_apps", "apps", "Install app updates from Flathub automatically"},
		{"updates.notify", "notify", "Notify about new updates"},
	} {
		k := k
		ss = append(ss, &setting{Key: k.key, Group: "updates", Title: k.title, Type: "bool", Privileged: true, Needs: []string{"kwick-update"},
			Description: "Automatic updates (kwick-update). Changing it needs an administrator password.",
			get: func(c *setCtx) (any, error) {
				a, err := updateAuto(c)
				if err != nil {
					return nil, err
				}
				return a[k.cli], nil
			},
			set: func(c *setCtx, v any) error { return c.priv("auto-update", k.cli, onOff(v)) }})
	}
	ss = append(ss, &setting{Key: "updates.interval_hours", Group: "updates", Title: "Check for updates every", Type: "int", Min: 1, Max: 168, Step: 1, Privileged: true, Needs: []string{"kwick-update"},
		Description: "Hours between background update checks (Settings offers 6, 12 and 24). Needs an administrator password.",
		get: func(c *setCtx) (any, error) {
			a, err := updateAuto(c)
			if err != nil {
				return nil, err
			}
			if f, ok := a["interval"].(float64); ok {
				return int(f), nil
			}
			return nil, nil
		},
		set: func(c *setCtx, v any) error { return c.priv("auto-update", "interval", strconv.Itoa(v.(int))) }})
	for _, fx := range fxToggles {
		fx := fx
		ss = append(ss, &setting{Key: "effects." + fx.name, Group: "effects", Title: fx.title, Type: "bool", Needs: []string{"kwick-effects"},
			Description: "Turn this effect on or off; the preset becomes 'custom'. Not every effect exists on every desktop.",
			get: func(c *setCtx) (any, error) {
				switch effectsStatus(c)[fx.name] {
				case "on":
					return true, nil
				case "off":
					return false, nil
				}
				return nil, fmt.Errorf("not available on this desktop")
			},
			set: func(c *setCtx, v any) error { return c.run(60*time.Second, "kwick-effects", "set", fx.name, onOff(v)) }})
	}
	settingsOnce = ss
	return ss
}

func sessionMatches(c *setCtx, sess string) bool {
	m := jsonOf(c, "kwick-desktop", "list", "--json")
	ds, _ := m["desktops"].([]any)
	for _, d := range ds {
		dm, _ := d.(map[string]any)
		if dm == nil || dm["default"] != true {
			continue
		}
		n, _ := dm["name"].(string)
		s, _ := dm["session"].(string)
		return n == sess || s == sess || (sess == "plasma" && n == "kde")
	}
	return false
}

func dockSet(cmd string) func(c *setCtx, v any) error {
	return func(c *setCtx, v any) error {
		var arg string
		switch x := v.(type) {
		case bool:
			arg = onOff(x)
		case int:
			arg = strconv.Itoa(x)
		case string:
			arg = x
		}
		if err := c.run(30*time.Second, "kwick-dock", cmd, arg); err != nil {
			return err
		}
		return c.run(30*time.Second, "kwick-dock", "apply")
	}
}

func dockBool(key, def string) func(c *setCtx) (any, error) {
	return func(c *setCtx) (any, error) { return keyFile(kwickConfPath("dock.conf"), key, def) == "on", nil }
}

func wobblySet(idx int) func(c *setCtx, v any) error {
	return func(c *setCtx, v any) error {
		o, _ := c.out("kwick-effects", "param", "wobbly")
		cur := strings.Fields(o)
		if len(cur) < 2 {
			cur = []string{"6", "7"}
		}
		cur[idx] = strconv.Itoa(v.(int))
		return c.run(60*time.Second, "kwick-effects", "wobbly", cur[0], cur[1])
	}
}

func parseKDateTime(s string) (time.Time, error) {
	if t, err := time.ParseInLocation("2006-01-02T15:04:05", strings.TrimSuffix(s, "Z"), time.Local); err == nil {
		return t, nil
	}
	p := strings.Split(s, ",")
	if len(p) < 6 {
		return time.Time{}, fmt.Errorf("bad date %q", s)
	}
	var n [6]int
	for i := 0; i < 6; i++ {
		f, err := strconv.ParseFloat(strings.TrimSpace(p[i]), 64)
		if err != nil {
			return time.Time{}, err
		}
		n[i] = int(f)
	}
	return time.Date(n[0], time.Month(n[1]), n[2], n[3], n[4], n[5], 0, time.Local), nil
}

func settingByKey(k string) *setting {
	for _, s := range settingsTable() {
		if s.Key == k {
			return s
		}
	}
	return nil
}

var settingsLegacy = map[string]string{"radius": "corner_radius"}

func settingKeys() []string {
	var out []string
	for _, s := range settingsTable() {
		out = append(out, s.Key)
	}
	return out
}

type settingChange struct {
	st  *setting
	val any
}

func parseSettingChanges(a map[string]any) ([]settingChange, error) {
	raw := map[string]any{}
	if m, ok := a["settings"].(map[string]any); ok {
		for k, v := range m {
			raw[k] = v
		}
	} else if _, present := a["settings"]; present {
		return nil, fmt.Errorf("settings must be an object of key: value (see settings_list)")
	}
	for _, k := range []string{"appearance", "layout"} {
		if v, ok := a[k]; ok {
			raw[k] = v
		}
	}
	for k := range a {
		if k != "settings" && k != "appearance" && k != "layout" {
			return nil, fmt.Errorf("unknown argument %q; put settings inside \"settings\": {\"key\": value}", k)
		}
	}
	if len(raw) == 0 {
		return nil, fmt.Errorf("give at least one setting, for example {\"settings\": {\"appearance\": \"light\"}}; settings_list shows them all")
	}
	if len(raw) > 20 {
		return nil, fmt.Errorf("at most 20 settings per call")
	}
	keys := make([]string, 0, len(raw))
	for k := range raw {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var out []settingChange
	for _, k := range keys {
		key := k
		if l, ok := settingsLegacy[k]; ok {
			key = l
		}
		st := settingByKey(key)
		if st == nil {
			return nil, fmt.Errorf("unknown setting %q; settings_list shows the valid keys", k)
		}
		v, err := validateSetting(st, raw[k])
		if err != nil {
			return nil, err
		}
		out = append(out, settingChange{st, v})
	}
	sort.SliceStable(out, func(i, j int) bool { return settingOrder(out[i].st) < settingOrder(out[j].st) })
	return out, nil
}

func settingOrder(st *setting) int {
	switch st.Key {
	case "layout":
		return 0
	case "appearance":
		return 1
	case "effects.preset":
		return 2
	}
	return 10
}

func fmtVal(v any) string {
	switch x := v.(type) {
	case []string:
		return strings.Join(x, ", ")
	case string:
		return x
	}
	b, _ := json.Marshal(v)
	return string(b)
}

func settingsDetail(s *Server, a map[string]any) string {
	ch, err := parseSettingChanges(a)
	if err != nil {
		return "Change settings"
	}
	var p []string
	priv := false
	for _, c := range ch {
		p = append(p, c.st.Title+" to "+fmtVal(c.val))
		priv = priv || c.st.Privileged
	}
	d := "Change " + strings.Join(p, "; ")
	if priv {
		d += " (an administrator password is asked next)"
	}
	return d
}

func settingsPrecheck(s *Server, a map[string]any) error {
	ch, err := parseSettingChanges(a)
	if err != nil {
		return err
	}
	for _, c := range ch {
		if ok, why := c.st.available(); !ok {
			return fmt.Errorf("%s: %s", c.st.Key, why)
		}
		if c.st.Type == "path" {
			if _, err := wallpaperAllowed(c.val.(string)); err != nil {
				return err
			}
		}
	}
	return nil
}

func readSettings(c *setCtx, sts []*setting) (map[string]any, map[string]string) {
	vals := map[string]any{}
	errs := map[string]string{}
	var mu sync.Mutex
	var wg sync.WaitGroup
	sem := make(chan struct{}, 6)
	for _, st := range sts {
		if ok, why := st.available(); !ok {
			errs[st.Key] = why
			continue
		}
		wg.Add(1)
		go func(st *setting) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			v, err := st.get(c)
			mu.Lock()
			defer mu.Unlock()
			if err != nil {
				errs[st.Key] = err.Error()
				return
			}
			vals[st.Key] = v
		}(st)
	}
	wg.Wait()
	return vals, errs
}

func selectSettings(a map[string]any) ([]*setting, error) {
	keys := argStrings(a, "keys")
	group := argStr(a, "group")
	var out []*setting
	if len(keys) > 0 {
		for _, k := range keys {
			if l, ok := settingsLegacy[k]; ok {
				k = l
			}
			st := settingByKey(k)
			if st == nil {
				return nil, fmt.Errorf("unknown setting %q; settings_list shows the valid keys", k)
			}
			out = append(out, st)
		}
		return out, nil
	}
	for _, st := range settingsTable() {
		if group == "" || st.Group == group {
			out = append(out, st)
		}
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("unknown group %q (one of: %s)", group, strings.Join(settingGroups(), ", "))
	}
	return out, nil
}

func settingGroups() []string {
	seen := map[string]bool{}
	var out []string
	for _, st := range settingsTable() {
		if !seen[st.Group] {
			seen[st.Group] = true
			out = append(out, st.Group)
		}
	}
	return out
}

func toolSettingsList(s *Server, a map[string]any) (toolResult, error) {
	sts, err := selectSettings(a)
	if err != nil {
		return toolResult{}, err
	}
	var vals map[string]any
	var errs map[string]string
	withValues := true
	if b, ok := a["values"].(bool); ok {
		withValues = b
	}
	if withValues {
		vals, errs = readSettings(newSetCtx(s.agent), sts)
	}
	var list []map[string]any
	for _, st := range sts {
		d := st.describe()
		if withValues {
			if v, ok := vals[st.Key]; ok {
				d["value"] = v
			} else if e, ok := errs[st.Key]; ok && d["available"] == true {
				d["error"] = e
			}
		}
		list = append(list, d)
	}
	return toolResult{Data: map[string]any{"desktop": desktopKind(), "groups": settingGroups(), "count": len(list), "settings": list,
		"how": "Change with settings_set {\"settings\": {\"key\": value}}. privileged settings also ask for an administrator password."}}, nil
}

func toolSettingsGet(s *Server, a map[string]any) (toolResult, error) {
	sts, err := selectSettings(a)
	if err != nil {
		return toolResult{}, err
	}
	vals, errs := readSettings(newSetCtx(s.agent), sts)
	out := map[string]any{"desktop": desktopKind(), "edition": edition(), "values": vals}
	if len(errs) > 0 {
		out["unavailable"] = errs
	}
	if len(argStrings(a, "keys")) == 0 && argStr(a, "group") == "" {
		for _, k := range []string{"layout", "appearance"} {
			out[k] = vals[k]
		}
		out["radius"] = vals["corner_radius"]
	}
	return toolResult{Data: out}, nil
}

func toolSettingsSet(s *Server, a map[string]any) (toolResult, error) {
	ch, err := parseSettingChanges(a)
	if err != nil {
		return toolResult{}, err
	}
	c := newSetCtx(s.agent)
	done := map[string]any{}
	failed := map[string]string{}
	for _, x := range ch {
		if err := x.st.set(c, x.val); err != nil {
			failed[x.st.Key] = err.Error()
			continue
		}
		done[x.st.Key] = x.val
	}
	var sts []*setting
	for _, x := range ch {
		sts = append(sts, x.st)
	}
	now, _ := readSettings(newSetCtx(s.agent), sts)
	out := map[string]any{"changed": done, "now": now}
	if len(c.log) > 0 {
		out["log"] = strings.Join(c.log, "\n")
	}
	if len(failed) > 0 {
		out["failed"] = failed
		if len(done) == 0 {
			var msgs []string
			for k, v := range failed {
				msgs = append(msgs, k+": "+v)
			}
			sort.Strings(msgs)
			return toolResult{}, fmt.Errorf("%s", strings.Join(msgs, "; "))
		}
	}
	return toolResult{Data: out}, nil
}
