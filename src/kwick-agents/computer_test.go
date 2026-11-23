package main

import (
	"bytes"
	"encoding/json"
	"image"
	"image/color"
	"image/png"
	"math"
	"strings"
	"testing"
	"time"
)

func TestParseKeyCombo(t *testing.T) {
	cases := map[string]string{
		"enter":        "Return",
		"Return":       "Return",
		"ctrl+s":       "ctrl+s",
		"Ctrl+Shift+T": "ctrl+shift+t",
		"alt+f4":       "alt+F4",
		"super":        "Super_L",
		"ctrl++":       "ctrl+plus",
		"ctrl+/":       "ctrl+slash",
		"shift+tab":    "shift+Tab",
		"cmd+space":    "logo+space",
		"a":            "a",
		"A":            "A",
		"pagedown":     "Next",
	}
	for in, want := range cases {
		k, err := parseKeyCombo(in)
		if err != nil {
			t.Fatalf("%s: %v", in, err)
		}
		if k.String() != want {
			t.Fatalf("%s: got %s want %s", in, k.String(), want)
		}
	}
	for _, in := range []string{"", "ctrl+", "hyper+a", "ctrl+ctrl+a", "ctrl+banana", "f25", strings.Repeat("a", 70), "\x01"} {
		if k, err := parseKeyCombo(in); err == nil {
			t.Fatalf("%q accepted as %s", in, k.String())
		}
	}
	k, _ := parseKeyCombo("ctrl+shift+t")
	if strings.Join(k.wtypeArgs(), " ") != "-M ctrl -M shift -k t -m shift -m ctrl" {
		t.Fatalf("wtype args %v", k.wtypeArgs())
	}
	if k.mods[0].sym != 0xffe3 || k.key.sym != 't' {
		t.Fatal("keysyms")
	}
	if runeKeysym('é') != 0xe9 || runeKeysym('€') != 0x010020ac || runeKeysym('\n') != 0xff0d {
		t.Fatal("rune keysyms")
	}
}

func testPNG(w, h int) image.Image {
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			img.Set(x, y, color.RGBA{uint8(x), uint8(y), 0, 255})
		}
	}
	return img
}

func TestProcessShotScalesAndMaps(t *testing.T) {
	raw := testPNG(400, 200)
	img, mime, g, err := processShot(raw, rectF{0, 0, 200, 100}, nil, 100, 100, "png", 0)
	if err != nil {
		t.Fatal(err)
	}
	if mime != "image/png" || g.Width != 100 || g.Height != 50 {
		t.Fatalf("got %s %dx%d", mime, g.Width, g.Height)
	}
	if math.Abs(g.Scale-2) > 1e-9 {
		t.Fatalf("scale %v (100 image px cover 200 desktop px)", g.Scale)
	}
	x, y := g.toScreen(50, 25)
	if x != 100 || y != 50 {
		t.Fatalf("center maps to %v,%v", x, y)
	}
	dec, err := png.Decode(bytes.NewReader(img))
	if err != nil || dec.Bounds().Dx() != 100 {
		t.Fatal("output is not a 100px PNG")
	}
	_, _, g, err = processShot(raw, rectF{0, 0, 200, 100}, &rectF{50, 25, 100, 50}, 1280, 800, "jpeg", 80)
	if err != nil {
		t.Fatal(err)
	}
	if g.Width != 200 || g.Height != 100 || g.OriginX != 50 || g.OriginY != 25 || math.Abs(g.Scale-0.5) > 1e-9 {
		t.Fatalf("region geometry %+v", g)
	}
	if x, y := g.toScreen(0, 0); x != 50 || y != 25 {
		t.Fatalf("region origin maps to %v,%v", x, y)
	}
	if _, _, _, err := processShot(raw, rectF{0, 0, 200, 100}, &rectF{500, 500, 10, 10}, 1280, 800, "png", 0); err == nil {
		t.Fatal("region outside the screen accepted")
	}
	if _, _, _, err := processShot(image.NewRGBA(image.Rect(0, 0, 0, 0)), rectF{}, nil, 100, 100, "png", 0); err == nil {
		t.Fatal("empty image accepted")
	}
	bgra := []byte{1, 2, 3, 255, 4, 5, 6, 255}
	ri, err := rawToRGBA(bgra, 2, 1, 8, 6)
	if err != nil || ri.RGBAAt(0, 0) != (color.RGBA{3, 2, 1, 255}) {
		t.Fatalf("BGRA conversion: %v %v", ri, err)
	}
	if _, err := rawToRGBA(bgra, 3, 1, 8, 6); err == nil {
		t.Fatal("short buffer accepted")
	}
	if _, err := rawToRGBA(bgra, 2, 1, 8, 99); err == nil {
		t.Fatal("unknown format accepted")
	}
	_, _, g, _ = processShot(raw, rectF{}, nil, 1280, 800, "png", 0)
	if g.Width != 400 || g.Scale != 1 {
		t.Fatalf("no upscaling expected: %+v", g)
	}
}

func TestDownscaleAverages(t *testing.T) {
	src := image.NewRGBA(image.Rect(0, 0, 4, 2))
	for i := range src.Pix {
		src.Pix[i] = 255
	}
	src.Set(0, 0, color.RGBA{0, 0, 0, 255})
	src.Set(1, 0, color.RGBA{0, 0, 0, 255})
	src.Set(0, 1, color.RGBA{0, 0, 0, 255})
	src.Set(1, 1, color.RGBA{0, 0, 0, 255})
	d := downscale(src, 2, 1)
	if d.RGBAAt(0, 0).R != 0 || d.RGBAAt(1, 0).R != 255 {
		t.Fatalf("got %v %v", d.RGBAAt(0, 0), d.RGBAAt(1, 0))
	}
	if w, h := fitSize(1920, 1080, 1280, 800); w != 1280 || h != 720 {
		t.Fatalf("fit %dx%d", w, h)
	}
	if w, h := fitSize(3840, 2400, 1280, 800); w != 1280 || h != 800 {
		t.Fatalf("fit %dx%d", w, h)
	}
}

func TestProtectedWindows(t *testing.T) {
	prot := []winInfo{
		{App: "org.kde.polkit-kde-authentication-agent-1"},
		{App: "polkit-kde-authentication-agent-1"},
		{App: "kwalletd6"},
		{App: "pinentry-qt"},
		{App: "gcr-prompter"},
		{App: "xdg-desktop-portal-kde", Title: "Remote control requested"},
		{App: "kdialog", Title: "KwickOS: allow an AI agent?"},
		{App: "zenity", Title: "KwickOS: allow an AI agent?"},
		{App: "kwick-settings", Title: "Settings"},
		{App: "", Title: "Authentication Required", extra: []string{"x"}},
		{App: "foo", extra: []string{"org.kde.ksshaskpass.desktop"}},
		{App: "hyprpolkitagent"},
	}
	for _, w := range prot {
		if protectedReason(w) == "" {
			t.Fatalf("%+v is not protected", w)
		}
	}
	for _, w := range []winInfo{{App: "org.kde.kate", Title: "notes.txt - Kate"}, {App: "firefox-esr", Title: "Polkit docs - Firefox"}, {App: "org.kde.dolphin", Title: "Home"}} {
		if r := protectedReason(w); r != "" {
			t.Fatalf("%+v is protected: %s", w, r)
		}
	}
}

func TestComputerToolsAreDeclared(t *testing.T) {
	want := []string{"screen_info", "screenshot", "pointer_move", "pointer_click", "pointer_drag", "scroll", "key_press", "type_text",
		"windows_list", "window_focus", "window_close", "window_move_resize", "clipboard_get", "clipboard_set", "computer_release",
		"settings_list", "settings_get", "settings_set"}
	have := map[string]tool{}
	for _, tl := range toolTable() {
		if _, dup := have[tl.Name]; dup {
			t.Fatalf("duplicate tool %s", tl.Name)
		}
		have[tl.Name] = tl
		if _, ok := capByName(tl.Cap); !ok {
			t.Fatalf("%s uses unknown capability %s", tl.Name, tl.Cap)
		}
		if _, err := json.Marshal(tl.describe()); err != nil {
			t.Fatalf("%s: %v", tl.Name, err)
		}
	}
	for _, n := range want {
		if _, ok := have[n]; !ok {
			t.Fatalf("missing tool %s", n)
		}
	}
	for _, n := range []string{"pointer_move", "pointer_click", "type_text", "key_press", "windows_list", "clipboard_get", "clipboard_set", "screen_info"} {
		if have[n].Cap != ctlCap {
			t.Fatalf("%s needs %s", n, ctlCap)
		}
	}
	c, _ := capByName(ctlCap)
	if c.Default != "ask" {
		t.Fatalf("computer.control default %s", c.Default)
	}
}

func TestControlNeedsConsentAndSession(t *testing.T) {
	testHome(t)
	t.Setenv("KWICK_AGENTS_CONSENT_WAIT", "200ms")
	t.Setenv("WAYLAND_DISPLAY", "")
	t.Setenv("DISPLAY", "")
	s := newServer("test", nil, false)
	res, _ := s.callTool("type_text", map[string]any{"text": "hello"})
	if res["isError"] != true {
		t.Fatalf("type_text without a desktop succeeded: %v", res)
	}
	if s.shared.active() != nil {
		t.Fatal("a session started without consent")
	}
	t.Setenv("WAYLAND_DISPLAY", "wayland-test")
	res, _ = s.callTool("windows_list", map[string]any{})
	if txt := res["content"].([]map[string]any)[0]["text"].(string); !strings.Contains(txt, "did not answer") {
		t.Fatalf("expected an unanswered consent request, got %s", txt)
	}
	if s.shared.active() != nil {
		t.Fatal("a session started without consent")
	}
	setGrant("test", ctlCap, "deny")
	res, _ = s.callTool("pointer_move", map[string]any{"x": float64(1), "y": float64(1)})
	if txt := res["content"].([]map[string]any)[0]["text"].(string); !strings.HasPrefix(txt, "Denied") {
		t.Fatalf("expected denied, got %s", txt)
	}
	res, _ = s.callTool("computer_release", map[string]any{})
	if txt := res["content"].([]map[string]any)[0]["text"].(string); !strings.HasPrefix(txt, "Denied") {
		t.Fatalf("release with deny: %s", txt)
	}
}

func TestControlSessionLimitsAndStop(t *testing.T) {
	testHome(t)
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/nonexistent")
	s := newServer("test", nil, false)
	c, err := s.shared.startControl(s, "test")
	if err != nil {
		t.Fatal(err)
	}
	if s.shared.active() != c {
		t.Fatal("session not active")
	}
	n := 0
	for i := 0; i < 100; i++ {
		if c.take(1) == nil {
			n++
		}
	}
	if n < 25 || n > 35 {
		t.Fatalf("burst allowed %d actions", n)
	}
	if err := c.take(1); err == nil || !strings.Contains(err.Error(), "rate limit") {
		t.Fatalf("expected rate limit, got %v", err)
	}
	if !exists(c.marker) {
		t.Fatal("no session marker")
	}
	if err := cmdControl(opts{json: true}, []string{"stop"}); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(3 * time.Second)
	for s.shared.active() != nil && time.Now().Before(deadline) {
		time.Sleep(50 * time.Millisecond)
	}
	if s.shared.active() != nil {
		t.Fatal("kwick-agents control stop did not end the session")
	}
	if c.reason != "stopped by the user" {
		t.Fatalf("reason %q", c.reason)
	}
	es := readAudit("test", 0)
	found := false
	for _, e := range es {
		if e.Tool == "control" && e.Decision == "stop" {
			found = true
		}
	}
	if !found {
		t.Fatal("the stop was not audited")
	}
}

func TestSplitASCII(t *testing.T) {
	got := splitASCII("Hi \u00dcn\u00ef x\u20ac")
	want := []string{"Hi ", "\u00dc", "n", "\u00ef", " x", "\u20ac"}
	if strings.Join(got, "|") != strings.Join(want, "|") {
		t.Fatalf("got %q", got)
	}
	if !isASCII("plain\ntext") || isASCII("\u00e9") {
		t.Fatal("isASCII")
	}
}

func TestPointMapping(t *testing.T) {
	t.Setenv("XDG_CURRENT_DESKTOP", "")
	s := newServer("test", nil, false)
	if _, _, err := s.point(map[string]any{"x": float64(10)}, "x", "y"); err == nil {
		t.Fatal("missing y accepted")
	}
	p, sp, err := s.point(map[string]any{"x": float64(10), "y": float64(20)}, "x", "y")
	if err != nil || sp != "screen" || p != [2]float64{10, 20} {
		t.Fatalf("screen space: %v %s %v", p, sp, err)
	}
	if _, _, err := s.point(map[string]any{"x": float64(10), "y": float64(20), "space": "image"}, "x", "y"); err == nil {
		t.Fatal("image space without a screenshot accepted")
	}
	s.shared.setShot(shotGeom{OriginX: 100, OriginY: 0, Scale: 1.5, Width: 1280, Height: 720})
	p, sp, err = s.point(map[string]any{"x": float64(100), "y": float64(200)}, "x", "y")
	if err != nil || sp != "image" || p != [2]float64{250, 300} {
		t.Fatalf("image space: %v %s %v", p, sp, err)
	}
	if _, _, err := s.point(map[string]any{"x": float64(1281), "y": float64(0)}, "x", "y"); err == nil {
		t.Fatal("point outside the screenshot accepted")
	}
	if _, _, err := s.point(map[string]any{"x": "NaN", "y": float64(0), "space": "screen"}, "x", "y"); err == nil {
		t.Fatal("NaN accepted")
	}
}
