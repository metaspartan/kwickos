package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"text/tabwriter"
	"time"
)

type Asset struct {
	URL    string            `json:"url"`
	SHA256 string            `json:"sha256"`
	Size   int64             `json:"size,omitempty"`
	Format string            `json:"format"`
	Strip  int               `json:"strip,omitempty"`
	Rename map[string]string `json:"rename,omitempty"`
}

type Entry struct {
	Name        string            `json:"name"`
	Title       string            `json:"title"`
	Kind        string            `json:"kind"`
	Vendor      string            `json:"vendor"`
	Description string            `json:"description"`
	Homepage    string            `json:"homepage"`
	Source      string            `json:"source"`
	License     string            `json:"license"`
	Version     string            `json:"version"`
	Released    string            `json:"released,omitempty"`
	Method      string            `json:"method"`
	Assets      map[string]Asset  `json:"assets,omitempty"`
	Bin         map[string]string `json:"bin,omitempty"`
	Main        string            `json:"main,omitempty"`
	Runtime     string            `json:"runtime,omitempty"`
	Python      string            `json:"python,omitempty"`
	Lock        string            `json:"lock,omitempty"`
	Git         string            `json:"git,omitempty"`
	Tag         string            `json:"tag,omitempty"`
	Commit      string            `json:"commit,omitempty"`
	Scripts     []string          `json:"scripts,omitempty"`
	Keys        []string          `json:"keys,omitempty"`
	Home        []string          `json:"home,omitempty"`
	Env         map[string]string `json:"env,omitempty"`
	GPU         bool              `json:"gpu,omitempty"`
	Network     bool              `json:"network"`
	MCP         string            `json:"mcp,omitempty"`
	MCPHint     string            `json:"mcp_hint,omitempty"`
	Ports       []int             `json:"ports,omitempty"`
	Arch        []string          `json:"arch,omitempty"`
	Unsupported map[string]string `json:"unsupported,omitempty"`
	Needs       []string          `json:"needs,omitempty"`
	Verify      string            `json:"verify"`
	Install     string            `json:"upstream_install,omitempty"`
	FirstRun    string            `json:"first_run,omitempty"`
	Notes       string            `json:"notes,omitempty"`
	Hidden      bool              `json:"hidden,omitempty"`
}

type Catalog struct {
	Schema  int      `json:"schema"`
	Updated string   `json:"updated"`
	Entries []*Entry `json:"entries"`
	byName  map[string]*Entry
}

func catalogPath() string {
	if p := os.Getenv("KWICK_AGENTS_CATALOG"); p != "" {
		return p
	}
	return filepath.Join(libDir, "catalog.json")
}

func locksDir() string {
	if p := os.Getenv("KWICK_AGENTS_LOCKS"); p != "" {
		return p
	}
	return filepath.Join(libDir, "locks")
}

func loadCatalog() (*Catalog, error) {
	var c Catalog
	if err := readJSONFile(catalogPath(), &c); err != nil {
		return nil, fmt.Errorf("cannot read the catalog %s: %v", catalogPath(), err)
	}
	c.byName = map[string]*Entry{}
	for _, e := range c.Entries {
		c.byName[e.Name] = e
	}
	return &c, nil
}

func (c *Catalog) get(name string) (*Entry, error) {
	if e, ok := c.byName[name]; ok {
		return e, nil
	}
	for _, e := range c.Entries {
		for cmd := range e.Bin {
			if cmd == name && e.Kind != "runtime" {
				return e, nil
			}
		}
	}
	return nil, fmt.Errorf("unknown agent %q (see: kwick-agents list)", name)
}

func (c *Catalog) supported(e *Entry, arch string) (bool, string) {
	if r, ok := e.Unsupported[arch]; ok {
		return false, r
	}
	if r, ok := e.Unsupported["all"]; ok {
		return false, r
	}
	if len(e.Assets) > 0 {
		if _, ok := e.Assets[arch]; !ok {
			if _, any := e.Assets["any"]; !any {
				return false, "no upstream release for " + arch
			}
		}
	}
	if len(e.Arch) > 0 {
		found := false
		for _, a := range e.Arch {
			if a == arch {
				found = true
			}
		}
		if !found {
			return false, "not available on " + arch
		}
	}
	if e.Runtime != "" {
		rt, ok := c.byName[e.Runtime]
		if !ok {
			return false, "runtime " + e.Runtime + " missing from the catalog"
		}
		if ok, why := c.supported(rt, arch); !ok {
			return false, e.Runtime + ": " + why
		}
	}
	return true, ""
}

func (e *Entry) asset(arch string) (Asset, bool) {
	if a, ok := e.Assets[arch]; ok {
		return a, true
	}
	a, ok := e.Assets["any"]
	return a, ok
}

func (e *Entry) mainCmd() string {
	if e.Main != "" {
		return e.Main
	}
	keys := make([]string, 0, len(e.Bin))
	for k := range e.Bin {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	if len(keys) > 0 {
		return keys[0]
	}
	return e.Name
}

func (e *Entry) commands() []string {
	keys := make([]string, 0, len(e.Bin))
	for k := range e.Bin {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

type Installed struct {
	Name        string   `json:"name"`
	Version     string   `json:"version"`
	Method      string   `json:"method"`
	Dir         string   `json:"dir"`
	Runtime     string   `json:"runtime,omitempty"`
	RuntimeDir  string   `json:"runtime_dir,omitempty"`
	Commands    []string `json:"commands"`
	Shims       []string `json:"shims,omitempty"`
	InstalledAt string   `json:"installed_at"`
	Scope       string   `json:"scope"`
	Legacy      bool     `json:"legacy,omitempty"`
}

type State struct {
	Schema int                   `json:"schema"`
	Agents map[string]*Installed `json:"agents"`
}

func loadState(s Scope) *State {
	st := &State{Schema: 1, Agents: map[string]*Installed{}}
	readJSONFile(filepath.Join(s.State, "state.json"), st)
	if st.Agents == nil {
		st.Agents = map[string]*Installed{}
	}
	if s.System {
		if _, ok := st.Agents["cybara"]; !ok && exists(filepath.Join(sysState, "cybara")) && exists(filepath.Join(sysBin, "cybara")) {
			st.Agents["cybara"] = &Installed{Name: "cybara", Version: "unknown", Method: "binary", Dir: sysBin, Commands: []string{"cybara"}, Scope: "system", Legacy: true}
		}
	}
	return st
}

func saveState(s Scope, st *State) error {
	mode := os.FileMode(0o644)
	return writeJSONFile(filepath.Join(s.State, "state.json"), st, mode)
}

func findInstalled(name string) (*Installed, Scope, bool) {
	us := userScope()
	if !isRoot() {
		if in, ok := loadState(us).Agents[name]; ok {
			return in, us, true
		}
	}
	ss := systemScope()
	if in, ok := loadState(ss).Agents[name]; ok {
		return in, ss, true
	}
	if isRoot() {
		if in, ok := loadState(us).Agents[name]; ok {
			return in, us, true
		}
	}
	return nil, Scope{}, false
}

type ListItem struct {
	Name              string   `json:"name"`
	Title             string   `json:"title"`
	Kind              string   `json:"kind"`
	Vendor            string   `json:"vendor"`
	Description       string   `json:"description"`
	Homepage          string   `json:"homepage"`
	Source            string   `json:"source"`
	License           string   `json:"license"`
	Version           string   `json:"version"`
	Supported         bool     `json:"supported"`
	UnsupportedReason string   `json:"unsupported_reason,omitempty"`
	Installed         bool     `json:"installed"`
	InstalledVersion  string   `json:"installed_version,omitempty"`
	Scope             string   `json:"scope,omitempty"`
	UpdateAvailable   bool     `json:"update_available"`
	Commands          []string `json:"commands"`
	Keys              []string `json:"keys"`
	KeysSet           []string `json:"keys_set"`
	Sandbox           bool     `json:"sandbox"`
	Network           bool     `json:"network"`
	MCP               bool     `json:"mcp_supported"`
	MCPEnabled        bool     `json:"mcp_enabled"`
	DownloadSize      int64    `json:"download_size,omitempty"`
	Runtime           string   `json:"runtime,omitempty"`
}

func listItem(c *Catalog, e *Entry, arch string) ListItem {
	ok, why := c.supported(e, arch)
	it := ListItem{
		Name: e.Name, Title: e.Title, Kind: e.Kind, Vendor: e.Vendor, Description: e.Description,
		Homepage: e.Homepage, Source: e.Source, License: e.License, Version: e.Version,
		Supported: ok, UnsupportedReason: why, Commands: e.commands(), Keys: append([]string{}, e.Keys...),
		KeysSet: []string{}, Runtime: e.Runtime, MCP: e.MCP != "" && e.MCP != "none",
	}
	if it.Commands == nil {
		it.Commands = []string{}
	}
	if a, ok := e.asset(arch); ok {
		it.DownloadSize = a.Size
	}
	if in, sc, ok := findInstalled(e.Name); ok {
		it.Installed = true
		it.InstalledVersion = in.Version
		it.Scope = sc.Name()
		it.UpdateAvailable = in.Version != e.Version
	}
	if e.Kind != "runtime" {
		p := effectiveProfile(e)
		it.Sandbox = p.Sandbox
		it.Network = p.Network
		it.KeysSet = keyNames(e.Name)
		if it.MCP && it.Installed {
			it.MCPEnabled = mcpConfigured(e)
		}
	}
	return it
}

func cmdList(c *Catalog, o opts) error {
	arch := hostArch()
	var items []ListItem
	for _, e := range c.Entries {
		if e.Hidden {
			continue
		}
		it := listItem(c, e, arch)
		if o.installed && !it.Installed {
			continue
		}
		items = append(items, it)
	}
	if items == nil {
		items = []ListItem{}
	}
	if o.json {
		emitJSON(map[string]any{"schema": 1, "arch": arch, "catalog_updated": c.Updated, "agents": items})
		return nil
	}
	tw := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "NAME\tVERSION\tSTATE\tDESCRIPTION")
	for _, it := range items {
		state := "-"
		switch {
		case !it.Supported:
			state = "unavailable"
		case it.UpdateAvailable:
			state = "update " + it.InstalledVersion
		case it.Installed:
			state = "installed"
		}
		d := it.Description
		if !it.Supported {
			d = it.UnsupportedReason
		}
		fmt.Fprintf(tw, "%s\t%s\t%s\t%s\n", it.Name, it.Version, state, d)
	}
	return tw.Flush()
}

func cmdStatus(c *Catalog, o opts) error {
	arch := hostArch()
	if o.json {
		o.installed = false
		return cmdList(c, o)
	}
	for _, e := range c.Entries {
		if e.Hidden {
			continue
		}
		it := listItem(c, e, arch)
		st, note := "no", ""
		if !it.Supported {
			st, note = "na", it.UnsupportedReason
		} else if it.Installed {
			st = "yes"
		}
		if o.machine {
			fmt.Printf("%s|%s|%s|%s\n", e.Name, st, e.Description, note)
		} else {
			label := map[string]string{"yes": "installed", "no": "-", "na": "unavailable"}[st]
			if note == "" {
				note = e.Description
			}
			fmt.Printf("%-12s %-12s %s\n", e.Name, label, note)
		}
	}
	return nil
}

type Info struct {
	ListItem
	Released        string            `json:"released,omitempty"`
	Method          string            `json:"method"`
	Verify          string            `json:"verify"`
	UpstreamInstall string            `json:"upstream_install,omitempty"`
	Asset           *Asset            `json:"asset,omitempty"`
	Git             string            `json:"git,omitempty"`
	Commit          string            `json:"commit,omitempty"`
	InstallDir      string            `json:"install_dir,omitempty"`
	Shims           []string          `json:"shims,omitempty"`
	Profile         Profile           `json:"profile"`
	HomePaths       []string          `json:"home_paths"`
	Ports           []int             `json:"ports,omitempty"`
	MCPConfig       string            `json:"mcp_config,omitempty"`
	MCPHint         string            `json:"mcp_hint,omitempty"`
	FirstRun        string            `json:"first_run,omitempty"`
	Notes           string            `json:"notes,omitempty"`
	Grants          map[string]string `json:"grants,omitempty"`
	Folders         []string          `json:"folders"`
	Env             map[string]string `json:"env,omitempty"`
}

func cmdInfo(c *Catalog, o opts, pos []string) error {
	if len(pos) != 1 {
		return fmt.Errorf("usage: kwick-agents info NAME [--json]")
	}
	e, err := c.get(pos[0])
	if err != nil {
		return err
	}
	arch := hostArch()
	in := Info{ListItem: listItem(c, e, arch), Released: e.Released, Method: e.Method, Verify: e.Verify,
		UpstreamInstall: e.Install, Git: e.Git, Commit: e.Commit, Ports: e.Ports, MCPHint: e.MCPHint,
		FirstRun: e.FirstRun, Notes: e.Notes, Profile: effectiveProfile(e), HomePaths: e.Home, Env: e.Env, Folders: []string{}}
	if in.HomePaths == nil {
		in.HomePaths = []string{}
	}
	if a, ok := e.asset(arch); ok {
		in.Asset = &a
	}
	if inst, _, ok := findInstalled(e.Name); ok {
		in.InstallDir = inst.Dir
		in.Shims = inst.Shims
	}
	if e.Kind != "runtime" {
		g := loadGrants()
		in.Grants = effectiveGrants(g, e.Name)
		in.Folders = append(in.Folders, g.folders(e.Name)...)
		if f := mcpConfigFile(e); f != "" {
			in.MCPConfig = f
		}
	}
	if o.json {
		emitJSON(in)
		return nil
	}
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	row := func(k, v string) {
		if v != "" {
			fmt.Fprintf(w, "%s\t%s\n", k, v)
		}
	}
	row("Name", e.Name)
	row("Title", e.Title)
	row("Vendor", e.Vendor)
	row("Description", e.Description)
	row("License", e.License)
	row("Homepage", e.Homepage)
	row("Source", e.Source)
	row("Pinned version", e.Version+" "+e.Released)
	if !in.Supported {
		row("Available", "no: "+in.UnsupportedReason)
	}
	if in.Installed {
		row("Installed", in.InstalledVersion+" ("+in.Scope+") "+in.InstallDir)
	} else {
		row("Installed", "no")
	}
	row("Commands", strings.Join(in.Commands, ", "))
	row("Runtime", e.Runtime)
	row("Method", e.Method)
	if in.Asset != nil {
		row("Download", in.Asset.URL)
		row("sha256", in.Asset.SHA256)
	}
	if e.Git != "" {
		row("Git", e.Git+" "+e.Tag+" "+e.Commit)
	}
	row("Verification", e.Verify)
	row("Upstream install", e.Install)
	if e.Kind != "runtime" {
		sb := "on"
		if !in.Profile.Sandbox {
			sb = "off"
		}
		net := "on"
		if !in.Profile.Network {
			net = "off"
		}
		row("Sandbox", sb+", network "+net)
		row("Shared with sandbox", strings.Join(e.Home, " "))
		row("Keys used", strings.Join(e.Keys, " "))
		row("Keys stored", strings.Join(in.KeysSet, " "))
		mcp := "not supported by this agent"
		if in.MCP {
			mcp = "supported, not registered (kwick-agents mcp enable " + e.Name + ")"
			if in.MCPEnabled {
				mcp = "registered in " + shortPath(in.MCPConfig)
			}
		}
		if e.MCPHint != "" && !in.MCPEnabled {
			mcp = e.MCPHint
		}
		row("kwick-mcp", mcp)
		row("First run", e.FirstRun)
	}
	row("Notes", e.Notes)
	return w.Flush()
}

func nowStamp() string { return time.Now().UTC().Format(time.RFC3339) }
