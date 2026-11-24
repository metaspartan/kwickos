package main

import (
	"os"
	"os/exec"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestConsentAnswer(t *testing.T) {
	cases := map[string]string{
		"qml: kwick-consent:once":  "once",
		"kwick-consent:always":     "always",
		"js: kwick-consent:deny":   "deny",
		"kwick-consent:everything": "",
		"qml: something else":      "",
		"kwick-consent: once ":     "once",
	}
	for in, want := range cases {
		if got := consentAnswer(in); got != want {
			t.Fatalf("%q: got %q want %q", in, got, want)
		}
	}
	for _, app := range []string{"qml6", "org.qt-project.qml"} {
		if protectedReason(winInfo{App: app, Title: consentTitle}) == "" {
			t.Fatalf("the consent dialog from %s is not protected", app)
		}
	}
	for c := range capVerbs {
		if _, ok := capByName(c); !ok {
			t.Fatalf("unknown capability %s", c)
		}
	}
	for _, c := range capabilities {
		if capVerbs[c.Name] == "" {
			t.Fatalf("no verb for %s", c.Name)
		}
	}
}

func TestConsentClosesWhenRequesterGoes(t *testing.T) {
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	gone := make(chan struct{})
	got := make(chan string, 1)
	go func() { got <- askPending("test", "", "files.write", "x", 30*time.Second, gone) }()
	time.Sleep(400 * time.Millisecond)
	close(gone)
	select {
	case v := <-got:
		if v != "gone" {
			t.Fatalf("pending request answered %q after the client left", v)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("the pending request outlived its client")
	}
	if ms, _ := os.ReadDir(pendingDir()); len(ms) != 0 {
		t.Fatalf("pending files left behind: %d", len(ms))
	}

	gone = make(chan struct{})
	c := exec.Command("sleep", "30")
	dieWithRequester(c)
	if err := c.Start(); err != nil {
		t.Skip("no sleep binary")
	}
	stop := cancelOnGone(c, gone)
	defer stop()
	close(gone)
	waited := make(chan error, 1)
	go func() { waited <- c.Wait() }()
	select {
	case err := <-waited:
		if err == nil || !strings.Contains(err.Error(), "terminated") {
			t.Fatalf("dialog ended with %v, want a SIGTERM", err)
		}
	case <-time.After(3 * time.Second):
		c.Process.Kill()
		t.Fatal("the dialog stayed open after its client left")
	}
	if c.SysProcAttr == nil || c.SysProcAttr.Pdeathsig == 0 {
		t.Fatal("dialogs are not tied to the process that asked")
	}
}

func TestConsentDialogDiesWithRequester(t *testing.T) {
	if os.Getenv("KWICK_CONSENT_CHILD") == "1" {
		c := exec.Command("sleep", "30")
		dieWithRequester(c)
		if c.Start() != nil {
			os.Exit(3)
		}
		os.Stdout.WriteString("dialog " + strconv.Itoa(c.Process.Pid) + "\n")
		time.Sleep(30 * time.Second)
		return
	}
	self, err := os.Executable()
	if err != nil {
		t.Skip(err)
	}
	p := exec.Command(self, "-test.run", "TestConsentDialogDiesWithRequester")
	p.Env = append(os.Environ(), "KWICK_CONSENT_CHILD=1")
	out, err := p.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := p.Start(); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 64)
	var text string
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) && !strings.Contains(text, "\n") {
		n, err := out.Read(buf)
		text += string(buf[:n])
		if err != nil {
			break
		}
	}
	lines := strings.Fields(text)
	if len(lines) < 2 {
		p.Process.Kill()
		t.Skip("child did not start a dialog")
	}
	pid := lines[1]
	p.Process.Kill()
	p.Wait()
	for i := 0; i < 30; i++ {
		if _, err := os.Stat("/proc/" + pid); os.IsNotExist(err) {
			return
		}
		if b, err := os.ReadFile("/proc/" + pid + "/stat"); err == nil && strings.Contains(string(b), ") Z ") {
			return
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatal("the dialog survived the process that asked for it")
}
