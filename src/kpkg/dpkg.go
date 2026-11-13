package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

func runInteractive(name string, args ...string) int {
	c := exec.Command(name, args...)
	c.Stdin, c.Stdout, c.Stderr = os.Stdin, os.Stdout, os.Stderr
	if err := c.Run(); err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			return ee.ExitCode()
		}
		return 1
	}
	return 0
}

func parseDpkgOpts(args []string) []string {
	var rest []string
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case strings.HasPrefix(a, "--root="):
			cfg.Root = strings.TrimPrefix(a, "--root=")
		case a == "--root" && i+1 < len(args):
			cfg.Root = args[i+1]
			i++
		case a == "--force-architecture" || a == "--force-all":
			cfg.ForceArch = true
		case strings.HasPrefix(a, "--force-") || strings.HasPrefix(a, "--no-force-") || strings.HasPrefix(a, "--refuse-") ||
			a == "--no-triggers" || a == "--triggers" || a == "--no-debsig" || a == "--abort-after" ||
			strings.HasPrefix(a, "--admindir") || strings.HasPrefix(a, "--instdir") || strings.HasPrefix(a, "--log") ||
			a == "--skip-same-version" || a == "-G" || a == "--refuse-downgrade" || a == "-E" || a == "-B" || a == "--auto-deconfigure" ||
			a == "--no-pager" || a == "--recursive" || a == "-R":
		default:
			rest = append(rest, a)
		}
	}
	setupPaths()
	return rest
}

func mainDpkg(args []string) int {
	setupPaths()
	args = parseDpkgOpts(args)
	if len(args) == 0 {
		fmt.Println("Type dpkg --help for help about installing and deinstalling packages.")
		return 2
	}
	cmd, rest := args[0], args[1:]
	switch cmd {
	case "--version":
		fmt.Printf("Debian 'dpkg' package management program version %s (kpkg %s, %s).\n", dpkgCompatVersion, kpkgVersion, cfg.Arch)
	case "--print-architecture":
		fmt.Println(cfg.Arch)
	case "--print-foreign-architectures":
		for _, a := range cfg.Foreign {
			fmt.Println(a)
		}
	case "--add-architecture", "--remove-architecture":
		if len(rest) != 1 {
			fmt.Fprintf(os.Stderr, "dpkg: error: %s takes exactly one argument\n", cmd)
			return 2
		}
		var err error
		if cmd == "--add-architecture" {
			err = addArchitecture(rest[0])
		} else {
			err = removeArchitecture(rest[0])
		}
		if err != nil {
			fmt.Fprintln(os.Stderr, "dpkg: error:", err)
			return 2
		}
	case "--compare-versions":
		if len(rest) != 3 {
			fmt.Fprintln(os.Stderr, "dpkg: --compare-versions takes three arguments")
			return 2
		}
		return compareCmd(rest[0], rest[1], rest[2])
	case "--assert-multi-conffiles", "--assert-support-predepends", "--assert-working-epoch",
		"--assert-long-filenames", "--assert-versioned-provides", "--assert-multi-arch",
		"--assert-protected-field", "--clear-avail", "--update-avail", "--merge-avail", "--forget-old-unavail",
		"--set-selections", "--clear-selections", "--verify", "-V":
		return 0
	case "-i", "--install", "--unpack":
		return dpkgInstall(rest, cmd == "--unpack")
	case "-r", "--remove", "-P", "--purge":
		cfg.Purge = cmd == "-P" || cmd == "--purge"
		db := mustDB(false)
		pl := db.NewPlan(ResolveOpts{})
		for _, n := range rest {
			if in := db.lookupInstalled(n); in != nil {
				pl.Remove[in.InfoName()] = in
			} else {
				fmt.Fprintf(os.Stderr, "dpkg: warning: ignoring request to remove %s which isn't installed\n", n)
			}
		}
		if len(pl.Remove) == 0 {
			return 0
		}
		if err := pl.Execute(cfg.Purge); err != nil {
			fmt.Fprintln(os.Stderr, "dpkg: error:", err)
			return 1
		}
	case "--configure", "--triggers-only":
		db := mustDB(false)
		tx := &Tx{db: db, activated: map[string]bool{}, prevVer: map[string]string{}}
		rc := 0
		for _, k := range sortedKeys(db.Installed) {
			in := db.Installed[k]
			want := len(rest) > 0 && (rest[0] == "-a" || rest[0] == "--pending" || contains(rest, in.Name))
			if want && (in.State() == "unpacked" || in.State() == "half-configured") {
				if err := tx.configure(in.Pkg); err != nil {
					fmt.Fprintln(os.Stderr, "dpkg: error:", err)
					rc = 1
				}
			}
		}
		return rc
	case "-l", "--list":
		return dpkgList(rest)
	case "-L", "--listfiles", "-S", "--search", "-s", "--status", "-p", "--print-avail", "--get-selections", "-W", "--show":
		return mainDpkgQuery(args)
	case "-C", "--audit":
		db := mustDB(false)
		for _, k := range sortedKeys(db.Installed) {
			if st := db.Installed[k].State(); st != "installed" && st != "config-files" {
				fmt.Printf("%s is in state %s\n", k, st)
			}
		}
	case "-x", "--extract", "-X", "--vextract", "-c", "--contents", "-I", "--info", "-f", "--field", "-e", "--control", "-b", "--build", "--fsys-tarfile":
		return mainDpkgDeb(args)
	case "--help", "-h":
		fmt.Println("dpkg (kpkg): -i|--install <.deb>  -r|--remove <pkg>  -P|--purge <pkg>  -l|--list  -L <pkg>  -S <pattern>\n" +
			"  -s <pkg>  --configure -a  --compare-versions a op b  --print-architecture  -x <.deb> <dir>  -c <.deb>")
	default:
		fmt.Fprintf(os.Stderr, "dpkg: error: unknown option %s\n", cmd)
		return 2
	}
	return 0
}

func compareCmd(a, op, b string) int {
	nl := strings.HasSuffix(op, "-nl")
	op = strings.TrimSuffix(op, "-nl")
	if nl && (a == "" || b == "") {
		switch op {
		case "lt", "le":
			if a == "" {
				return 1
			}
			return 0
		case "gt", "ge":
			if a == "" {
				return 0
			}
			return 1
		}
	}
	c := CompareVersions(a, b)
	var ok bool
	switch op {
	case "lt", "<<", "<":
		ok = c < 0
	case "le", "<=":
		ok = c <= 0
	case "eq", "=":
		ok = c == 0
	case "ne":
		ok = c != 0
	case "ge", ">=":
		ok = c >= 0
	case "gt", ">>", ">":
		ok = c > 0
	default:
		fmt.Fprintf(os.Stderr, "dpkg: error: unknown version comparison operator %s\n", op)
		return 2
	}
	if ok {
		return 0
	}
	return 1
}

func dpkgInstall(files []string, unpackOnly bool) int {
	db := mustDB(false)
	db.provAvail = map[string][]provider{}
	pl := db.NewPlan(ResolveOpts{})
	for _, f := range files {
		if fi, err := os.Stat(f); err == nil && fi.IsDir() {
			m, _ := filepath.Glob(filepath.Join(f, "*.deb"))
			files = append(files, m...)
			continue
		}
		p, err := resolveRequest(db, f)
		if err != nil {
			fmt.Fprintln(os.Stderr, "dpkg: error:", err)
			return 1
		}
		pl.Add(p, true)
	}
	// dpkg semantics: no resolution; report unmet deps but still unpack
	broken := false
	for _, p := range pl.Install {
		for _, fld := range []string{"Pre-Depends", "Depends"} {
			for _, g := range p.Deps(fld) {
				if !pl.groupSatisfied(g, p.selfArch()) {
					fmt.Fprintf(os.Stderr, "dpkg: dependency problems prevent configuration of %s:\n %s depends on %s; however it is not installed.\n", p.Key(), p.Key(), g[0])
					broken = true
				}
			}
		}
	}
	if broken {
		unpackOnly = true
	}
	cfg.DownloadOnly = false
	if unpackOnly {
		unlock, err := lockDB()
		if err != nil {
			fmt.Fprintln(os.Stderr, "dpkg: error:", err)
			return 2
		}
		defer unlock()
		tx := &Tx{db: db, plan: pl, activated: map[string]bool{}, prevVer: map[string]string{}}
		tx.loadOwners()
		for _, p := range pl.Install {
			if err := tx.unpack(p, p.LocalDeb); err != nil {
				fmt.Fprintln(os.Stderr, "dpkg: error:", err)
				return 1
			}
		}
		db.SaveStatus()
		if broken {
			fmt.Fprintln(os.Stderr, "Errors were encountered while processing packages (run 'apt install -f' / install their dependencies).")
			return 1
		}
		return 0
	}
	if err := pl.Execute(false); err != nil {
		fmt.Fprintln(os.Stderr, "dpkg: error:", err)
		return 1
	}
	return 0
}

func statusAbbrev(st string) string {
	f := strings.Fields(st)
	if len(f) != 3 {
		return "un "
	}
	want := map[string]string{"install": "i", "hold": "h", "deinstall": "r", "purge": "p", "unknown": "u"}[f[0]]
	cur := map[string]string{"installed": "i", "config-files": "c", "unpacked": "U", "half-configured": "F",
		"half-installed": "H", "triggers-awaited": "W", "triggers-pending": "t", "not-installed": "n"}[f[2]]
	return want + cur + " "
}

func dpkgList(pats []string) int {
	db := mustDB(false)
	fmt.Println("Desired=Unknown/Install/Remove/Purge/Hold\n| Status=Not/Inst/Conf-files/Unpacked/halF-conf/Half-inst/trig-aWait/Trig-pend\n|/ Err?=(none)/Reinst-required (Status,Err: uppercase=bad)\n||/ Name                       Version                      Architecture Description\n+++-==========================-============================-============-================================================")
	for _, k := range sortedKeys(db.Installed) {
		in := db.Installed[k]
		if len(pats) > 0 {
			ok := false
			for _, p := range pats {
				if matchInstalledPattern(p, in) {
					ok = true
				}
			}
			if !ok {
				continue
			}
		}
		desc := strings.SplitN(in.Field("Description"), "\n", 2)[0]
		fmt.Printf("%s %-26s %-28s %-12s %s\n", statusAbbrev(in.Status), k, in.Version, in.Arch, desc)
	}
	return 0
}

func mainDpkgQuery(args []string) int {
	setupPaths()
	args = parseDpkgOpts(args)
	format := "${binary:Package}\t${Version}\n"
	var cmd string
	var pats []string
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "-f" || a == "--showformat":
			if i+1 < len(args) {
				format = args[i+1]
				i++
			}
		case strings.HasPrefix(a, "--showformat="):
			format = strings.TrimPrefix(a, "--showformat=")
		case strings.HasPrefix(a, "-f") && len(a) > 2 && cmd != "":
			format = a[2:]
		case strings.HasPrefix(a, "-") && cmd == "":
			cmd = a
		default:
			pats = append(pats, a)
		}
	}
	db := mustDB(false)
	find := func(n string) *Installed {
		if in := db.lookupInstalled(n); in != nil {
			return in
		}
		return db.baseVirtual(n)
	}
	switch cmd {
	case "-W", "--show":
		rc := 1
		for _, k := range sortedKeys(db.Installed) {
			in := db.Installed[k]
			if len(pats) > 0 {
				ok := false
				for _, p := range pats {
					if matchInstalledPattern(p, in) || (strings.HasSuffix(p, ":"+cfg.Arch) && matchInstalledPattern(strings.TrimSuffix(p, ":"+cfg.Arch), in) && (in.Arch == cfg.Arch || in.Arch == "all")) {
						ok = true
					}
				}
				if !ok {
					continue
				}
			}
			rc = 0
			fmt.Print(expandFormat(format, in))
		}
		if len(pats) > 0 && rc != 0 {
			for _, p := range pats {
				if v := db.baseVirtual(strings.TrimSuffix(p, ":"+cfg.Arch)); v != nil {
					fmt.Print(expandFormat(format, v))
					rc = 0
				}
			}
		}
		if len(pats) > 0 && rc != 0 {
			fmt.Fprintf(os.Stderr, "dpkg-query: no packages found matching %s\n", strings.Join(pats, " "))
		}
		if len(pats) == 0 {
			rc = 0
		}
		return rc
	case "-s", "--status", "-p", "--print-avail":
		rc := 0
		for _, n := range pats {
			in := find(n)
			if in == nil {
				fmt.Fprintf(os.Stderr, "dpkg-query: package '%s' is not installed and no information is available\n", n)
				rc = 1
				continue
			}
			in.P.Write822(os.Stdout)
			fmt.Println()
		}
		return rc
	case "-L", "--listfiles":
		rc := 0
		for _, n := range pats {
			in := find(n)
			if in == nil {
				fmt.Fprintf(os.Stderr, "dpkg-query: package '%s' is not installed\n", n)
				rc = 1
				continue
			}
			for _, f := range readList(in.InfoName()) {
				fmt.Println(f)
			}
		}
		return rc
	case "-S", "--search":
		owners := map[string][]string{}
		for k := range db.Installed {
			for _, f := range readList(k) {
				owners[f] = append(owners[f], k)
			}
		}
		found := false
		for _, pat := range pats {
			glob := strings.ContainsAny(pat, "*?[")
			for _, f := range sortedKeys(owners) {
				var hit bool
				if glob {
					hit, _ = filepath.Match(pat, f)
				} else if strings.HasPrefix(pat, "/") {
					hit = f == pat
				} else {
					hit = strings.Contains(f, pat)
				}
				if hit {
					found = true
					fmt.Printf("%s: %s\n", strings.Join(owners[f], ", "), f)
				}
			}
		}
		if !found {
			fmt.Fprintf(os.Stderr, "dpkg-query: no path found matching pattern %s\n", strings.Join(pats, " "))
			return 1
		}
	case "-l", "--list":
		return dpkgList(pats)
	case "--get-selections":
		for _, k := range sortedKeys(db.Installed) {
			fmt.Printf("%-40s\tinstall\n", k)
		}
	case "-c", "--control-path":
		for _, n := range pats[1:] {
			fmt.Println(filepath.Join("/var/lib/dpkg/info", pats[0]+"."+n))
		}
	default:
		fmt.Fprintln(os.Stderr, "dpkg-query: need an action option (-W, -s, -L, -S, -l)")
		return 2
	}
	return 0
}

func expandFormat(f string, in *Installed) string {
	f = strings.NewReplacer(`\n`, "\n", `\t`, "\t", `\\`, `\`).Replace(f)
	var b strings.Builder
	for {
		i := strings.Index(f, "${")
		if i < 0 {
			b.WriteString(f)
			break
		}
		b.WriteString(f[:i])
		j := strings.IndexByte(f[i:], '}')
		if j < 0 {
			b.WriteString(f[i:])
			break
		}
		field := f[i+2 : i+j]
		f = f[i+j+1:]
		width := 0
		if k := strings.IndexByte(field, ';'); k >= 0 {
			width, _ = strconv.Atoi(field[k+1:])
			field = field[:k]
		}
		var v string
		switch field {
		case "binary:Package":
			v = in.InfoName()
			if !strings.Contains(v, ":") && false {
				v += ":" + in.Arch
			}
		case "db:Status-Abbrev":
			v = statusAbbrev(in.Status)
		case "db:Status-Want":
			v = strings.Fields(in.Status + " x x")[0]
		case "db:Status-Status":
			v = strings.Fields(in.Status + " x x x")[2]
		case "Status":
			v = in.Status
		case "source:Package":
			v = strings.Fields(in.Field("Source") + " " + in.Name)[0]
		case "binary:Summary":
			v = strings.SplitN(in.Field("Description"), "\n", 2)[0]
		default:
			v = in.Field(field)
		}
		if width > 0 {
			v = fmt.Sprintf("%-*s", width, v)
		} else if width < 0 {
			v = fmt.Sprintf("%*s", -width, v)
		}
		b.WriteString(v)
	}
	return b.String()
}

func mainDpkgTrigger(args []string) int {
	var names []string
	for _, a := range args {
		if !strings.HasPrefix(a, "-") {
			names = append(names, a)
		}
	}
	if tf := os.Getenv("KPKG_TRIGGER_FILE"); tf != "" && len(names) > 0 {
		f, err := os.OpenFile(tf, os.O_APPEND|os.O_WRONLY, 0)
		if err == nil {
			fmt.Fprintln(f, strings.Join(names, " "))
			f.Close()
		}
	}
	return 0
}

func mainMaintscriptHelper(args []string) int {
	if len(args) >= 2 && args[0] == "supports" {
		return 0
	}
	// rm_conffile / mv_conffile / symlink_to_dir / dir_to_symlink:
	// best-effort no-ops; kpkg keeps conffiles and handles dir/symlink swaps.
	return 0
}

// ------------------------------------------------------------- dpkg-deb

func mainDpkgDeb(args []string) int {
	setupPaths()
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "dpkg-deb: need an action option")
		return 2
	}
	cmd, rest := args[0], args[1:]
	fail := func(err error) int { fmt.Fprintln(os.Stderr, "dpkg-deb: error:", err); return 2 }
	switch cmd {
	case "-x", "--extract", "-X", "--vextract":
		if len(rest) < 2 {
			return fail(errors.New("--extract needs .deb and directory"))
		}
		saved := cfg.Root
		cfg.Root, _ = filepath.Abs(rest[1])
		os.MkdirAll(cfg.Root, 0755)
		res, err := ExtractData(rest[0], nil, nil, nil, nil)
		cfg.Root = saved
		if err != nil {
			return fail(err)
		}
		if cmd == "-X" || cmd == "--vextract" {
			for _, f := range res.Files {
				fmt.Println("." + f)
			}
		}
	case "-c", "--contents":
		f, err := os.Open(rest[0])
		if err != nil {
			return fail(err)
		}
		defer f.Close()
		arIter(f, func(name string, size int64, r io.Reader) (bool, error) {
			if !strings.HasPrefix(name, "data.tar") {
				return false, nil
			}
			dr, err := decompressor(name, r)
			if err != nil {
				return true, err
			}
			tr := tar.NewReader(dr)
			for {
				h, err := tr.Next()
				if err != nil {
					break
				}
				fmt.Printf("%s %s/%s %9d %s %s", fs.FileMode(h.Mode).String(), h.Uname, h.Gname, h.Size, h.ModTime.Format("2006-01-02 15:04"), h.Name)
				if h.Linkname != "" {
					fmt.Printf(" -> %s", h.Linkname)
				}
				fmt.Println()
			}
			return true, nil
		})
	case "-I", "--info", "-f", "--field":
		dc, err := ReadDebControl(rest[0])
		if err != nil {
			return fail(err)
		}
		if cmd == "-f" || cmd == "--field" {
			if len(rest) == 1 {
				dc.Para.Write822(os.Stdout)
			}
			for _, k := range rest[1:] {
				if len(rest) > 2 {
					fmt.Printf("%s: %s\n", k, dc.Para.Get(k))
				} else {
					fmt.Println(dc.Para.Get(k))
				}
			}
			return 0
		}
		for _, n := range sortedKeys(dc.Files) {
			fmt.Printf(" %7d bytes, %4d lines      %s\n", len(dc.Files[n]), bytes.Count(dc.Files[n], []byte("\n")), n)
		}
		dc.Para.Write822(os.Stdout)
	case "-e", "--control":
		dc, err := ReadDebControl(rest[0])
		if err != nil {
			return fail(err)
		}
		dir := "DEBIAN"
		if len(rest) > 1 {
			dir = rest[1]
		}
		os.MkdirAll(dir, 0755)
		for n, b := range dc.Files {
			os.WriteFile(filepath.Join(dir, n), b, 0755)
		}
	case "-b", "--build", "--root-owner-group":
		var src, out string
		for _, a := range rest {
			if strings.HasPrefix(a, "-") {
				continue
			}
			if src == "" {
				src = a
			} else {
				out = a
			}
		}
		if err := buildDeb(src, out); err != nil {
			return fail(err)
		}
	default:
		return fail(fmt.Errorf("unknown action %s", cmd))
	}
	return 0
}

// buildDeb creates a .deb (gzip members, root:root ownership) from a tree
// containing DEBIAN/control.
func buildDeb(src, out string) error {
	ctlData, err := os.ReadFile(filepath.Join(src, "DEBIAN/control"))
	if err != nil {
		return err
	}
	var para *Paragraph
	ParseParagraphs(bytes.NewReader(ctlData), nil, func(p *Paragraph) error { para = p; return io.EOF })
	if para == nil || para.Get("Package") == "" || para.Get("Version") == "" {
		return errors.New("DEBIAN/control lacks Package/Version")
	}
	if out == "" || strings.HasSuffix(out, "/") {
		out = filepath.Join(out, fmt.Sprintf("%s_%s_%s.deb", para.Get("Package"), para.Get("Version"), para.Get("Architecture")))
	}
	mktar := func(root string, skip string) ([]byte, error) {
		var buf bytes.Buffer
		zw := gzip.NewWriter(&buf)
		tw := tar.NewWriter(zw)
		err := filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			rel, _ := filepath.Rel(root, p)
			rel = filepath.ToSlash(rel)
			if skip != "" && (rel == skip || strings.HasPrefix(rel, skip+"/")) {
				if d.IsDir() {
					return filepath.SkipDir
				}
				return nil
			}
			fi, err := os.Lstat(p)
			if err != nil {
				return err
			}
			link := ""
			if fi.Mode()&os.ModeSymlink != 0 {
				link, _ = os.Readlink(p)
			}
			h, err := tar.FileInfoHeader(fi, link)
			if err != nil {
				return err
			}
			h.Name = "./" + rel
			if rel == "." {
				h.Name = "./"
			} else if fi.IsDir() {
				h.Name += "/"
			}
			h.Uid, h.Gid, h.Uname, h.Gname = 0, 0, "root", "root"
			h.ModTime = time.Unix(fi.ModTime().Unix(), 0)
			h.Format = tar.FormatGNU
			if err := tw.WriteHeader(h); err != nil {
				return err
			}
			if fi.Mode().IsRegular() {
				f, err := os.Open(p)
				if err != nil {
					return err
				}
				io.Copy(tw, f)
				f.Close()
			}
			return nil
		})
		tw.Close()
		zw.Close()
		return buf.Bytes(), err
	}
	ctlTar, err := mktar(filepath.Join(src, "DEBIAN"), "")
	if err != nil {
		return err
	}
	dataTar, err := mktar(src, "DEBIAN")
	if err != nil {
		return err
	}
	f, err := os.Create(out)
	if err != nil {
		return err
	}
	defer f.Close()
	io.WriteString(f, "!<arch>\n")
	now := time.Now().Unix()
	member := func(name string, data []byte) {
		fmt.Fprintf(f, "%-16s%-12d%-6d%-6d%-8s%-10d`\n", name, now, 0, 0, "100644", len(data))
		f.Write(data)
		if len(data)%2 == 1 {
			f.Write([]byte{'\n'})
		}
	}
	member("debian-binary", []byte("2.0\n"))
	member("control.tar.gz", ctlTar)
	member("data.tar.gz", dataTar)
	fmt.Printf("dpkg-deb: building package '%s' in '%s'.\n", para.Get("Package"), out)
	_ = path.Join
	return nil
}
