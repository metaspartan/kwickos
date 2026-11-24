package main

import (
	"bufio"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"time"
)

const consentTitle = "KwickOS: allow an AI agent?"

var capVerbs = map[string]string{
	"system.read":      "read system information",
	"files.read":       "read your files",
	"files.write":      "change your files",
	"notify":           "show notifications",
	"settings.write":   "change your settings",
	"apps.launch":      "open applications",
	"screen.capture":   "take a screenshot",
	"computer.control": "use this computer",
	"packages.manage":  "install software",
	"snapshots.manage": "create system snapshots",
	"inference.manage": "manage local models",
}

type consentConfig struct {
	Title      string `json:"title"`
	Agent      string `json:"agent"`
	Action     string `json:"action"`
	Detail     string `json:"detail"`
	Capability string `json:"capability"`
	Appearance string `json:"appearance"`
	Layout     string `json:"layout"`
	Accent     string `json:"accent,omitempty"`
}

func consentQML() string {
	if p := os.Getenv("KWICK_AGENTS_CONSENT_QML"); p != "" && filepath.IsAbs(p) && exists(p) {
		return p
	}
	return filepath.Join(libDir, "consent.qml")
}

func consentAnswer(line string) string {
	i := strings.Index(line, "kwick-consent:")
	if i < 0 {
		return ""
	}
	switch v := strings.TrimSpace(line[i+len("kwick-consent:"):]); v {
	case "once", "always", "deny":
		return v
	}
	return ""
}

func dieWithRequester(c *exec.Cmd) {
	c.SysProcAttr = &syscall.SysProcAttr{Pdeathsig: syscall.SIGTERM}
}

func askNative(title, who, capName, desc, detail string, gone <-chan struct{}) (string, bool) {
	if desktopKind() != "kde" || os.Getenv("WAYLAND_DISPLAY") == "" {
		return "", false
	}
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	qml := lookPath("qml6")
	if qml == "" || !exists(consentQML()) {
		return "", false
	}
	layout := "macos"
	if b, err := os.ReadFile(kwickConfPath("layout")); err == nil && len(strings.TrimSpace(string(b))) > 0 {
		layout = strings.TrimSpace(string(b))
	}
	app := "dark"
	if b, err := os.ReadFile(kwickConfPath("appearance")); err == nil && strings.TrimSpace(string(b)) == "light" {
		app = "light"
	}
	action := capVerbs[capName]
	if action == "" {
		action = "continue"
	}
	body := strings.TrimSuffix(desc, ".") + "."
	if d := strings.TrimSpace(detail); d != "" {
		if !strings.ContainsAny(d[len(d)-1:], ".!?:") {
			d += "."
		}
		body += "\n\n" + d
	}
	cfg, _ := json.Marshal(consentConfig{Title: title, Agent: who, Action: action, Detail: body, Capability: capName, Appearance: app, Layout: layout, Accent: currentAccentHex()})
	cmd := exec.Command(qml, consentQML(), "--", string(cfg))
	cmd.Env = append(os.Environ(), "QT_QPA_PLATFORM=wayland")
	dieWithRequester(cmd)
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return "", false
	}
	if cmd.Start() != nil {
		return "", false
	}
	stop := cancelOnGone(cmd, gone)
	defer stop()
	done := make(chan struct{})
	go keepConsentAbove(title, done)
	ans := ""
	sc := bufio.NewScanner(stderr)
	for sc.Scan() {
		if v := consentAnswer(sc.Text()); v != "" {
			ans = v
		}
	}
	cmd.Wait()
	close(done)
	if ans == "" {
		return "", false
	}
	return ans, true
}

func keepConsentAbove(title string, done chan struct{}) {
	b, err := sessionBus()
	if err != nil {
		return
	}
	js := `var ws = workspace.stackingOrder, n = 0;
for (var i = 0; i < ws.length; i++) {
  var w = ws[i];
  if (w.deleted || String(w.caption || "") !== ` + jsString(title) + `) continue;
  w.keepAbove = true;
  w.onAllDesktops = true;
  w.skipTaskbar = true;
  w.skipSwitcher = true;
  var o = w.output ? w.output.geometry : workspace.clientArea(KWin.FullScreenArea, w), g = w.frameGeometry;
  w.frameGeometry = {x: o.x + Math.round((o.width - g.width) / 2), y: o.y + Math.round(o.height * 0.22), width: g.width, height: g.height};
  workspace.activeWindow = w;
  n++;
}
return n;`
	placed := 0
	for i := 0; i < 40 && placed < 4; i++ {
		select {
		case <-done:
			return
		case <-time.After(150 * time.Millisecond):
		}
		if out, err := b.kwinEval(js, 2*time.Second); err == nil && strings.TrimSpace(string(out)) != "0" {
			placed++
		}
	}
}
