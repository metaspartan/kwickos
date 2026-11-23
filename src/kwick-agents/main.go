package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

var version = "dev"

const prog = "kwick-agents"

type opts struct {
	json      bool
	machine   bool
	system    bool
	user      bool
	noSandbox bool
	sandbox   bool
	offline   bool
	noMCP     bool
	always    bool
	latest    bool
	installed bool
	dialog    bool
	yes       bool
	cmd       string
	agent     string
	n         int
	args      []string
	rest      []string
}

func parseOpts(a []string) (opts, error) {
	o := opts{n: 50}
	for i := 0; i < len(a); i++ {
		s := a[i]
		if s == "--" {
			o.rest = append(o.rest, a[i+1:]...)
			break
		}
		next := func() (string, error) {
			if i+1 >= len(a) {
				return "", fmt.Errorf("%s needs a value", s)
			}
			i++
			return a[i], nil
		}
		var err error
		switch s {
		case "--json":
			o.json = true
		case "--machine":
			o.machine = true
		case "--system":
			o.system = true
		case "--user":
			o.user = true
		case "--no-sandbox":
			o.noSandbox = true
		case "--sandbox":
			o.sandbox = true
		case "--offline":
			o.offline = true
		case "--no-mcp":
			o.noMCP = true
		case "--always":
			o.always = true
		case "--latest":
			o.latest = true
		case "--dialog":
			o.dialog = true
		case "--installed":
			o.installed = true
		case "-y", "--yes":
			o.yes = true
		case "--cmd":
			o.cmd, err = next()
		case "--agent":
			o.agent, err = next()
		case "-n":
			var v string
			v, err = next()
			if err == nil {
				o.n, err = strconv.Atoi(v)
			}
		default:
			if strings.HasPrefix(s, "--cmd=") {
				o.cmd = strings.TrimPrefix(s, "--cmd=")
			} else if strings.HasPrefix(s, "--agent=") {
				o.agent = strings.TrimPrefix(s, "--agent=")
			} else if strings.HasPrefix(s, "-") && len(s) > 1 && len(o.args) > 0 && (o.args[0] == "run" || o.args[0] == "shell") {
				o.rest = append(o.rest, a[i:]...)
				i = len(a)
			} else if len(o.args) == 0 && (s == "--help" || s == "--version") {
				o.args = append(o.args, s)
			} else if strings.HasPrefix(s, "--") {
				return o, fmt.Errorf("unknown option %s", s)
			} else {
				o.args = append(o.args, s)
			}
		}
		if err != nil {
			return o, err
		}
		if len(o.args) >= 2 && (o.args[0] == "run" || o.args[0] == "shell") && o.rest == nil {
			rest := a[i+1:]
			j := 0
			for j < len(rest) {
				r := rest[j]
				if r == "--no-sandbox" {
					o.noSandbox = true
				} else if r == "--sandbox" {
					o.sandbox = true
				} else if r == "--offline" {
					o.offline = true
				} else if r == "--cmd" && j+1 < len(rest) {
					o.cmd = rest[j+1]
					j++
				} else if strings.HasPrefix(r, "--cmd=") {
					o.cmd = strings.TrimPrefix(r, "--cmd=")
				} else if r == "--" {
					j++
					break
				} else {
					break
				}
				j++
			}
			o.rest = append([]string{}, rest[j:]...)
			break
		}
	}
	return o, nil
}

func usage() {
	fmt.Print(`usage: kwick-agents <command> [options]

Catalog and installs (per user; as root or with --system for every user):
  list [--json] [--installed]       agents and runtimes in the catalog
  info NAME [--json]                details, pinned version, sources, sandbox and keys
  install NAME... [--system] [--no-mcp]
                                    download the pinned release, verify it, install it
  remove NAME... [--system]         remove the program; your data and settings are kept
  update [NAME...] [--json]         move installed agents to the versions pinned now
  run NAME [--cmd C] [--no-sandbox] [--offline] [-- ARGS]
                                    start an agent in its sandbox with its keys
  shell NAME [-- COMMAND]           a shell (or one command) inside NAME's sandbox
  status [--json|--machine]         installed state of every catalog entry

Keys (Secret Service or KWallet on the desktop, a mode 600 file otherwise):
  key set NAME VAR [--dialog]       store a secret: stdin, a terminal prompt or a desktop dialog
  key rm NAME VAR                   delete a secret
  key list [NAME] [--json]          names of the stored secrets, never the values
                                    NAME "shared" is given to every agent

Permissions, sandbox and audit:
  grants [NAME] [--json]            what each agent may do through kwick-mcp
  grant NAME CAPABILITY allow|ask|deny
  folders NAME [add|rm PATH]        folders an agent may read and write through kwick-mcp
  sandbox NAME [on|off]             run NAME in bubblewrap (default on)
  network NAME [on|off]             network inside the sandbox
  consent [list|allow ID|always ID|deny ID] [--json]
                                    answer permission requests from a terminal
  audit [--json] [-n N] [--agent NAME]
                                    what agents asked for and what was decided
  control [list|stop [ID|NAME]] [--json]
                                    agents controlling the pointer and keyboard; stop them

MCP:
  mcp serve [--agent NAME]          the KwickOS MCP server on stdio (also: kwick-mcp)
  mcp enable NAME | disable NAME    register kwick-mcp in an agent's own config
  mcp status [--json]               which agents have kwick-mcp registered
  mcp tools [--json]                tools kwick-mcp offers and the capability each needs
  cua-driver mcp                    cua-driver compatible computer use server (also: kwick-cua-driver),
                                    routed through kwick-mcp; Cybara uses it for its computer use

Local models (also: kwick-inference):
  inference status|doctor|install|models|use|service|connect ...
                                    llama.cpp on http://127.0.0.1:11435/v1 (see: kwick-agents inference help)
  run --local NAME                  start Aider or Claude Code against the local endpoint

  doctor [--json]                   check bubblewrap, user namespaces, keystore and dialogs
  catalog                           the raw catalog as JSON
  version
`)
}

func main() {
	base := filepath.Base(os.Args[0])
	if base == "kwick-mcp" {
		o, err := parseOpts(os.Args[1:])
		if err != nil {
			fail(err)
		}
		os.Exit(mcpMain(o))
	}
	if base == "kwick-cua-driver" {
		os.Exit(cuaMain(os.Args[1:]))
	}
	if base == "kwick-inference" {
		os.Exit(inferenceMain(os.Args[1:]))
	}
	os.Exit(cli(os.Args[1:]))
}

func fail(err error) {
	fmt.Fprintf(os.Stderr, "%s: %v\n", prog, err)
	os.Exit(1)
}

func warnf(f string, a ...any) {
	fmt.Fprintf(os.Stderr, prog+": "+f+"\n", a...)
}

func emitJSON(v any) {
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		fail(err)
	}
}

type exitErr struct{ code int }

func (e exitErr) Error() string { return "exit " + strconv.Itoa(e.code) }

func cli(a []string) int {
	if len(a) > 0 && a[0] == "inference" {
		return inferenceMain(a[1:])
	}
	a = takeLocalFlag(a)
	o, err := parseOpts(a)
	if err != nil {
		warnf("%v", err)
		return 2
	}
	if len(o.args) == 0 {
		usage()
		return 0
	}
	cmd := o.args[0]
	pos := o.args[1:]
	var cat *Catalog
	needCat := map[string]bool{"list": true, "info": true, "install": true, "remove": true, "update": true, "run": true, "shell": true, "status": true, "all": true, "catalog": true, "mcp": true, "grants": true, "doctor": true}
	if needCat[cmd] {
		cat, err = loadCatalog()
		if err != nil {
			warnf("%v", err)
			return 1
		}
	}
	switch cmd {
	case "help", "-h", "--help":
		usage()
		return 0
	case "version", "--version":
		if o.json {
			emitJSON(map[string]any{"version": version})
		} else {
			fmt.Println(version)
		}
		return 0
	case "list":
		err = cmdList(cat, o)
	case "info":
		err = cmdInfo(cat, o, pos)
	case "status":
		err = cmdStatus(cat, o)
	case "install":
		err = cmdInstall(cat, o, pos)
	case "all":
		err = cmdAll(cat, o)
	case "remove", "uninstall":
		err = cmdRemove(cat, o, pos)
	case "update", "upgrade":
		err = cmdUpdate(cat, o, pos)
	case "run":
		return cmdRun(cat, o, pos, false)
	case "shell":
		return cmdRun(cat, o, pos, true)
	case "catalog":
		emitJSON(cat)
	case "key", "keys":
		err = cmdKey(o, pos)
	case "grants":
		err = cmdGrants(cat, o, pos)
	case "grant":
		err = cmdGrant(o, pos)
	case "folders":
		err = cmdFolders(o, pos)
	case "sandbox":
		err = cmdProfileToggle(o, pos, "sandbox")
	case "network":
		err = cmdProfileToggle(o, pos, "network")
	case "consent":
		err = cmdConsent(o, pos)
	case "audit":
		err = cmdAudit(o)
	case "control":
		err = cmdControl(o, pos)
	case "cua-driver":
		return cuaMain(pos)
	case "mcp":
		return cmdMCP(cat, o, pos)
	case "doctor":
		err = cmdDoctor(o)
	default:
		warnf("unknown command %q (see: kwick-agents help)", cmd)
		return 2
	}
	if err != nil {
		var ee exitErr
		if errors.As(err, &ee) {
			return ee.code
		}
		warnf("%v", err)
		return 1
	}
	return 0
}
