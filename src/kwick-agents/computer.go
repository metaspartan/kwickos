package main

import (
	"bufio"
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

const ctlCap = "computer.control"

type inputBackend interface {
	name() string
	move(x, y float64) error
	button(btn string, down bool) error
	scroll(dx, dy int) error
	combo(k keyCombo) error
	typeText(s string) error
	close()
}

type clicker interface {
	click(btn string, n int) error
}

type winInfo struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	App       string `json:"app"`
	PID       int    `json:"pid,omitempty"`
	X         int    `json:"x"`
	Y         int    `json:"y"`
	Width     int    `json:"width"`
	Height    int    `json:"height"`
	Active    bool   `json:"active"`
	Minimized bool   `json:"minimized,omitempty"`
	Output    string `json:"output,omitempty"`
	Kind      string `json:"kind"`
	Protected string `json:"protected,omitempty"`
	Stack     int    `json:"-"`
	extra     []string
}

type screenInfo struct {
	Name   string  `json:"name"`
	X      int     `json:"x"`
	Y      int     `json:"y"`
	Width  int     `json:"width"`
	Height int     `json:"height"`
	Scale  float64 `json:"scale"`
}

type wmBackend interface {
	wmName() string
	windows() ([]winInfo, error)
	screens() ([]screenInfo, error)
	focus(id string) error
	closeWin(id string) error
	moveResize(id string, x, y, w, h *int) error
}

type brokerState struct {
	mu    sync.Mutex
	agent string
	ctl   *ctlSession
	shot  *shotGeom
}

type ctlSession struct {
	id      string
	agent   string
	client  string
	started time.Time
	expires time.Time
	lastUse time.Time
	in      inputBackend
	inErr   error
	note    *notifyHandle
	noteCmd *exec.Cmd
	pill    *exec.Cmd
	hotkey  func()
	marker  string
	done    chan struct{}
	once    sync.Once
	mu      sync.Mutex
	tokens  float64
	tokAt   time.Time
	actions int
	reason  string
	state   *brokerState
}

func ctlLimits() (time.Duration, time.Duration) {
	total, idle := 60*time.Minute, 15*time.Minute
	if v, err := strconv.Atoi(os.Getenv("KWICK_AGENTS_CONTROL_MINUTES")); err == nil && v > 0 && v <= 24*60 {
		total = time.Duration(v) * time.Minute
	}
	if v, err := strconv.Atoi(os.Getenv("KWICK_AGENTS_CONTROL_IDLE_MINUTES")); err == nil && v > 0 && v <= 24*60 {
		idle = time.Duration(v) * time.Minute
	}
	return total, idle
}

func controlDir() string { return filepath.Join(runtimeDir(), "control") }

func (st *brokerState) active() *ctlSession {
	st.mu.Lock()
	defer st.mu.Unlock()
	if st.ctl == nil {
		return nil
	}
	select {
	case <-st.ctl.done:
		st.ctl = nil
		return nil
	default:
	}
	return st.ctl
}

func (st *brokerState) lastShot() *shotGeom {
	st.mu.Lock()
	defer st.mu.Unlock()
	return st.shot
}

func (st *brokerState) setShot(g shotGeom) {
	st.mu.Lock()
	st.shot = &g
	st.mu.Unlock()
}

func (st *brokerState) stopControl(reason string) {
	if c := st.active(); c != nil {
		c.stop(reason)
	}
}

type ctlMarker struct {
	ID      string `json:"id"`
	Agent   string `json:"agent"`
	Client  string `json:"client,omitempty"`
	PID     int    `json:"pid"`
	Started string `json:"started"`
	Expires string `json:"expires"`
	Desktop string `json:"desktop"`
}

func (st *brokerState) startControl(s *Server, how string) (*ctlSession, error) {
	st.mu.Lock()
	if st.ctl != nil {
		select {
		case <-st.ctl.done:
		default:
			c := st.ctl
			st.mu.Unlock()
			return c, nil
		}
	}
	total, _ := ctlLimits()
	b := make([]byte, 4)
	rand.Read(b)
	c := &ctlSession{id: hex.EncodeToString(b), agent: s.agent, client: s.client, started: time.Now(), expires: time.Now().Add(total), lastUse: time.Now(),
		done: make(chan struct{}), tokens: 30, tokAt: time.Now(), state: st}
	st.ctl = c
	st.mu.Unlock()
	os.MkdirAll(controlDir(), 0o700)
	c.marker = filepath.Join(controlDir(), c.id+".json")
	if err := writeJSONFile(c.marker, ctlMarker{ID: c.id, Agent: c.agent, Client: c.client, PID: os.Getpid(), Started: c.started.UTC().Format(time.RFC3339),
		Expires: c.expires.UTC().Format(time.RFC3339), Desktop: desktopKind()}, 0o600); err != nil {
		c.stop("could not record the session")
		return nil, err
	}
	c.showIndicator(s)
	auditLog(auditEntry{Agent: c.agent, Client: c.client, Tool: "control", Capability: ctlCap, Decision: how, OK: true,
		Summary: fmt.Sprintf("computer control started (session %s, until %s)", c.id, c.expires.Format("15:04"))})
	go c.watch()
	return c, nil
}

func (c *ctlSession) watch() {
	t := time.NewTicker(500 * time.Millisecond)
	defer t.Stop()
	_, idle := ctlLimits()
	for {
		select {
		case <-c.done:
			return
		case <-t.C:
			if !exists(c.marker) {
				c.stop("stopped by the user")
				return
			}
			c.mu.Lock()
			last := c.lastUse
			c.mu.Unlock()
			if time.Now().After(c.expires) {
				c.stop("time limit reached")
				return
			}
			if time.Since(last) > idle {
				c.stop("idle for " + idle.String())
				return
			}
		}
	}
}

func (c *ctlSession) stop(reason string) {
	c.once.Do(func() {
		c.mu.Lock()
		c.reason = reason
		in := c.in
		c.in = nil
		note, pill := c.note, c.pill
		c.mu.Unlock()
		close(c.done)
		if in != nil {
			in.close()
		}
		if c.hotkey != nil {
			c.hotkey()
		}
		if note != nil {
			note.close()
		}
		if pill != nil && pill.Process != nil {
			pill.Process.Kill()
		}
		if c.noteCmd != nil && c.noteCmd.Process != nil {
			c.noteCmd.Process.Kill()
		}
		os.Remove(c.marker)
		if b, err := sessionBus(); err == nil {
			b.notify("AI agent control ended", fmt.Sprintf("%s no longer controls the pointer and keyboard (%s).", agentTitle(c.agent), reason), "input-mouse", 1, false, nil, nil, nil)
		}
		auditLog(auditEntry{Agent: c.agent, Client: c.client, Tool: "control", Capability: ctlCap, Decision: "stop", OK: true,
			Summary: fmt.Sprintf("computer control ended (session %s): %s, %d actions", c.id, reason, c.actions)})
	})
}

func (c *ctlSession) alive() bool {
	select {
	case <-c.done:
		return false
	default:
		return true
	}
}

func (c *ctlSession) take(cost float64) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	now := time.Now()
	c.tokens = math.Min(30, c.tokens+now.Sub(c.tokAt).Seconds()*15)
	c.tokAt = now
	if c.tokens < cost {
		return fmt.Errorf("rate limit: at most 15 input actions per second; wait %.1fs and try again", (cost-c.tokens)/15)
	}
	c.tokens -= cost
	c.actions++
	c.lastUse = now
	return nil
}

func agentTitle(agent string) string {
	if cat, err := loadCatalog(); err == nil {
		if e, ok := cat.byName[agent]; ok && e.Title != "" {
			return e.Title
		}
	}
	return agent
}

func hotkeyText() string {
	switch desktopKind() {
	case "kde", "sway", "hyprland":
		return "press Meta+Alt+Escape or "
	}
	return ""
}

func (c *ctlSession) showIndicator(s *Server) {
	title := agentTitle(c.agent) + " is controlling this computer"
	body := fmt.Sprintf("The AI agent can move the pointer, click, type and manage windows until %s. To take control back, %sclick Stop.", c.expires.Format("15:04"), hotkeyText())
	if b, err := sessionBus(); err == nil {
		b.mu.Lock()
		b.onStop = func(reason string) {
			stopAllMarkers("stopped with the keyboard shortcut")
			if cur := c.state.active(); cur == c {
				c.stop("stopped with the keyboard shortcut")
			}
		}
		b.mu.Unlock()
		b.conn.RequestName(controlBusName, 0)
		prevHotkey := c.hotkey
		c.hotkey = func() {
			b.conn.ReleaseName(controlBusName)
			if prevHotkey != nil {
				prevHotkey()
			}
		}
		if !c.startPill(func() { c.notifyFallback(b, title, body) }) {
			c.notifyFallback(b, title, body)
		}
		if desktopKind() == "kde" {
			b.kwinHotkey()
		}
	} else if c.startPill(nil) {
	} else if lookPath("notify-send") != "" {
		cmd := exec.Command("notify-send", "--app-name=KwickOS Agents", "--urgency=critical", "--icon=input-mouse", "--wait", "--action=stop=Stop", title, body)
		var out bytes.Buffer
		cmd.Stdout = &out
		if cmd.Start() == nil {
			c.noteCmd = cmd
			go func() {
				cmd.Wait()
				if strings.TrimSpace(out.String()) == "stop" {
					c.stop("stopped from the notification")
				}
			}()
		}
	}
	self, err := os.Executable()
	if err != nil {
		self = selfPath
	}
	switch desktopKind() {
	case "sway":
		if exec.Command("swaymsg", "bindsym", "--no-warn", "Mod4+Mod1+Escape", "exec", self, "control", "stop").Run() == nil {
			prev := c.hotkey
			c.hotkey = func() {
				exec.Command("swaymsg", "unbindsym", "Mod4+Mod1+Escape").Run()
				if prev != nil {
					prev()
				}
			}
		}
	case "hyprland":
		if exec.Command("hyprctl", "keyword", "bind", "SUPER ALT,Escape,exec,"+self+" control stop").Run() == nil {
			c.hotkey = func() { exec.Command("hyprctl", "keyword", "unbind", "SUPER ALT,Escape").Run() }
		}
	}
}

func (c *ctlSession) notifyFallback(b *bus, title, body string) {
	if !c.alive() {
		return
	}
	if h, err := b.notify(title, body, "input-mouse", 2, true, []string{"stop", "Stop", "default", "Stop"}, func(a string) {
		if a == "stop" || a == "default" {
			c.stop("stopped from the notification")
		}
	}, nil); err == nil {
		c.mu.Lock()
		c.note = h
		c.mu.Unlock()
	}
}

func indicatorQML() string {
	if p := os.Getenv("KWICK_AGENTS_INDICATOR_QML"); p != "" && filepath.IsAbs(p) && exists(p) {
		return p
	}
	return filepath.Join(libDir, "indicator.qml")
}

type pillConfig struct {
	Agent      string `json:"agent"`
	Appearance string `json:"appearance"`
	Layout     string `json:"layout"`
	Accent     string `json:"accent,omitempty"`
	Until      string `json:"until"`
	Hotkey     string `json:"hotkey,omitempty"`
}

func currentAccentHex() string {
	if desktopKind() == "gnome" {
		if n := gsetGet(newSetCtx(""), "org.gnome.desktop.interface", "accent-color"); n != "" {
			if n == "slate" {
				n = "graphite"
			}
			return accentHex[n]
		}
		return ""
	}
	rgb := strings.Split(strings.ReplaceAll(kread(newSetCtx(""), "kdeglobals", "General", "AccentColor"), " ", ""), ",")
	if len(rgb) < 3 {
		return ""
	}
	var v [3]int
	for i := 0; i < 3; i++ {
		n, err := strconv.Atoi(rgb[i])
		if err != nil || n < 0 || n > 255 {
			return ""
		}
		v[i] = n
	}
	return fmt.Sprintf("#%02x%02x%02x", v[0], v[1], v[2])
}

func (c *ctlSession) startPill(onCrash func()) bool {
	switch desktopKind() {
	case "kde", "sway", "hyprland":
	default:
		return false
	}
	qml := lookPath("qml6")
	if qml == "" || !exists(indicatorQML()) || os.Getenv("WAYLAND_DISPLAY") == "" {
		return false
	}
	layout := "macos"
	if b, err := os.ReadFile(kwickConfPath("layout")); err == nil && len(strings.TrimSpace(string(b))) > 0 {
		layout = strings.TrimSpace(string(b))
	}
	app := "dark"
	if b, err := os.ReadFile(kwickConfPath("appearance")); err == nil && strings.TrimSpace(string(b)) == "light" {
		app = "light"
	}
	hk := "Meta+Alt+Esc"
	if layout == "windows" {
		hk = "Win+Alt+Esc"
	}
	cfg, _ := json.Marshal(pillConfig{Agent: agentTitle(c.agent), Appearance: app, Layout: layout, Accent: currentAccentHex(), Until: c.expires.Format("15:04"), Hotkey: hk})
	cmd := exec.Command(qml, indicatorQML(), "--", string(cfg))
	cmd.Env = append(os.Environ(), "QT_QPA_PLATFORM=wayland")
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return false
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if cmd.Start() != nil {
		return false
	}
	c.mu.Lock()
	c.pill = cmd
	c.mu.Unlock()
	go func() {
		stopped := false
		sc := bufio.NewScanner(stderr)
		for sc.Scan() {
			l := strings.TrimSpace(sc.Text())
			if l == "stop" || strings.HasSuffix(l, ": stop") {
				stopped = true
				c.stop("stopped with the Stop button")
			}
		}
		cmd.Wait()
		if !stopped && c.alive() && onCrash != nil {
			onCrash()
		}
	}()
	return true
}

func (c *ctlSession) input() (inputBackend, error) {
	c.mu.Lock()
	if c.in != nil {
		in := c.in
		c.mu.Unlock()
		return in, nil
	}
	c.mu.Unlock()
	in, err := newInput()
	if err != nil {
		return nil, err
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if !c.alive() {
		in.close()
		return nil, fmt.Errorf("the control session ended")
	}
	c.in = in
	if p, ok := in.(*portalBackend); ok {
		p.setOnClose(func() { c.stop("the remote desktop session was closed from the system") })
	}
	return in, nil
}

func newInput() (inputBackend, error) {
	switch desktopKind() {
	case "sway":
		if lookPath("swaymsg") == "" {
			return nil, fmt.Errorf("swaymsg is not installed")
		}
		return &swayInput{}, nil
	case "hyprland":
		if lookPath("hyprctl") == "" {
			return nil, fmt.Errorf("hyprctl is not installed")
		}
		return &hyprInput{}, nil
	}
	b, err := sessionBus()
	if err != nil {
		return nil, err
	}
	p, err := newPortalBackend(b)
	if err != nil {
		if lookPath("ydotool") != "" && exists(ydotoolSocket()) {
			return &ydoInput{}, nil
		}
		return nil, err
	}
	return p, nil
}

func currentWM() wmBackend {
	switch desktopKind() {
	case "kde":
		return &kwinWM{}
	case "sway":
		return &swayWM{}
	case "hyprland":
		return &hyprWM{}
	}
	return nil
}

var protectedApps = []string{
	"polkit-kde-authentication-agent-1", "org.kde.polkit-kde-authentication-agent-1", "polkit-gnome-authentication-agent-1", "polkit-mate-authentication-agent-1",
	"lxpolkit", "lxqt-policykit-agent", "hyprpolkitagent", "org.hyprland.hyprpolkitagent", "soteria", "polkit-agent-helper-1",
	"kwalletd5", "kwalletd6", "org.kde.kwalletd5", "org.kde.kwalletd6", "ksecretd", "org.kde.ksecretd", "gcr-prompter", "org.gnome.keyring.systemprompter",
	"ksshaskpass", "org.kde.ksshaskpass", "ssh-askpass", "gnome-ssh-askpass", "lxqt-openssh-askpass",
	"kscreenlocker_greet", "sddm", "sddm-greeter", "sddm-greeter-qt6", "swaylock", "hyprlock", "gtklock", "waylock", "gdm",
	"xdg-desktop-portal-kde", "org.freedesktop.impl.portal.desktop.kde", "xdg-desktop-portal-gnome", "xdg-desktop-portal-gtk",
}

var settingsApps = []string{"kwick-settings", "kwick-settings-app", "org.kwickos.settings", "org.kwickos.settings.qml"}

func protectedReason(w winInfo) string {
	fields := append([]string{w.App}, w.extra...)
	for _, f := range fields {
		lf := strings.ToLower(f)
		if lf == "" {
			continue
		}
		for _, p := range settingsApps {
			if lf == p || strings.TrimSuffix(lf, ".desktop") == p {
				return "KwickOS Settings, where agent permissions are granted (use settings_set instead)"
			}
		}
		for _, p := range protectedApps {
			if lf == p || strings.TrimSuffix(lf, ".desktop") == p {
				return "a password, unlock or permission prompt (" + f + ")"
			}
		}
		if strings.HasPrefix(lf, "pinentry") || strings.Contains(lf, "polkit") || strings.Contains(lf, "askpass") {
			return "a password prompt (" + f + ")"
		}
	}
	t := strings.ToLower(w.Title)
	if t == "kwickos agent control" {
		return "the KwickOS agent control indicator"
	}
	if strings.Contains(t, "allow an ai agent") || strings.HasPrefix(t, "kwickos: allow") {
		return "a KwickOS permission dialog"
	}
	if strings.Contains(t, "remote control requested") || strings.Contains(t, "authentication required") || strings.Contains(t, "kde wallet") || strings.Contains(t, "unlock keyring") {
		return "a system authorization dialog"
	}
	return ""
}

func markProtected(ws []winInfo) {
	for i := range ws {
		ws[i].Protected = protectedReason(ws[i])
	}
}

func (st *brokerState) guardInput(pt *[2]float64, typing bool) error {
	if b, err := sessionBus(); err == nil && b.screenLocked() {
		return fmt.Errorf("Refused: the screen is locked; agents never type into or click on the lock screen")
	}
	if typing && desktopKind() != "kde" && desktopKind() != "sway" && desktopKind() != "hyprland" {
		return nil
	}
	wm := currentWM()
	if wm == nil {
		return nil
	}
	ws, err := wm.windows()
	if err != nil {
		return fmt.Errorf("Refused: cannot check which window would receive the input (%v)", err)
	}
	for _, w := range ws {
		r := protectedReason(w)
		if r == "" || w.Minimized {
			continue
		}
		if w.Active {
			return fmt.Errorf("Refused: the focused window is %s. Agents never type, click or press keys there; ask the user to answer it", r)
		}
		if pt != nil && pt[0] >= float64(w.X) && pt[1] >= float64(w.Y) && pt[0] < float64(w.X+w.Width) && pt[1] < float64(w.Y+w.Height) {
			return fmt.Errorf("Refused: %.0f,%.0f is on %s. Agents never click there; ask the user to answer it", pt[0], pt[1], r)
		}
	}
	return nil
}

func (s *Server) ctl() (*ctlSession, error) {
	c := s.shared.active()
	if c == nil {
		return nil, fmt.Errorf("no computer control session; call the tool again to ask the user")
	}
	return c, nil
}

func desktopRect(scr []screenInfo) rectF {
	if len(scr) == 0 {
		return rectF{}
	}
	x0, y0, x1, y1 := math.Inf(1), math.Inf(1), math.Inf(-1), math.Inf(-1)
	for _, s := range scr {
		x0 = math.Min(x0, float64(s.X))
		y0 = math.Min(y0, float64(s.Y))
		x1 = math.Max(x1, float64(s.X+s.Width))
		y1 = math.Max(y1, float64(s.Y+s.Height))
	}
	return rectF{x0, y0, x1 - x0, y1 - y0}
}

func (s *Server) screens() ([]screenInfo, error) {
	if wm := currentWM(); wm != nil {
		if sc, err := wm.screens(); err == nil && len(sc) > 0 {
			return sc, nil
		}
	}
	if c := s.shared.active(); c != nil {
		c.mu.Lock()
		in := c.in
		c.mu.Unlock()
		if p, ok := in.(*portalBackend); ok {
			return p.screens(), nil
		}
	}
	return nil, fmt.Errorf("screen geometry is not available on this desktop")
}

func argNum(a map[string]any, k string) (float64, bool) {
	switch v := a[k].(type) {
	case float64:
		if math.IsNaN(v) || math.IsInf(v, 0) {
			return 0, false
		}
		return v, true
	case string:
		f, err := strconv.ParseFloat(v, 64)
		return f, err == nil && !math.IsNaN(f) && !math.IsInf(f, 0)
	}
	return 0, false
}

func (s *Server) point(a map[string]any, xk, yk string) ([2]float64, string, error) {
	x, okx := argNum(a, xk)
	y, oky := argNum(a, yk)
	if !okx || !oky {
		return [2]float64{}, "", fmt.Errorf("%s and %s are required numbers", xk, yk)
	}
	space := argStr(a, "space")
	shot := s.shared.lastShot()
	if space == "" {
		space = "screen"
		if shot != nil {
			space = "image"
		}
	}
	var p [2]float64
	switch space {
	case "image":
		if shot == nil {
			return p, space, fmt.Errorf("no screenshot yet: take one first or pass \"space\": \"screen\"")
		}
		if x < 0 || y < 0 || x > float64(shot.Width) || y > float64(shot.Height) {
			return p, space, fmt.Errorf("%.0f,%.0f is outside the last screenshot (%dx%d)", x, y, shot.Width, shot.Height)
		}
		p[0], p[1] = shot.toScreen(x, y)
	case "screen":
		p = [2]float64{x, y}
	default:
		return p, space, fmt.Errorf("space must be image or screen")
	}
	if sc, err := s.screens(); err == nil {
		in := false
		for _, r := range sc {
			if p[0] >= float64(r.X) && p[1] >= float64(r.Y) && p[0] < float64(r.X+r.Width) && p[1] < float64(r.Y+r.Height) {
				in = true
			}
		}
		if !in {
			d := desktopRect(sc)
			return p, space, fmt.Errorf("%.0f,%.0f is not on any screen (desktop %.0fx%.0f at %.0f,%.0f)", p[0], p[1], d.W, d.H, d.X, d.Y)
		}
	}
	p[0], p[1] = math.Round(p[0]), math.Round(p[1])
	return p, space, nil
}

func (s *Server) doInput(cost float64, pt *[2]float64, typing bool, f func(in inputBackend) error) error {
	c, err := s.ctl()
	if err != nil {
		return err
	}
	if err := c.take(cost); err != nil {
		return err
	}
	if err := s.shared.guardInput(pt, typing); err != nil {
		return err
	}
	in, err := c.input()
	if err != nil {
		return fmt.Errorf("cannot control the pointer and keyboard: %v", err)
	}
	return f(in)
}

func pointDetail(s *Server, a map[string]any, xk, yk string) string {
	x, _ := argNum(a, xk)
	y, _ := argNum(a, yk)
	sp := argStr(a, "space")
	if sp == "" {
		sp = "screen"
		if s.shared.lastShot() != nil {
			sp = "image"
		}
	}
	return fmt.Sprintf("%.0f,%.0f (%s)", x, y, sp)
}

func ctlDetail(prefix string) func(s *Server, a map[string]any) string {
	return func(s *Server, a map[string]any) string { return prefix }
}

func computerTools() []tool {
	num := func(d string) map[string]any { return map[string]any{"type": "number", "description": d} }
	space := str("Coordinate space: 'image' = pixels of the last screenshot (default after a screenshot), 'screen' = desktop coordinates from screen_info", "image", "screen")
	button := str("Mouse button (default left)", "left", "right", "middle", "back", "forward")
	return []tool{
		{Name: "screen_info", Title: "Screens", Cap: ctlCap, ReadOnly: true,
			Description: "Connected screens with position, size and scale in desktop coordinates, the desktop session, the input method and the geometry of the last screenshot.",
			fn:          toolScreenInfo, precheck: needGUI, detail: ctlDetail("Read the screen layout")},
		{Name: "pointer_move", Title: "Move the pointer", Cap: ctlCap,
			Description: "Move the mouse pointer to x,y.",
			Schema:      obj(map[string]any{"x": num("X"), "y": num("Y"), "space": space}, "x", "y"),
			fn:          toolPointerMove, precheck: needGUI, detail: func(s *Server, a map[string]any) string { return "Move the pointer to " + pointDetail(s, a, "x", "y") }},
		{Name: "pointer_click", Title: "Click", Cap: ctlCap,
			Description: "Click at x,y (or where the pointer is when x and y are left out). double=true double-clicks.",
			Schema:      obj(map[string]any{"x": num("X"), "y": num("Y"), "button": button, "double": map[string]any{"type": "boolean"}, "space": space}),
			fn:          toolPointerClick, precheck: needGUI, detail: func(s *Server, a map[string]any) string {
				w := "Click"
				if b, _ := a["double"].(bool); b {
					w = "Double-click"
				}
				if _, ok := a["x"]; ok {
					return w + " at " + pointDetail(s, a, "x", "y")
				}
				return w
			}},
		{Name: "pointer_drag", Title: "Drag", Cap: ctlCap,
			Description: "Press a button at from_x,from_y, move to to_x,to_y and release it.",
			Schema: obj(map[string]any{"from_x": num("Start X"), "from_y": num("Start Y"), "to_x": num("End X"), "to_y": num("End Y"), "button": button, "space": space},
				"from_x", "from_y", "to_x", "to_y"),
			fn: toolPointerDrag, precheck: needGUI, detail: func(s *Server, a map[string]any) string {
				return "Drag from " + pointDetail(s, a, "from_x", "from_y") + " to " + pointDetail(s, a, "to_x", "to_y")
			}},
		{Name: "scroll", Title: "Scroll", Cap: ctlCap,
			Description: "Scroll at x,y (or at the pointer) by wheel steps: dy > 0 scrolls down, dx > 0 scrolls right.",
			Schema: obj(map[string]any{"x": num("X"), "y": num("Y"), "dx": map[string]any{"type": "integer", "minimum": -30, "maximum": 30},
				"dy": map[string]any{"type": "integer", "minimum": -30, "maximum": 30}, "space": space}),
			fn: toolScroll, precheck: needGUI, detail: func(s *Server, a map[string]any) string {
				return fmt.Sprintf("Scroll by %d,%d", argInt(a, "dx", 0), argInt(a, "dy", 0))
			}},
		{Name: "key_press", Title: "Press keys", Cap: ctlCap,
			Description: "Press a key or key combination, for example 'enter', 'ctrl+s', 'ctrl+shift+t', 'alt+f4', 'super'. keys may also be a list pressed one after another.",
			Schema: obj(map[string]any{"keys": map[string]any{"description": "A combination like 'ctrl+c', or a list of them", "anyOf": []any{map[string]any{"type": "string"},
				map[string]any{"type": "array", "items": map[string]any{"type": "string"}, "maxItems": 20}}},
				"repeat": map[string]any{"type": "integer", "minimum": 1, "maximum": 50}}, "keys"),
			fn: toolKeyPress, precheck: needGUI, detail: func(s *Server, a map[string]any) string {
				ks := argStrings(a, "keys")
				if v, ok := a["keys"].(string); ok {
					ks = []string{v}
				}
				return "Press " + strings.Join(ks, ", ")
			}},
		{Name: "type_text", Title: "Type text", Cap: ctlCap,
			Description: "Type text into the focused window as if typed on the keyboard (up to 2000 characters; newlines press Enter). Refused when a password, unlock or permission prompt is focused.",
			Schema:      obj(map[string]any{"text": str("Text to type")}, "text"),
			fn:          toolTypeText, precheck: needGUI, detail: func(s *Server, a map[string]any) string {
				t := argStr(a, "text")
				if len(t) > 60 {
					t = t[:60] + "..."
				}
				return fmt.Sprintf("Type %q", t)
			}},
		{Name: "windows_list", Title: "List windows", Cap: ctlCap, ReadOnly: true,
			Description: "Open windows with id, title, app, position, size, which one is focused and whether it is protected (password and permission prompts, KwickOS Settings).",
			Schema:      obj(map[string]any{"all": map[string]any{"type": "boolean", "description": "Include panels, docks and other non-normal windows"}}),
			fn:          toolWindowsList, precheck: needGUI, detail: ctlDetail("List the open windows")},
		{Name: "window_focus", Title: "Focus a window", Cap: ctlCap,
			Description: "Bring a window to the front and give it keyboard focus (id from windows_list).",
			Schema:      obj(map[string]any{"id": str("Window id")}, "id"),
			fn:          toolWindowFocus, precheck: needGUI, detail: winDetail("Focus")},
		{Name: "window_close", Title: "Close a window", Cap: ctlCap, Destructive: true,
			Description: "Ask a window to close, like clicking its close button (the app may ask to save).",
			Schema:      obj(map[string]any{"id": str("Window id")}, "id"),
			fn:          toolWindowClose, precheck: needGUI, detail: winDetail("Close")},
		{Name: "window_move_resize", Title: "Move or resize a window", Cap: ctlCap,
			Description: "Move and/or resize a window in desktop coordinates; leave out what should stay.",
			Schema: obj(map[string]any{"id": str("Window id"), "x": map[string]any{"type": "integer"}, "y": map[string]any{"type": "integer"},
				"width": map[string]any{"type": "integer", "minimum": 50}, "height": map[string]any{"type": "integer", "minimum": 50}}, "id"),
			fn: toolWindowMoveResize, precheck: needGUI, detail: winDetail("Move or resize")},
		{Name: "clipboard_get", Title: "Read the clipboard", Cap: ctlCap, ReadOnly: true,
			Description: "The text on the clipboard (up to 1 MB).",
			fn:          toolClipboardGet, precheck: needGUI, detail: ctlDetail("Read the clipboard")},
		{Name: "clipboard_set", Title: "Set the clipboard", Cap: ctlCap,
			Description: "Put text on the clipboard (up to 1 MB), for example to paste it with key_press 'ctrl+v'.",
			Schema:      obj(map[string]any{"text": str("Text")}, "text"),
			fn:          toolClipboardSet, precheck: needGUI, detail: func(s *Server, a map[string]any) string {
				return fmt.Sprintf("Put %s of text on the clipboard", humanBytes(int64(len(argStr(a, "text")))))
			}},
		{Name: "computer_release", Title: "End computer control", Cap: ctlCap, noSession: true,
			Description: "End this agent's computer control session when the task is done, so the user gets the pointer and keyboard back.",
			fn:          toolRelease, detail: ctlDetail("End computer control")},
	}
}

func winDetail(verb string) func(s *Server, a map[string]any) string {
	return func(s *Server, a map[string]any) string {
		id := argStr(a, "id")
		if wm := currentWM(); wm != nil {
			if ws, err := wm.windows(); err == nil {
				for _, w := range ws {
					if w.ID == id {
						return fmt.Sprintf("%s the window %q (%s)", verb, w.Title, w.App)
					}
				}
			}
		}
		return verb + " the window " + id
	}
}

func toolScreenInfo(s *Server, a map[string]any) (toolResult, error) {
	sc, err := s.screens()
	out := map[string]any{"desktop": desktopKind(), "session_type": os.Getenv("XDG_SESSION_TYPE")}
	if err == nil {
		out["screens"] = sc
		d := desktopRect(sc)
		out["desktop_rect"] = map[string]any{"x": d.X, "y": d.Y, "width": d.W, "height": d.H}
	} else {
		out["screens_error"] = err.Error()
	}
	if g := s.shared.lastShot(); g != nil {
		out["last_screenshot"] = g
	}
	if c := s.shared.active(); c != nil {
		c.mu.Lock()
		if c.in != nil {
			out["input"] = c.in.name()
		}
		c.mu.Unlock()
		out["session_expires"] = c.expires.Format(time.RFC3339)
	}
	out["coordinates"] = "Pointer tools take x,y in the pixels of the last screenshot (space 'image', default after a screenshot) or in desktop coordinates (space 'screen'). Desktop coordinates are logical pixels: a 2x screen of 3840x2160 pixels is 1920x1080 here."
	return toolResult{Data: out}, nil
}

func toolPointerMove(s *Server, a map[string]any) (toolResult, error) {
	p, sp, err := s.point(a, "x", "y")
	if err != nil {
		return toolResult{}, err
	}
	err = s.doInput(1, &p, false, func(in inputBackend) error { return in.move(p[0], p[1]) })
	if err != nil {
		return toolResult{}, err
	}
	return toolResult{Data: map[string]any{"moved_to": map[string]any{"x": p[0], "y": p[1], "space": "screen"}, "from_space": sp}}, nil
}

func clickButton(a map[string]any) (string, error) {
	b := argStr(a, "button")
	if b == "" {
		b = "left"
	}
	if _, ok := evdevButtons[b]; !ok {
		return "", fmt.Errorf("button must be left, right, middle, back or forward")
	}
	return b, nil
}

func toolPointerClick(s *Server, a map[string]any) (toolResult, error) {
	btn, err := clickButton(a)
	if err != nil {
		return toolResult{}, err
	}
	n := 1
	if d, _ := a["double"].(bool); d {
		n = 2
	}
	var pp *[2]float64
	if _, hasX := a["x"]; hasX {
		p, _, err := s.point(a, "x", "y")
		if err != nil {
			return toolResult{}, err
		}
		pp = &p
	}
	if pp == nil && desktopKind() != "gnome" {
		return toolResult{}, fmt.Errorf("give x and y so the click target can be checked")
	}
	err = s.doInput(float64(n), pp, false, func(in inputBackend) error {
		if pp != nil {
			if err := in.move(pp[0], pp[1]); err != nil {
				return err
			}
			time.Sleep(30 * time.Millisecond)
		}
		if ck, ok := in.(clicker); ok {
			return ck.click(btn, n)
		}
		for i := 0; i < n; i++ {
			if err := in.button(btn, true); err != nil {
				return err
			}
			time.Sleep(20 * time.Millisecond)
			if err := in.button(btn, false); err != nil {
				return err
			}
			time.Sleep(40 * time.Millisecond)
		}
		return nil
	})
	if err != nil {
		return toolResult{}, err
	}
	out := map[string]any{"button": btn, "clicks": n}
	if pp != nil {
		out["at"] = map[string]any{"x": pp[0], "y": pp[1], "space": "screen"}
	}
	return toolResult{Data: out, Text: "Clicked. Take a screenshot to see the result."}, nil
}

func toolPointerDrag(s *Server, a map[string]any) (toolResult, error) {
	btn, err := clickButton(a)
	if err != nil {
		return toolResult{}, err
	}
	p0, _, err := s.point(a, "from_x", "from_y")
	if err != nil {
		return toolResult{}, err
	}
	p1, _, err := s.point(a, "to_x", "to_y")
	if err != nil {
		return toolResult{}, err
	}
	if err := s.shared.guardInput(&p1, false); err != nil {
		return toolResult{}, err
	}
	err = s.doInput(4, &p0, false, func(in inputBackend) error {
		if err := in.move(p0[0], p0[1]); err != nil {
			return err
		}
		time.Sleep(40 * time.Millisecond)
		if err := in.button(btn, true); err != nil {
			return err
		}
		const steps = 12
		for i := 1; i <= steps; i++ {
			f := float64(i) / steps
			if err := in.move(math.Round(p0[0]+(p1[0]-p0[0])*f), math.Round(p0[1]+(p1[1]-p0[1])*f)); err != nil {
				in.button(btn, false)
				return err
			}
			time.Sleep(16 * time.Millisecond)
		}
		time.Sleep(40 * time.Millisecond)
		return in.button(btn, false)
	})
	if err != nil {
		return toolResult{}, err
	}
	return toolResult{Data: map[string]any{"from": map[string]any{"x": p0[0], "y": p0[1]}, "to": map[string]any{"x": p1[0], "y": p1[1]}, "button": btn}}, nil
}

func toolScroll(s *Server, a map[string]any) (toolResult, error) {
	dx, dy := argInt(a, "dx", 0), argInt(a, "dy", 0)
	if dx == 0 && dy == 0 {
		return toolResult{}, fmt.Errorf("give dx and/or dy (wheel steps, dy > 0 scrolls down)")
	}
	if dx < -30 || dx > 30 || dy < -30 || dy > 30 {
		return toolResult{}, fmt.Errorf("dx and dy must be between -30 and 30")
	}
	var pp *[2]float64
	if _, hasX := a["x"]; hasX {
		p, _, err := s.point(a, "x", "y")
		if err != nil {
			return toolResult{}, err
		}
		pp = &p
	}
	err := s.doInput(1, pp, false, func(in inputBackend) error {
		if pp != nil {
			if err := in.move(pp[0], pp[1]); err != nil {
				return err
			}
			time.Sleep(20 * time.Millisecond)
		}
		return in.scroll(dx, dy)
	})
	if err != nil {
		return toolResult{}, err
	}
	return toolResult{Data: map[string]any{"dx": dx, "dy": dy}}, nil
}

func toolKeyPress(s *Server, a map[string]any) (toolResult, error) {
	var ks []string
	if v, ok := a["keys"].(string); ok {
		ks = []string{v}
	} else {
		ks = argStrings(a, "keys")
	}
	if len(ks) == 0 || len(ks) > 20 {
		return toolResult{}, fmt.Errorf("keys must be a combination like 'ctrl+s' or a list of up to 20")
	}
	rep := argInt(a, "repeat", 1)
	if rep < 1 || rep > 50 {
		return toolResult{}, fmt.Errorf("repeat must be between 1 and 50")
	}
	var combos []keyCombo
	for _, k := range ks {
		c, err := parseKeyCombo(k)
		if err != nil {
			return toolResult{}, err
		}
		combos = append(combos, c)
	}
	err := s.doInput(float64(len(combos)*rep)/4+1, nil, true, func(in inputBackend) error {
		for r := 0; r < rep; r++ {
			for _, c := range combos {
				if err := in.combo(c); err != nil {
					return err
				}
				time.Sleep(25 * time.Millisecond)
			}
		}
		return nil
	})
	if err != nil {
		return toolResult{}, err
	}
	var names []string
	for _, c := range combos {
		names = append(names, c.String())
	}
	return toolResult{Data: map[string]any{"pressed": names, "repeat": rep}}, nil
}

func toolTypeText(s *Server, a map[string]any) (toolResult, error) {
	t := argStr(a, "text")
	if t == "" {
		return toolResult{}, fmt.Errorf("text is empty")
	}
	n := 0
	for _, r := range t {
		n++
		if r < 32 && r != '\n' && r != '\t' || r == 127 {
			return toolResult{}, fmt.Errorf("text contains control characters; use key_press for special keys")
		}
	}
	if n > 2000 {
		return toolResult{}, fmt.Errorf("at most 2000 characters per call (got %d); split the text or use clipboard_set and ctrl+v", n)
	}
	pasted := 0
	err := s.doInput(float64(n)/40+1, nil, true, func(in inputBackend) error {
		if _, ok := in.(*portalBackend); !ok || isASCII(t) {
			return in.typeText(t)
		}
		paste, _ := parseKeyCombo("ctrl+v")
		if s.activeIsTerminal() {
			paste, _ = parseKeyCombo("ctrl+shift+v")
		}
		saved, _, serr := clipboardGet()
		for _, run := range splitASCII(t) {
			if isASCII(run) {
				if err := in.typeText(run); err != nil {
					return err
				}
				continue
			}
			if _, err := clipboardSet(run); err != nil {
				return fmt.Errorf("characters outside ASCII are pasted through the clipboard, which failed: %v", err)
			}
			time.Sleep(60 * time.Millisecond)
			if err := in.combo(paste); err != nil {
				return err
			}
			time.Sleep(120 * time.Millisecond)
			pasted++
		}
		if serr == nil && pasted > 0 {
			clipboardSet(saved)
		}
		return nil
	})
	if err != nil {
		return toolResult{}, err
	}
	out := map[string]any{"typed_characters": n}
	if pasted > 0 {
		out["pasted_runs"] = pasted
		out["note"] = "characters outside ASCII were pasted through the clipboard, which was restored afterwards"
	}
	return toolResult{Data: out}, nil
}

func isASCII(s string) bool {
	for _, r := range s {
		if r > 0x7e {
			return false
		}
	}
	return true
}

func splitASCII(s string) []string {
	var out []string
	cur := []rune{}
	curASCII := true
	for i, r := range []rune(s) {
		a := r <= 0x7e
		if i > 0 && a != curASCII {
			out = append(out, string(cur))
			cur = cur[:0]
		}
		curASCII = a
		cur = append(cur, r)
	}
	if len(cur) > 0 {
		out = append(out, string(cur))
	}
	return out
}

var terminalApps = []string{"konsole", "org.kde.konsole", "foot", "kitty", "alacritty", "org.gnome.terminal", "gnome-terminal-server", "org.gnome.ptyxis", "kwick-terminal", "xterm", "wezterm", "org.wezfurlong.wezterm", "ghostty", "com.mitchellh.ghostty"}

func (s *Server) activeIsTerminal() bool {
	wm := currentWM()
	if wm == nil {
		return false
	}
	ws, err := wm.windows()
	if err != nil {
		return false
	}
	for _, w := range ws {
		if !w.Active {
			continue
		}
		for _, f := range append([]string{w.App}, w.extra...) {
			lf := strings.TrimSuffix(strings.ToLower(f), ".desktop")
			for _, t := range terminalApps {
				if lf == t {
					return true
				}
			}
		}
	}
	return false
}

func (s *Server) wm() (wmBackend, error) {
	wm := currentWM()
	if wm == nil {
		if desktopKind() == "gnome" {
			return nil, fmt.Errorf("GNOME gives other programs no window list; use key_press 'super' for the overview or 'alt+tab' to switch windows")
		}
		return nil, fmt.Errorf("window management needs KDE Plasma, Hyprland or sway")
	}
	return wm, nil
}

func toolWindowsList(s *Server, a map[string]any) (toolResult, error) {
	wm, err := s.wm()
	if err != nil {
		return toolResult{}, err
	}
	ws, err := wm.windows()
	if err != nil {
		return toolResult{}, err
	}
	all, _ := a["all"].(bool)
	out := []winInfo{}
	active := ""
	for _, w := range ws {
		w.Protected = protectedReason(w)
		if w.Active {
			active = w.ID
		}
		if !all && w.Kind != "normal" && w.Kind != "dialog" && w.Protected == "" {
			continue
		}
		out = append(out, w)
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].Stack > out[j].Stack })
	return toolResult{Data: map[string]any{"count": len(out), "windows": out, "active": active, "backend": wm.wmName(), "order": "topmost first"}}, nil
}

func (s *Server) findWin(wm wmBackend, id string) (winInfo, error) {
	if id == "" {
		return winInfo{}, fmt.Errorf("id is required (see windows_list)")
	}
	ws, err := wm.windows()
	if err != nil {
		return winInfo{}, err
	}
	for _, w := range ws {
		if w.ID == id {
			if r := protectedReason(w); r != "" {
				return w, fmt.Errorf("Refused: that window is %s", r)
			}
			return w, nil
		}
	}
	return winInfo{}, fmt.Errorf("no window with id %q (see windows_list)", id)
}

func (s *Server) winOp(a map[string]any, f func(wm wmBackend, w winInfo) error) (toolResult, error) {
	c, err := s.ctl()
	if err != nil {
		return toolResult{}, err
	}
	if err := c.take(1); err != nil {
		return toolResult{}, err
	}
	wm, err := s.wm()
	if err != nil {
		return toolResult{}, err
	}
	w, err := s.findWin(wm, argStr(a, "id"))
	if err != nil {
		return toolResult{}, err
	}
	if err := f(wm, w); err != nil {
		return toolResult{}, err
	}
	return toolResult{Data: map[string]any{"id": w.ID, "title": w.Title, "app": w.App}}, nil
}

func toolWindowFocus(s *Server, a map[string]any) (toolResult, error) {
	return s.winOp(a, func(wm wmBackend, w winInfo) error { return wm.focus(w.ID) })
}

func toolWindowClose(s *Server, a map[string]any) (toolResult, error) {
	return s.winOp(a, func(wm wmBackend, w winInfo) error { return wm.closeWin(w.ID) })
}

func toolWindowMoveResize(s *Server, a map[string]any) (toolResult, error) {
	opt := func(k string) (*int, error) {
		if _, ok := a[k]; !ok {
			return nil, nil
		}
		v, ok := argNum(a, k)
		if !ok || v != math.Trunc(v) || math.Abs(v) > 100000 {
			return nil, fmt.Errorf("%s must be a whole number", k)
		}
		n := int(v)
		return &n, nil
	}
	x, err := opt("x")
	if err != nil {
		return toolResult{}, err
	}
	y, err := opt("y")
	if err != nil {
		return toolResult{}, err
	}
	w, err := opt("width")
	if err != nil {
		return toolResult{}, err
	}
	h, err := opt("height")
	if err != nil {
		return toolResult{}, err
	}
	if x == nil && y == nil && w == nil && h == nil {
		return toolResult{}, fmt.Errorf("give x, y, width and/or height")
	}
	if (w != nil && *w < 50) || (h != nil && *h < 50) {
		return toolResult{}, fmt.Errorf("width and height must be at least 50")
	}
	return s.winOp(a, func(wm wmBackend, win winInfo) error { return wm.moveResize(win.ID, x, y, w, h) })
}

func toolClipboardGet(s *Server, a map[string]any) (toolResult, error) {
	c, err := s.ctl()
	if err != nil {
		return toolResult{}, err
	}
	if err := c.take(1); err != nil {
		return toolResult{}, err
	}
	t, via, err := clipboardGet()
	if err != nil {
		return toolResult{}, err
	}
	if len(t) > 1<<20 {
		t = t[:1<<20]
	}
	return toolResult{Text: t, Data: map[string]any{"bytes": len(t), "via": via}}, nil
}

func toolClipboardSet(s *Server, a map[string]any) (toolResult, error) {
	c, err := s.ctl()
	if err != nil {
		return toolResult{}, err
	}
	t := argStr(a, "text")
	if len(t) > 1<<20 {
		return toolResult{}, fmt.Errorf("at most 1 MB")
	}
	if err := c.take(1); err != nil {
		return toolResult{}, err
	}
	via, err := clipboardSet(t)
	if err != nil {
		return toolResult{}, err
	}
	return toolResult{Data: map[string]any{"bytes": len(t), "via": via}}, nil
}

func toolRelease(s *Server, a map[string]any) (toolResult, error) {
	c := s.shared.active()
	if c == nil {
		return toolResult{Data: map[string]any{"released": false, "note": "no control session was active"}}, nil
	}
	c.stop("ended by the agent")
	return toolResult{Data: map[string]any{"released": true}}, nil
}

func clipboardGet() (string, string, error) {
	if desktopKind() == "kde" {
		if b, err := sessionBus(); err == nil && b.hasName("org.kde.klipper") {
			var s string
			if err := b.conn.Object("org.kde.klipper", "/klipper").Call("org.kde.klipper.klipper.getClipboardContents", 0).Store(&s); err == nil {
				return s, "klipper", nil
			}
		}
	}
	if lookPath("wl-paste") != "" && os.Getenv("WAYLAND_DISPLAY") != "" {
		out, err := runTimeout(5*time.Second, "wl-paste", "--no-newline", "--type", "text/plain;charset=utf-8")
		if err != nil {
			if strings.Contains(string(out), "No selection") || strings.Contains(string(out), "Nothing is copied") {
				return "", "wl-paste", nil
			}
			return "", "", fmt.Errorf("wl-paste: %v %s", err, strings.TrimSpace(string(out)))
		}
		return string(out), "wl-paste", nil
	}
	return "", "", fmt.Errorf("no clipboard access here (klipper or wl-clipboard needed)")
}

func clipboardSet(t string) (string, error) {
	if desktopKind() == "kde" {
		if b, err := sessionBus(); err == nil && b.hasName("org.kde.klipper") {
			if err := b.conn.Object("org.kde.klipper", "/klipper").Call("org.kde.klipper.klipper.setClipboardContents", 0, t).Err; err == nil {
				return "klipper", nil
			}
		}
	}
	if lookPath("wl-copy") != "" && os.Getenv("WAYLAND_DISPLAY") != "" {
		c := exec.Command("wl-copy", "--type", "text/plain;charset=utf-8")
		c.Stdin = strings.NewReader(t)
		c.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
		var buf bytes.Buffer
		c.Stderr = &buf
		if err := c.Run(); err != nil {
			return "", fmt.Errorf("wl-copy: %v %s", err, strings.TrimSpace(buf.String()))
		}
		return "wl-copy", nil
	}
	return "", fmt.Errorf("no clipboard access here (klipper or wl-clipboard needed)")
}

type kwinWM struct{}

func (kwinWM) wmName() string { return "KWin scripting" }

type kwinState struct {
	Windows []struct {
		ID        string  `json:"id"`
		Title     string  `json:"title"`
		App       string  `json:"app"`
		Name      string  `json:"name"`
		Desktop   string  `json:"desktop_file"`
		PID       int     `json:"pid"`
		X         float64 `json:"x"`
		Y         float64 `json:"y"`
		W         float64 `json:"width"`
		H         float64 `json:"height"`
		Active    bool    `json:"active"`
		Minimized bool    `json:"minimized"`
		Normal    bool    `json:"normal"`
		Dialog    bool    `json:"dialog"`
		Output    string  `json:"output"`
		Stack     int     `json:"stack"`
	} `json:"windows"`
	Screens []struct {
		Name  string  `json:"name"`
		X     float64 `json:"x"`
		Y     float64 `json:"y"`
		W     float64 `json:"width"`
		H     float64 `json:"height"`
		Scale float64 `json:"scale"`
	} `json:"screens"`
}

const kwinStateJS = `var out = [], act = workspace.activeWindow, ws = workspace.stackingOrder;
for (var i = 0; i < ws.length; i++) {
  var w = ws[i], g = w.frameGeometry;
  if (w.deleted) continue;
  out.push({id: String(w.internalId), title: String(w.caption || ""), app: String(w.resourceClass || ""), name: String(w.resourceName || ""),
    desktop_file: String(w.desktopFileName || ""), pid: w.pid || 0, x: g.x, y: g.y, width: g.width, height: g.height,
    active: act !== null && w === act, minimized: !!w.minimized, normal: !!w.normalWindow, dialog: !!w.dialog,
    output: w.output ? String(w.output.name) : "", stack: i});
}
var sc = [];
for (var j = 0; j < workspace.screens.length; j++) {
  var o = workspace.screens[j], q = o.geometry;
  sc.push({name: String(o.name), x: q.x, y: q.y, width: q.width, height: q.height, scale: o.devicePixelRatio});
}
return {windows: out, screens: sc};`

func kwinQuery() (*kwinState, error) {
	b, err := sessionBus()
	if err != nil {
		return nil, err
	}
	raw, err := b.kwinEval(kwinStateJS, 5*time.Second)
	if err != nil {
		return nil, err
	}
	var st kwinState
	if err := json.Unmarshal(raw, &st); err != nil {
		return nil, fmt.Errorf("KWin returned %s", truncate(string(raw), 200))
	}
	return &st, nil
}

func truncate(s string, n int) string {
	if len(s) > n {
		return s[:n] + "..."
	}
	return s
}

func (kwinWM) windows() ([]winInfo, error) {
	st, err := kwinQuery()
	if err != nil {
		return nil, err
	}
	var out []winInfo
	for _, w := range st.Windows {
		k := "other"
		if w.Normal {
			k = "normal"
		} else if w.Dialog {
			k = "dialog"
		}
		out = append(out, winInfo{ID: w.ID, Title: w.Title, App: w.App, PID: w.PID, X: int(w.X), Y: int(w.Y), Width: int(w.W), Height: int(w.H),
			Active: w.Active, Minimized: w.Minimized, Output: w.Output, Kind: k, Stack: w.Stack, extra: []string{w.Name, w.Desktop}})
	}
	return out, nil
}

func (kwinWM) screens() ([]screenInfo, error) {
	st, err := kwinQuery()
	if err != nil {
		return nil, err
	}
	var out []screenInfo
	for _, s := range st.Screens {
		out = append(out, screenInfo{Name: s.Name, X: int(s.X), Y: int(s.Y), Width: int(s.W), Height: int(s.H), Scale: s.Scale})
	}
	return out, nil
}

func kwinWinOp(id, body string) error {
	b, err := sessionBus()
	if err != nil {
		return err
	}
	js := "var id = " + jsString(id) + ", ws = workspace.stackingOrder, w = null;\nfor (var i = 0; i < ws.length; i++) if (String(ws[i].internalId) === id) w = ws[i];\nif (w === null) return {error: \"no such window\"};\n" + body + "\nreturn true;"
	_, err = b.kwinEval(js, 5*time.Second)
	return err
}

func (kwinWM) focus(id string) error {
	return kwinWinOp(id, "if (w.minimized) w.minimized = false;\nworkspace.activeWindow = w;")
}

func (kwinWM) closeWin(id string) error { return kwinWinOp(id, "w.closeWindow();") }

func (kwinWM) moveResize(id string, x, y, wd, ht *int) error {
	f := func(p *int, def string) string {
		if p == nil {
			return def
		}
		return strconv.Itoa(*p)
	}
	return kwinWinOp(id, "if (w.fullScreen) w.fullScreen = false;\nif (typeof w.setMaximize === \"function\") w.setMaximize(false, false);\nvar g = w.frameGeometry;\nw.frameGeometry = {x: "+
		f(x, "g.x")+", y: "+f(y, "g.y")+", width: "+f(wd, "g.width")+", height: "+f(ht, "g.height")+"};")
}

type swayNode struct {
	ID       int64                             `json:"id"`
	Name     string                            `json:"name"`
	Type     string                            `json:"type"`
	AppID    string                            `json:"app_id"`
	PID      int                               `json:"pid"`
	Focused  bool                              `json:"focused"`
	Visible  bool                              `json:"visible"`
	Output   string                            `json:"output"`
	Rect     struct{ X, Y, Width, Height int } `json:"rect"`
	WinProps struct {
		Class string `json:"class"`
	} `json:"window_properties"`
	Nodes    []swayNode `json:"nodes"`
	Floating []swayNode `json:"floating_nodes"`
	Scale    float64    `json:"scale"`
	Active   bool       `json:"active"`
}

type swayWM struct{}

func (swayWM) wmName() string { return "sway IPC" }

func (swayWM) windows() ([]winInfo, error) {
	out, err := cmdText(5*time.Second, "swaymsg", "-t", "get_tree", "-r")
	if err != nil {
		return nil, err
	}
	var root swayNode
	if err := json.Unmarshal([]byte(out), &root); err != nil {
		return nil, fmt.Errorf("swaymsg get_tree: %v", err)
	}
	var ws []winInfo
	var walk func(n swayNode, output string)
	walk = func(n swayNode, output string) {
		if n.Type == "output" {
			output = n.Name
		}
		if (n.Type == "con" || n.Type == "floating_con") && (n.PID > 0 || n.AppID != "" || n.WinProps.Class != "") {
			app := n.AppID
			if app == "" {
				app = n.WinProps.Class
			}
			ws = append(ws, winInfo{ID: strconv.FormatInt(n.ID, 10), Title: n.Name, App: app, PID: n.PID, X: n.Rect.X, Y: n.Rect.Y, Width: n.Rect.Width,
				Height: n.Rect.Height, Active: n.Focused, Minimized: !n.Visible, Output: output, Kind: "normal", Stack: len(ws)})
		}
		for _, c := range n.Nodes {
			walk(c, output)
		}
		for _, c := range n.Floating {
			walk(c, output)
		}
	}
	walk(root, "")
	return ws, nil
}

func (swayWM) screens() ([]screenInfo, error) {
	out, err := cmdText(5*time.Second, "swaymsg", "-t", "get_outputs", "-r")
	if err != nil {
		return nil, err
	}
	var os_ []swayNode
	if err := json.Unmarshal([]byte(out), &os_); err != nil {
		return nil, err
	}
	var sc []screenInfo
	for _, o := range os_ {
		if o.Active {
			sc = append(sc, screenInfo{Name: o.Name, X: o.Rect.X, Y: o.Rect.Y, Width: o.Rect.Width, Height: o.Rect.Height, Scale: o.Scale})
		}
	}
	return sc, nil
}

func swayCmd(id string, cmd ...string) error {
	if _, err := strconv.ParseInt(id, 10, 64); err != nil {
		return fmt.Errorf("bad window id")
	}
	_, err := cmdText(5*time.Second, "swaymsg", append([]string{"[con_id=" + id + "]"}, cmd...)...)
	return err
}

func (swayWM) focus(id string) error    { return swayCmd(id, "focus") }
func (swayWM) closeWin(id string) error { return swayCmd(id, "kill") }
func (swayWM) moveResize(id string, x, y, w, h *int) error {
	if err := swayCmd(id, "floating", "enable"); err != nil {
		return err
	}
	if x != nil || y != nil {
		ws, _ := swayWM{}.windows()
		cx, cy := 0, 0
		for _, win := range ws {
			if win.ID == id {
				cx, cy = win.X, win.Y
			}
		}
		if x != nil {
			cx = *x
		}
		if y != nil {
			cy = *y
		}
		if err := swayCmd(id, "move", "absolute", "position", strconv.Itoa(cx), strconv.Itoa(cy)); err != nil {
			return err
		}
	}
	if w != nil || h != nil {
		args := []string{"resize", "set"}
		if w != nil {
			args = append(args, "width", strconv.Itoa(*w))
		}
		if h != nil {
			args = append(args, "height", strconv.Itoa(*h))
		}
		return swayCmd(id, args...)
	}
	return nil
}

type hyprWM struct{}

func (hyprWM) wmName() string { return "hyprctl" }

func (hyprWM) windows() ([]winInfo, error) {
	out, err := cmdText(5*time.Second, "hyprctl", "clients", "-j")
	if err != nil {
		return nil, err
	}
	var cs []struct {
		Address string `json:"address"`
		Title   string `json:"title"`
		Class   string `json:"class"`
		Initial string `json:"initialClass"`
		PID     int    `json:"pid"`
		At      [2]int `json:"at"`
		Size    [2]int `json:"size"`
		Focus   int    `json:"focusHistoryID"`
		Hidden  bool   `json:"hidden"`
		Mapped  bool   `json:"mapped"`
	}
	if err := json.Unmarshal([]byte(out), &cs); err != nil {
		return nil, err
	}
	var ws []winInfo
	for _, c := range cs {
		if !c.Mapped {
			continue
		}
		ws = append(ws, winInfo{ID: c.Address, Title: c.Title, App: c.Class, PID: c.PID, X: c.At[0], Y: c.At[1], Width: c.Size[0], Height: c.Size[1],
			Active: c.Focus == 0, Minimized: c.Hidden, Kind: "normal", Stack: 1000 - c.Focus, extra: []string{c.Initial}})
	}
	return ws, nil
}

func (hyprWM) screens() ([]screenInfo, error) {
	out, err := cmdText(5*time.Second, "hyprctl", "monitors", "-j")
	if err != nil {
		return nil, err
	}
	var ms []struct {
		Name   string  `json:"name"`
		X      int     `json:"x"`
		Y      int     `json:"y"`
		Width  int     `json:"width"`
		Height int     `json:"height"`
		Scale  float64 `json:"scale"`
	}
	if err := json.Unmarshal([]byte(out), &ms); err != nil {
		return nil, err
	}
	var sc []screenInfo
	for _, m := range ms {
		s := m.Scale
		if s <= 0 {
			s = 1
		}
		sc = append(sc, screenInfo{Name: m.Name, X: m.X, Y: m.Y, Width: int(float64(m.Width) / s), Height: int(float64(m.Height) / s), Scale: s})
	}
	return sc, nil
}

func hyprAddr(id string) (string, error) {
	if !strings.HasPrefix(id, "0x") || len(id) > 20 {
		return "", fmt.Errorf("bad window id")
	}
	if _, err := strconv.ParseUint(id[2:], 16, 64); err != nil {
		return "", fmt.Errorf("bad window id")
	}
	return "address:" + id, nil
}

func (hyprWM) focus(id string) error {
	a, err := hyprAddr(id)
	if err != nil {
		return err
	}
	_, err = cmdText(5*time.Second, "hyprctl", "dispatch", "focuswindow", a)
	return err
}

func (hyprWM) closeWin(id string) error {
	a, err := hyprAddr(id)
	if err != nil {
		return err
	}
	_, err = cmdText(5*time.Second, "hyprctl", "dispatch", "closewindow", a)
	return err
}

func (hyprWM) moveResize(id string, x, y, w, h *int) error {
	a, err := hyprAddr(id)
	if err != nil {
		return err
	}
	ws, _ := hyprWM{}.windows()
	var cur winInfo
	for _, win := range ws {
		if win.ID == id {
			cur = win
		}
	}
	cmdText(5*time.Second, "hyprctl", "dispatch", "setfloating", a)
	if x != nil || y != nil {
		nx, ny := cur.X, cur.Y
		if x != nil {
			nx = *x
		}
		if y != nil {
			ny = *y
		}
		if _, err := cmdText(5*time.Second, "hyprctl", "dispatch", "movewindowpixel", fmt.Sprintf("exact %d %d,%s", nx, ny, a)); err != nil {
			return err
		}
	}
	if w != nil || h != nil {
		nw, nh := cur.Width, cur.Height
		if w != nil {
			nw = *w
		}
		if h != nil {
			nh = *h
		}
		_, err := cmdText(5*time.Second, "hyprctl", "dispatch", "resizewindowpixel", fmt.Sprintf("exact %d %d,%s", nw, nh, a))
		return err
	}
	return nil
}

type swayInput struct{}

func (swayInput) name() string { return "swaymsg seat cursor + wtype" }

func (swayInput) move(x, y float64) error {
	_, err := cmdText(5*time.Second, "swaymsg", "seat", "-", "cursor", "set", strconv.Itoa(int(x)), strconv.Itoa(int(y)))
	return err
}

var swayButtons = map[string]string{"left": "BTN_LEFT", "right": "BTN_RIGHT", "middle": "BTN_MIDDLE", "back": "BTN_SIDE", "forward": "BTN_EXTRA"}

func (swayInput) button(btn string, down bool) error {
	act := "release"
	if down {
		act = "press"
	}
	_, err := cmdText(5*time.Second, "swaymsg", "seat", "-", "cursor", act, swayButtons[btn])
	return err
}

func (swayInput) scroll(dx, dy int) error {
	do := func(n int, neg, pos string) error {
		b := pos
		if n < 0 {
			b, n = neg, -n
		}
		for i := 0; i < n; i++ {
			if _, err := cmdText(5*time.Second, "swaymsg", "seat", "-", "cursor", "press", b); err != nil {
				return err
			}
			cmdText(5*time.Second, "swaymsg", "seat", "-", "cursor", "release", b)
		}
		return nil
	}
	if err := do(dy, "button4", "button5"); err != nil {
		return err
	}
	return do(dx, "button6", "button7")
}

func wtypeCombo(k keyCombo) error {
	if lookPath("wtype") == "" {
		return fmt.Errorf("wtype is not installed (apt install wtype)")
	}
	_, err := cmdText(10*time.Second, "wtype", k.wtypeArgs()...)
	return err
}

func wtypeText(s string) error {
	if lookPath("wtype") == "" {
		return fmt.Errorf("wtype is not installed (apt install wtype)")
	}
	_, err := cmdText(60*time.Second, "wtype", "-d", "4", "--", s)
	return err
}

func (swayInput) combo(k keyCombo) error  { return wtypeCombo(k) }
func (swayInput) typeText(s string) error { return wtypeText(s) }
func (swayInput) close()                  {}

type hyprInput struct {
	down string
}

func (*hyprInput) name() string { return "hyprctl + wlrctl + wtype" }

func (*hyprInput) move(x, y float64) error {
	_, err := cmdText(5*time.Second, "hyprctl", "dispatch", "movecursor", strconv.Itoa(int(x)), strconv.Itoa(int(y)))
	return err
}

var ydoButtons = map[string]int{"left": 0, "right": 1, "middle": 2, "back": 3, "forward": 4}

func ydotoolSocket() string {
	if s := os.Getenv("YDOTOOL_SOCKET"); s != "" {
		return s
	}
	return "/tmp/.ydotool_socket"
}

func (h *hyprInput) button(btn string, down bool) error {
	if lookPath("ydotool") != "" && exists(ydotoolSocket()) {
		code := 0x80
		if down {
			code = 0x40
		}
		_, err := cmdText(5*time.Second, "ydotool", "click", fmt.Sprintf("0x%02X", code|ydoButtons[btn]))
		return err
	}
	if down {
		h.down = btn
		return nil
	}
	if h.down != btn {
		return fmt.Errorf("dragging needs ydotool on Hyprland")
	}
	h.down = ""
	return h.click(btn, 1)
}

func (h *hyprInput) click(btn string, n int) error {
	if lookPath("wlrctl") == "" {
		return fmt.Errorf("wlrctl is not installed (apt install wlrctl)")
	}
	for i := 0; i < n; i++ {
		if _, err := cmdText(5*time.Second, "wlrctl", "pointer", "click", btn); err != nil {
			return err
		}
		time.Sleep(40 * time.Millisecond)
	}
	return nil
}

func (*hyprInput) scroll(dx, dy int) error {
	if lookPath("wlrctl") == "" {
		return fmt.Errorf("wlrctl is not installed (apt install wlrctl)")
	}
	_, err := cmdText(5*time.Second, "wlrctl", "pointer", "scroll", strconv.Itoa(dy*15), strconv.Itoa(dx*15))
	return err
}

func (*hyprInput) combo(k keyCombo) error  { return wtypeCombo(k) }
func (*hyprInput) typeText(s string) error { return wtypeText(s) }
func (*hyprInput) close()                  {}

type ydoInput struct{}

func (ydoInput) name() string { return "ydotool" }
func (ydoInput) move(x, y float64) error {
	_, err := cmdText(5*time.Second, "ydotool", "mousemove", "--absolute", "-x", strconv.Itoa(int(x)), "-y", strconv.Itoa(int(y)))
	return err
}
func (ydoInput) button(btn string, down bool) error {
	code := 0x80
	if down {
		code = 0x40
	}
	_, err := cmdText(5*time.Second, "ydotool", "click", fmt.Sprintf("0x%02X", code|ydoButtons[btn]))
	return err
}
func (ydoInput) scroll(dx, dy int) error {
	_, err := cmdText(5*time.Second, "ydotool", "mousemove", "--wheel", "-x", strconv.Itoa(dx), "-y", strconv.Itoa(-dy))
	return err
}
func (ydoInput) combo(k keyCombo) error {
	if lookPath("wtype") != "" && os.Getenv("WAYLAND_DISPLAY") != "" {
		return wtypeCombo(k)
	}
	return fmt.Errorf("key combinations need the portal or wtype here")
}
func (ydoInput) typeText(s string) error {
	_, err := cmdText(60*time.Second, "ydotool", "type", "--", s)
	return err
}
func (ydoInput) close() {}

func stopAllMarkers(reason string) int {
	ms, _ := filepath.Glob(filepath.Join(controlDir(), "*.json"))
	n := 0
	for _, m := range ms {
		var c ctlMarker
		if readJSONFile(m, &c) != nil {
			continue
		}
		if os.Remove(m) == nil {
			n++
			auditLog(auditEntry{Agent: c.Agent, Tool: "control", Capability: ctlCap, Decision: "stop", OK: true, Summary: "computer control " + reason + " (session " + c.ID + ")"})
		}
	}
	return n
}

func cmdControl(o opts, pos []string) error {
	sub := "list"
	if len(pos) > 0 {
		sub = pos[0]
	}
	ms, _ := filepath.Glob(filepath.Join(controlDir(), "*.json"))
	var list []ctlMarker
	for _, m := range ms {
		var c ctlMarker
		if readJSONFile(m, &c) != nil {
			continue
		}
		if c.PID > 0 && syscall.Kill(c.PID, 0) != nil {
			os.Remove(m)
			continue
		}
		list = append(list, c)
	}
	switch sub {
	case "list", "ls", "status":
		if list == nil {
			list = []ctlMarker{}
		}
		if o.json {
			emitJSON(map[string]any{"schema": 1, "sessions": list})
			return nil
		}
		if len(list) == 0 {
			fmt.Println("no agent controls this computer")
		}
		for _, c := range list {
			fmt.Printf("%s  %-12s since %s until %s\n", c.ID, c.Agent, c.Started, c.Expires)
		}
		return nil
	case "stop", "revoke":
		n := 0
		for _, c := range list {
			if len(pos) > 1 && pos[1] != c.ID && pos[1] != c.Agent {
				continue
			}
			if os.Remove(filepath.Join(controlDir(), c.ID+".json")) == nil {
				n++
				auditLog(auditEntry{Agent: c.Agent, Tool: "cli", Capability: ctlCap, Decision: "stop", OK: true, Summary: "computer control stopped by the user (session " + c.ID + ")"})
			}
		}
		if !o.json {
			if n == 0 {
				fmt.Println("no agent controls this computer")
			} else {
				fmt.Printf("stopped %d control session(s)\n", n)
			}
		} else {
			emitJSON(map[string]any{"stopped": n})
		}
		return nil
	}
	return fmt.Errorf("usage: kwick-agents control [list|stop [ID|AGENT]] [--json]")
}
