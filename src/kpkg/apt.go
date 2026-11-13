package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

func aptUsage() {
	fmt.Printf(`kpkg %s (apt-compatible) for %s
Usage: apt [options] command

Commands:
  update          refresh package indexes
  install PKG...  install packages (also ./file.deb, pkg=version)
  reinstall PKG   reinstall packages
  remove PKG...   remove packages        purge PKG...  remove + config files
  autoremove      remove unneeded automatically installed packages
  upgrade         upgrade installed packages
  full-upgrade    upgrade, allowing removals (alias: dist-upgrade)
  search REGEX    search package names and descriptions
  show PKG        show package details
  list            list packages (--installed, --upgradable)
  policy PKG      show installed and candidate versions
  depends PKG     rdepends PKG
  download PKG    download .deb into the current directory
  clean           remove cached .deb files
Options: -y  -s/--dry-run  --no-install-recommends  --install-recommends
         -d/--download-only  -o RootDir=DIR | --root DIR  -q
`, kpkgVersion, cfg.Arch)
}

// parseCommon strips global options shared by apt-get/apt/apt-cache.
func parseCommon(args []string) []string {
	var rest []string
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "-y" || a == "--yes" || a == "--assume-yes" || a == "-qy" || a == "-yq":
			cfg.Yes = true
		case a == "-q" || a == "-qq" || a == "--quiet":
			cfg.Quiet++
		case a == "-s" || a == "--simulate" || a == "--dry-run" || a == "--just-print" || a == "--no-act":
			cfg.DryRun = true
		case a == "--no-install-recommends":
			cfg.Recommends = false
		case a == "--install-recommends":
			cfg.Recommends = true
		case a == "-d" || a == "--download-only":
			cfg.DownloadOnly = true
		case a == "--reinstall":
			cfg.Reinstall = true
		case a == "--purge":
			cfg.Purge = true
		case a == "--autoremove" || a == "--auto-remove":
			cfg.AutoRemove = true
		case a == "--root" && i+1 < len(args):
			cfg.Root = args[i+1]
			i++
		case a == "-o" && i+1 < len(args):
			k, v, _ := strings.Cut(args[i+1], "=")
			switch k {
			case "RootDir", "Dir":
				cfg.Root = v
			case "APT::Install-Recommends":
				cfg.Recommends = v == "true" || v == "1"
			case "APT::Get::Assume-Yes":
				cfg.Yes = v == "true" || v == "1"
			}
			i++
		case strings.HasPrefix(a, "-o"):
		case a == "--no-install-suggests" || a == "--fix-broken" || a == "-f" || a == "--fix-missing" ||
			a == "--allow-downgrades" || a == "--allow-remove-essential" || a == "--allow-change-held-packages" ||
			a == "--no-upgrade" || a == "--only-upgrade" || a == "-m" || a == "--force-yes" || a == "--allow-unauthenticated" ||
			a == "--no-show-upgraded" || a == "-V" || a == "--verbose-versions" || a == "--show-progress" || a == "--no-cache":
		case a == "-t" || a == "--target-release" || a == "-a" || a == "--host-architecture":
			i++
		default:
			rest = append(rest, a)
		}
	}
	return rest
}

func mustDB(avail bool) *DB {
	db, err := OpenDB()
	if err != nil {
		die(err)
	}
	if avail {
		db.LoadAvailable()
	}
	return db
}

func mainApt(name string, args []string) int {
	setupPaths()
	args = parseCommon(args)
	setupPaths() // re-derive paths if --root changed
	if len(args) == 0 {
		aptUsage()
		return 1
	}
	cmd, args := args[0], args[1:]
	needRoot := map[string]bool{"update": true, "install": true, "reinstall": true, "remove": true, "purge": true,
		"autoremove": true, "upgrade": true, "full-upgrade": true, "dist-upgrade": true, "clean": true, "autoclean": true}
	if needRoot[cmd] && os.Geteuid() != 0 && !cfg.DryRun {
		fmt.Fprintln(os.Stderr, "E: This command requires root privileges (try sudo or su).")
		return 100
	}
	var err error
	switch cmd {
	case "update":
		err = Update()
	case "install", "reinstall":
		if cmd == "reinstall" {
			cfg.Reinstall = true
		}
		err = cmdInstall(args)
	case "remove", "purge", "autoremove", "autopurge":
		if cmd == "purge" || cmd == "autopurge" {
			cfg.Purge = true
		}
		err = cmdRemove(args, strings.HasPrefix(cmd, "auto"))
	case "upgrade", "full-upgrade", "dist-upgrade":
		err = cmdUpgrade(cmd != "upgrade")
	case "search":
		return mainAptCache(append([]string{"search"}, args...))
	case "show", "policy", "depends", "rdepends", "showpkg", "pkgnames", "madison":
		return mainAptCache(append([]string{cmd}, args...))
	case "list":
		err = cmdList(args)
	case "download":
		err = cmdDownload(args)
	case "clean", "autoclean":
		m, _ := filepath.Glob(filepath.Join(cfg.Cache, "*.deb"))
		for _, f := range m {
			os.Remove(f)
		}
		os.RemoveAll(filepath.Join(cfg.Cache, "partial"))
	case "check":
	case "moo":
		fmt.Println("                 (__)\n                 (oo)\n           /------\\/\n          / |    ||\n         *  /\\---/\\\n            ~~   ~~\n....\"Have you mooed today?\"... (kpkg edition)")
	case "--version", "-v", "version":
		fmt.Printf("kpkg %s (apt-compatible, KwickOS) %s\n", kpkgVersion, cfg.Arch)
	case "-h", "--help", "help":
		aptUsage()
	case "edit-sources":
		ed := os.Getenv("EDITOR")
		if ed == "" {
			ed = "vi"
		}
		return runInteractive(ed, filepath.Join(cfg.Root, "etc/apt/sources.list.d/debian.sources"))
	default:
		fmt.Fprintf(os.Stderr, "E: Invalid operation %s\n", cmd)
		return 100
	}
	if err != nil {
		die(err)
	}
	return 0
}

// resolveRequest maps "pkg", "pkg=ver", "pkg/suite", "./x.deb" to a Pkg.
func resolveRequest(db *DB, req string) (*Pkg, error) {
	if strings.HasSuffix(req, ".deb") {
		abs, _ := filepath.Abs(req)
		dc, err := ReadDebControl(abs)
		if err != nil {
			return nil, err
		}
		p := newPkg(dc.Para)
		if !p.archOK() && !cfg.ForceArch {
			return nil, fmt.Errorf("%s: package architecture (%s) does not match system (%s)", req, p.Arch, cfg.Arch)
		}
		p.LocalDeb = abs
		db.addAvail(p)
		vs := db.Avail[p.Key()]
		sort.SliceStable(vs, func(i, j int) bool { return vs[i] == p })
		return p, nil
	}
	name, ver, hasVer := strings.Cut(req, "=")
	suite := ""
	if n, s, ok := strings.Cut(name, "/"); ok {
		name, suite = n, s
	}
	base, qual, qualified := strings.Cut(name, ":")
	foreign := ""
	if qualified {
		switch {
		case qual == "any" || qual == "native" || qual == cfg.Arch || qual == "all":
			name = base
		case contains(cfg.Foreign, qual):
			foreign = qual
		default:
			return nil, fmt.Errorf("unable to locate package %s (architecture '%s' is not enabled; see dpkg --add-architecture)", name, qual)
		}
	}
	pools := [][]*Pkg{db.Avail[name]}
	if foreign != "" {
		var allOnly []*Pkg
		for _, p := range db.Avail[base] {
			if p.Arch == "all" {
				allOnly = append(allOnly, p)
			}
		}
		pools = append(pools, allOnly)
	}
	for _, pool := range pools {
		for _, p := range pool {
			if hasVer && p.Version != ver {
				continue
			}
			if suite != "" && p.Src != nil && p.Src.Suite != suite {
				continue
			}
			return p, nil
		}
	}
	if !hasVer {
		// virtual package with a single provider
		var provs []*Pkg
		seen := map[string]bool{}
		for _, pr := range db.provAvail[base] {
			if foreign == "" && pr.pkg.Arch != cfg.Arch && pr.pkg.Arch != "all" {
				continue
			}
			if foreign != "" && pr.pkg.Arch != foreign && pr.pkg.Arch != "all" {
				continue
			}
			if !seen[pr.pkg.Key()] && db.Candidate(pr.pkg.Key()) == pr.pkg {
				seen[pr.pkg.Key()] = true
				provs = append(provs, pr.pkg)
			}
		}
		if len(provs) == 1 {
			fmt.Printf("Note, selecting '%s' instead of '%s'\n", provs[0].Name, name)
			return provs[0], nil
		}
		if len(provs) > 1 {
			var ns []string
			for _, p := range provs {
				ns = append(ns, p.Name)
			}
			return nil, fmt.Errorf("package %s is a virtual package provided by: %s\nYou should explicitly select one to install", name, strings.Join(ns, ", "))
		}
	}
	if hasVer {
		return nil, fmt.Errorf("version '%s' for '%s' was not found", ver, name)
	}
	if in := db.lookupInstalled(name); in != nil && in.Field("X-Kwick-Base") == "yes" {
		return nil, fmt.Errorf("%s is part of the KwickOS base system", name)
	}
	return nil, fmt.Errorf("unable to locate package %s", name)
}

func cmdInstall(args []string) error {
	db := mustDB(true)
	if len(args) == 0 {
		return errors.New("no packages specified")
	}
	pl := db.NewPlan(ResolveOpts{Recommends: cfg.Recommends, Upgrade: true})
	var explicit []string
	for _, a := range args {
		if strings.HasSuffix(a, "-") && !strings.HasSuffix(a, ".deb") { // apt install foo-  => remove
			if in := db.lookupInstalled(strings.TrimSuffix(a, "-")); in != nil {
				pl.Remove[in.InfoName()] = in
			}
			continue
		}
		p, err := resolveRequest(db, a)
		if err != nil {
			return err
		}
		if in := db.lookupInstalled(p.Key()); in != nil && in.Key() == p.Key() && in.Version == p.Version && in.State() == "installed" && !cfg.Reinstall {
			fmt.Printf("%s is already the newest version (%s).\n", p.Key(), p.Version)
			if db.Auto[p.Key()] {
				delete(db.Auto, p.Key())
				fmt.Printf("%s set to manually installed.\n", p.Key())
				db.SaveAuto()
			}
			continue
		}
		pl.Add(p, true)
		explicit = append(explicit, p.Key())
	}
	fmt.Println("Reading package lists... Done\nBuilding dependency tree... Done")
	if err := pl.Resolve(); err != nil {
		return err
	}
	return runPlan(pl, len(pl.Install) > len(explicit) || len(pl.Remove) > 0)
}

func runPlan(pl *Plan, extra bool) error {
	if !pl.Summary() {
		return nil
	}
	if cfg.DryRun {
		for _, g := range pl.Order() {
			for _, p := range g {
				fmt.Printf("Inst %s (%s %s [%s])\n", p.Key(), p.Version, srcLabel(p), p.Arch)
			}
		}
		for _, k := range sortedKeys(pl.Remove) {
			fmt.Printf("Remv %s [%s]\n", pl.Remove[k].Key(), pl.Remove[k].Version)
		}
		return nil
	}
	if !confirm(extra) {
		return errors.New("Abort.")
	}
	return pl.Execute(cfg.Purge)
}

func srcLabel(p *Pkg) string {
	if p.Src == nil {
		return "local"
	}
	return p.Src.Suite + "/" + p.Src.Comp
}

func cmdRemove(args []string, auto bool) error {
	db := mustDB(false)
	var pl *Plan
	var err error
	names := args
	if auto || cfg.AutoRemove {
		for _, in := range db.Autoremovable() {
			names = append(names, in.Key())
		}
	}
	if len(names) == 0 {
		fmt.Println("0 upgraded, 0 newly installed, 0 to remove.")
		return nil
	}
	if pl, err = db.RemovalPlan(names); err != nil {
		return err
	}
	return runPlan(pl, len(pl.Remove) > len(args))
}

func cmdUpgrade(full bool) error {
	db := mustDB(true)
	pl := db.NewPlan(ResolveOpts{Recommends: false, Upgrade: true, NoRemove: !full})
	for _, p := range db.Upgradable() {
		if in := db.lookupInstalled(p.Key()); in != nil && in.Field("X-Kwick-Base") == "yes" {
			continue
		}
		pl.Add(p, !db.Auto[p.Key()])
	}
	fmt.Println("Reading package lists... Done\nBuilding dependency tree... Done\nCalculating upgrade... Done")
	if err := pl.Resolve(); err != nil {
		return err
	}
	return runPlan(pl, true)
}

func cmdList(args []string) error {
	installed, upgradable := false, false
	var pats []string
	for _, a := range args {
		switch a {
		case "--installed", "-i":
			installed = true
		case "--upgradable", "--upgradeable", "-u":
			upgradable = true
		case "--all-versions", "-a", "--manual-installed":
		default:
			pats = append(pats, a)
		}
	}
	db := mustDB(!installed || upgradable)
	match := func(n string) bool {
		if len(pats) == 0 {
			return true
		}
		for _, p := range pats {
			if ok, _ := filepath.Match(p, n); ok || p == n {
				return true
			}
		}
		return false
	}
	fmt.Println("Listing... Done")
	if upgradable {
		for _, p := range db.Upgradable() {
			if match(p.Name) || match(p.Key()) {
				in := db.lookupInstalled(p.Key())
				fmt.Printf("%s/%s %s %s [upgradable from: %s]\n", p.Name, srcSuite(p), p.Version, p.Arch, in.Version)
			}
		}
		return nil
	}
	if installed {
		for _, k := range sortedKeys(db.Installed) {
			in := db.Installed[k]
			if !(match(in.Name) || match(in.Key())) || in.State() == "not-installed" {
				continue
			}
			tag := "installed"
			if db.Auto[in.Key()] {
				tag = "installed,automatic"
			}
			if in.State() == "config-files" {
				tag = "residual-config"
			}
			fmt.Printf("%s/now %s %s [%s]\n", in.Name, in.Version, in.Arch, tag)
		}
		return nil
	}
	for _, n := range sortedKeys(db.Avail) {
		p := db.Avail[n][0]
		if !match(n) && !match(p.Name) {
			continue
		}
		tag := ""
		if in := db.lookupInstalled(n); in != nil && in.Key() == n {
			tag = " [installed]"
			if in.Version != p.Version {
				tag = " [installed,upgradable to: " + p.Version + "]"
			}
		}
		fmt.Printf("%s/%s %s %s%s\n", p.Name, srcSuite(p), p.Version, p.Arch, tag)
	}
	return nil
}

func srcSuite(p *Pkg) string {
	if p.Src == nil {
		return "now"
	}
	return p.Src.Suite
}

func cmdDownload(args []string) error {
	db := mustDB(true)
	for _, a := range args {
		p, err := resolveRequest(db, a)
		if err != nil {
			return err
		}
		dst := fmt.Sprintf("%s_%s_%s.deb", p.Name, strings.ReplaceAll(p.Version, ":", "%3a"), p.Arch)
		url := strings.TrimRight(p.Src.URI, "/") + "/" + p.Field("Filename")
		os.MkdirAll("partial", 0755)
		if err := fetchTo(url, dst, p.Field("SHA256"), p.Size()); err != nil {
			return err
		}
		os.Remove("partial")
		fmt.Printf("Get:1 %s %s %s [%s]\n", url, p.Name, p.Version, human(p.Size()))
	}
	return nil
}

func mainAptCache(args []string) int {
	setupPaths()
	args = parseCommon(args)
	setupPaths()
	if len(args) == 0 {
		aptUsage()
		return 1
	}
	cmd, args := args[0], args[1:]
	switch cmd {
	case "search":
		db := mustDB(true)
		var res []*regexp.Regexp
		for _, a := range args {
			re, err := regexp.Compile("(?i)" + a)
			if err != nil {
				die(err)
			}
			res = append(res, re)
		}
		for _, n := range sortedKeys(db.Avail) {
			p := db.Avail[n][0]
			text := n + " " + p.Field("Description")
			ok := true
			for _, re := range res {
				if !re.MatchString(text) {
					ok = false
					break
				}
			}
			if ok {
				tag := ""
				if db.lookupInstalled(n) != nil {
					tag = " [installed]"
				}
				fmt.Printf("%s/%s %s %s%s\n  %s\n\n", p.Name, srcSuite(p), p.Version, p.Arch, tag, strings.SplitN(p.Field("Description"), "\n", 2)[0])
			}
		}
	case "show", "showpkg":
		db := mustDB(true)
		for _, a := range args {
			p, err := resolveRequest(db, a)
			if err != nil {
				if in := db.lookupInstalled(a); in != nil {
					p = in.Pkg
				} else {
					die(err)
				}
			}
			for _, k := range p.P.Keys {
				if k == "SHA256" || k == "Filename" || k == "Size" {
					continue
				}
				fmt.Printf("%s: %s\n", k, p.Field(k))
			}
			fmt.Printf("Download-Size: %s\n", human(p.Size()))
			if p.Src != nil {
				fmt.Printf("APT-Sources: %s %s/%s %s Packages\n", strings.TrimRight(p.Src.URI, "/"), p.Src.Suite, p.Src.Comp, p.Arch)
			}
			if db.installedByKey(p.Key()) != nil {
				fmt.Println("APT-Manual-Installed:", map[bool]string{true: "no", false: "yes"}[db.Auto[p.Key()]])
			}
			fmt.Println()
		}
	case "policy", "madison":
		db := mustDB(true)
		for _, a := range args {
			fmt.Printf("%s:\n", a)
			iv := "(none)"
			if in := db.lookupInstalled(a); in != nil {
				iv = in.Version
			}
			cv := "(none)"
			if c := db.Candidate(a); c != nil {
				cv = c.Version
			}
			fmt.Printf("  Installed: %s\n  Candidate: %s\n  Version table:\n", iv, cv)
			for _, p := range db.Avail[a] {
				mark := "    "
				if p.Version == iv {
					mark = " *** "
				}
				fmt.Printf(" %s%s 500\n        500 %s %s/%s %s Packages\n", mark, p.Version, strings.TrimRight(p.Src.URI, "/"), p.Src.Suite, p.Src.Comp, p.Arch)
			}
		}
	case "depends":
		db := mustDB(true)
		for _, a := range args {
			p := db.Candidate(a)
			if p == nil {
				die(fmt.Errorf("unable to locate package %s", a))
			}
			fmt.Println(p.Name)
			for _, fld := range []string{"Pre-Depends", "Depends", "Recommends", "Suggests", "Conflicts", "Breaks", "Replaces"} {
				for _, g := range p.Deps(fld) {
					for i, d := range g {
						pfx := "  "
						if i < len(g)-1 {
							pfx = " |"
						}
						fmt.Printf("%s%s: %s\n", pfx, fld, d)
					}
				}
			}
		}
	case "rdepends":
		db := mustDB(true)
		for _, a := range args {
			fmt.Printf("%s\nReverse Depends:\n", a)
			for _, n := range sortedKeys(db.Avail) {
				p := db.Avail[n][0]
				for _, fld := range []string{"Pre-Depends", "Depends"} {
					for _, g := range p.Deps(fld) {
						for _, d := range g {
							if d.Name == a {
								fmt.Printf("  %s\n", n)
							}
						}
					}
				}
			}
		}
	case "pkgnames":
		db := mustDB(true)
		for _, n := range sortedKeys(db.Avail) {
			if len(args) == 0 || strings.HasPrefix(n, args[0]) {
				fmt.Println(n)
			}
		}
	case "stats":
		db := mustDB(true)
		fmt.Printf("Total package names: %d\nInstalled: %d\nVirtual packages: %d\n", len(db.Avail), len(db.Installed), len(db.provAvail))
	case "policy-all", "gencaches":
	default:
		fmt.Fprintf(os.Stderr, "E: Invalid operation %s\n", cmd)
		return 100
	}
	return 0
}

func mainAptMark(args []string) int {
	setupPaths()
	args = parseCommon(args)
	setupPaths()
	if len(args) == 0 {
		fmt.Println("Usage: apt-mark auto|manual|showauto|showmanual|hold|unhold PKG...")
		return 1
	}
	db := mustDB(false)
	switch args[0] {
	case "auto", "markauto":
		for _, n := range args[1:] {
			db.Auto[markKey(db, n)] = true
			fmt.Printf("%s set to automatically installed.\n", n)
		}
		db.SaveAuto()
	case "manual", "unmarkauto":
		for _, n := range args[1:] {
			delete(db.Auto, markKey(db, n))
			fmt.Printf("%s set to manually installed.\n", n)
		}
		db.SaveAuto()
	case "showauto":
		for _, k := range sortedKeys(db.Auto) {
			fmt.Println(k)
		}
	case "showmanual":
		for _, k := range sortedKeys(db.Installed) {
			if in := db.Installed[k]; !db.Auto[in.Key()] && in.Field("X-Kwick-Base") != "yes" {
				fmt.Println(in.Key())
			}
		}
	case "hold", "unhold", "showhold":
		// holds are recorded in dpkg selections in Debian; accepted for compatibility
	default:
		fmt.Fprintf(os.Stderr, "E: Invalid operation %s\n", args[0])
		return 100
	}
	return 0
}
