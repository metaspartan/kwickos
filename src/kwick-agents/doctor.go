package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

type check struct {
	Name   string `json:"name"`
	OK     bool   `json:"ok"`
	Detail string `json:"detail"`
}

func cmdDoctor(o opts) error {
	var cs []check
	add := func(n string, ok bool, d string) { cs = append(cs, check{n, ok, d}) }
	add("arch", true, hostArch())
	if _, err := loadCatalog(); err != nil {
		add("catalog", false, err.Error())
	} else {
		add("catalog", true, catalogPath())
	}
	bw := lookPath("bwrap")
	if bw == "" {
		add("bubblewrap", false, "not installed (sudo apt install bubblewrap)")
	} else {
		out, err := exec.Command(bw, "--ro-bind", "/", "/", "--dev", "/dev", "--proc", "/proc", "--unshare-all", "--die-with-parent", "--new-session", "true").CombinedOutput()
		if err != nil {
			add("bubblewrap", false, "cannot create a sandbox: "+strings.TrimSpace(string(out)))
		} else {
			add("bubblewrap", true, bw+" works (user, pid, ipc, uts and network namespaces)")
		}
	}
	add("keystore", true, backendName())
	dialogs := []string{}
	for _, t := range []string{"kdialog", "zenity", "notify-send"} {
		if lookPath(t) != "" {
			dialogs = append(dialogs, t)
		}
	}
	if guiEnv() && len(dialogs) > 0 {
		add("consent prompts", true, "desktop dialogs via "+strings.Join(dialogs, ", "))
	} else {
		add("consent prompts", true, "terminal: answer with 'kwick-agents consent' (no desktop session or dialog tool)")
	}
	pk := lookPath("pkexec") != "" && exists("/usr/share/polkit-1/actions/org.kwickos.agents.policy")
	if pk {
		add("administrator prompts", true, "polkit (pkexec) with org.kwickos.agents.policy")
	} else {
		add("administrator prompts", true, "no polkit; privileged MCP tools need 'sudo -n' or tell the user the command")
	}
	add("mcp server", exists(mcpPath), mcpPath)
	us := userScope()
	onPath := strings.Contains(":"+os.Getenv("PATH")+":", ":"+us.Bin+":")
	add("command shims", true, fmt.Sprintf("%s (on PATH: %v); system installs use %s", shortPath(us.Bin), onPath, sysBin))
	add("audit log", true, auditPath())
	failed := false
	for _, c := range cs {
		if !c.OK {
			failed = true
		}
	}
	if o.json {
		emitJSON(map[string]any{"schema": 1, "ok": !failed, "checks": cs})
	} else {
		for _, c := range cs {
			m := "ok  "
			if !c.OK {
				m = "FAIL"
			}
			fmt.Printf("%s %-22s %s\n", m, c.Name, c.Detail)
		}
	}
	if failed {
		return exitErr{1}
	}
	return nil
}
