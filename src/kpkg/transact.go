package main

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"
)

func lockDB() (func(), error) {
	os.MkdirAll(cfg.Admin, 0755)
	f, err := os.OpenFile(filepath.Join(cfg.Admin, "lock-frontend"), os.O_RDWR|os.O_CREATE, 0640)
	if err != nil {
		return nil, err
	}
	for i := 0; ; i++ {
		if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err == nil {
			break
		}
		if i == 0 {
			fmt.Fprintln(os.Stderr, "Waiting for dpkg frontend lock (another kpkg/apt is running)...")
		}
		if i > 600 {
			return nil, errors.New("could not get lock /var/lib/dpkg/lock-frontend")
		}
		time.Sleep(100 * time.Millisecond)
	}
	return func() { f.Close() }, nil
}

func debCacheName(p *Pkg) string {
	return filepath.Join(cfg.Cache, fmt.Sprintf("%s_%s_%s.deb", p.Name, strings.ReplaceAll(p.Version, ":", "%3a"), p.Arch))
}

// Download fetches .debs in parallel and verifies SHA256 + size.
func Download(pkgs []*Pkg) (map[*Pkg]string, error) {
	os.MkdirAll(filepath.Join(cfg.Cache, "partial"), 0755)
	out := map[*Pkg]string{}
	var mu sync.Mutex
	var firstErr error
	type job struct {
		n int
		p *Pkg
	}
	jobs := make(chan job)
	var wg sync.WaitGroup
	var total int64
	start := time.Now()
	for w := 0; w < 6; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := range jobs {
				p := j.p
				if p.LocalDeb != "" {
					mu.Lock()
					out[p] = p.LocalDeb
					mu.Unlock()
					continue
				}
				dst := debCacheName(p)
				want := p.Field("SHA256")
				if ok, _ := fileSHA256(dst, want); ok {
					mu.Lock()
					out[p] = dst
					mu.Unlock()
					continue
				}
				url := strings.TrimRight(p.Src.URI, "/") + "/" + p.Field("Filename")
				err := fetchTo(url, dst, want, p.Size())
				mu.Lock()
				if err != nil {
					if firstErr == nil {
						firstErr = fmt.Errorf("failed to fetch %s: %v", url, err)
					}
				} else {
					out[p] = dst
					total += p.Size()
					fmt.Printf("Get:%d %s %s/%s %s %s %s [%s]\n", j.n, strings.TrimRight(p.Src.URI, "/"), p.Src.Suite, p.Src.Comp, p.Arch, p.Name, p.Version, human(p.Size()))
				}
				mu.Unlock()
			}
		}()
	}
	for i, p := range pkgs {
		jobs <- job{i + 1, p}
	}
	close(jobs)
	wg.Wait()
	if total > 0 {
		el := time.Since(start).Seconds()
		fmt.Printf("Fetched %s in %.1fs (%s/s)\n", human(total), el, human(int64(float64(total)/max(el, 0.001))))
	}
	return out, firstErr
}

func fileSHA256(p, want string) (bool, error) {
	if want == "" {
		return false, nil
	}
	f, err := os.Open(p)
	if err != nil {
		return false, err
	}
	defer f.Close()
	h := sha256.New()
	io.Copy(h, f)
	return hex.EncodeToString(h.Sum(nil)) == want, nil
}

func fetchTo(url, dst, wantHash string, size int64) error {
	resp, err := httpGet(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	tmp := filepath.Join(filepath.Dir(dst), "partial", filepath.Base(dst))
	f, err := os.Create(tmp)
	if err != nil {
		return err
	}
	h := sha256.New()
	n, err := io.Copy(io.MultiWriter(f, h), resp.Body)
	f.Close()
	if err != nil {
		os.Remove(tmp)
		return err
	}
	if size > 0 && n != size {
		os.Remove(tmp)
		return fmt.Errorf("size mismatch (%d != %d)", n, size)
	}
	if wantHash != "" && hex.EncodeToString(h.Sum(nil)) != wantHash {
		os.Remove(tmp)
		return errors.New("hash sum mismatch")
	}
	return os.Rename(tmp, dst)
}

// ---------------------------------------------------------------- scripts

var triggerFile string

func scriptEnv(name, script string) []string {
	env := os.Environ()
	set := func(k, v string) { env = append(env, k+"="+v) }
	set("DPKG_MAINTSCRIPT_PACKAGE", name)
	set("DPKG_MAINTSCRIPT_NAME", script)
	set("DPKG_MAINTSCRIPT_ARCH", cfg.Arch)
	set("DPKG_RUNNING_VERSION", dpkgCompatVersion)
	set("DPKG_ADMINDIR", "/var/lib/dpkg")
	set("DPKG_ROOT", "")
	if os.Getenv("DEBIAN_FRONTEND") == "" {
		set("DEBIAN_FRONTEND", "noninteractive")
	}
	if os.Getenv("PATH") == "" {
		set("PATH", "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin")
	}
	if triggerFile != "" {
		set("KPKG_TRIGGER_FILE", triggerFile)
	}
	return env
}

// runScript runs a maintainer script; hostPath is its location on the host,
// chrootPath the same file as seen inside cfg.Root.
func runScriptAt(hostPath, chrootPath, pkg, script string, args ...string) error {
	if _, err := os.Stat(hostPath); err != nil {
		return nil
	}
	os.Chmod(hostPath, 0755)
	cmd := exec.Command(chrootPath, args...)
	if cfg.Root != "/" {
		cmd.SysProcAttr = &syscall.SysProcAttr{Chroot: cfg.Root}
		cmd.Dir = "/"
	} else {
		cmd.Dir = "/"
	}
	cmd.Env = scriptEnv(pkg, script)
	tb := &tailBuf{}
	cmd.Stdout, cmd.Stderr = io.MultiWriter(os.Stdout, tb), io.MultiWriter(os.Stderr, tb)
	if fi, _ := os.Stdin.Stat(); fi != nil && fi.Mode()&os.ModeCharDevice != 0 {
		cmd.Stdin = os.Stdin
	}
	if err := cmd.Run(); err != nil {
		return &scriptError{fmt.Sprintf("%s %s subprocess returned error exit status (%v)", pkg, script, err), string(tb.b)}
	}
	return nil
}

// withHealing runs fn; if it fails with a diagnosable compatibility problem
// the missing GNU tool / interpreter is installed and fn is retried.
func (tx *Tx) withHealing(fn func() error) error {
	err := fn()
	for i := 0; err != nil && i < 4; i++ {
		se, ok := err.(*scriptError)
		if !ok {
			return err
		}
		pkg, why := tx.db.diagnose(se.out)
		if pkg == "" || !tx.heal(pkg, why) {
			return err
		}
		err = fn()
	}
	return err
}

func runInfoScript(infoName, script string, args ...string) error {
	rel := path.Join("/var/lib/dpkg/info", infoName+"."+script)
	host := filepath.Join(infoDir(), infoName+"."+script)
	return runScriptAt(host, rel, strings.SplitN(infoName, ":", 2)[0], script, args...)
}

// ------------------------------------------------------------ transaction

type Tx struct {
	db        *DB
	plan      *Plan
	purge     bool
	owners    map[string][]string // path -> infoNames
	lists     map[string][]string // infoName -> files (modified copies)
	activated map[string]bool
	unpacked  []string // all paths unpacked (for file triggers)
	prevVer   map[string]string
	healed    map[string]bool
}

// scriptError carries the (tail of the) output of a failed maintainer script.
type scriptError struct {
	msg, out string
}

func (e *scriptError) Error() string { return e.msg }

// tailBuf keeps the last 32 KiB written to it.
type tailBuf struct{ b []byte }

func (t *tailBuf) Write(p []byte) (int, error) {
	t.b = append(t.b, p...)
	if len(t.b) > 32<<10 {
	        t.b = t.b[len(t.b)-32<<10:]
	}
	return len(p), nil
}

func (tx *Tx) loadOwners() {
	tx.owners = map[string][]string{}
	tx.lists = map[string][]string{}
	for k := range tx.db.Installed {
		fl := readList(k)
		tx.lists[k] = fl
		for _, f := range fl {
			tx.owners[f] = append(tx.owners[f], k)
		}
	}
}

func (tx *Tx) dropOwnership(path, infoName string) {
	fl := tx.lists[infoName]
	for i, f := range fl {
		if f == path {
			tx.lists[infoName] = append(fl[:i:i], fl[i+1:]...)
			break
		}
	}
	os := tx.owners[path]
	for i, o := range os {
		if o == infoName {
			tx.owners[path] = append(os[:i:i], os[i+1:]...)
			break
		}
	}
}

func isDirPath(p string) bool {
	fi, err := os.Stat(filepath.Join(cfg.Root, p))
	return err == nil && fi.IsDir()
}

// Summary prints an apt-style summary; returns false if nothing to do.
func (pl *Plan) Summary() bool {
	var newp, upg, down, rm []string
	var dl, grow int64
	for _, n := range sortedKeys(pl.Install) {
		p := pl.Install[n]
		in := pl.db.lookupInstalled(n)
		if in != nil && in.Version == p.Version && in.State() == "installed" && !cfg.Reinstall {
			delete(pl.Install, n)
			continue
		}
		dl += p.Size()
		grow += p.InstalledSize()
		switch {
		case in == nil:
			newp = append(newp, n)
		case CompareVersions(p.Version, in.Version) >= 0:
			upg = append(upg, n)
			grow -= in.InstalledSize()
		default:
			down = append(down, n)
			grow -= in.InstalledSize()
		}
	}
	for _, k := range sortedKeys(pl.Remove) {
		rm = append(rm, pl.Remove[k].Name)
		grow -= pl.Remove[k].InstalledSize()
	}
	show := func(title string, xs []string) {
		if len(xs) == 0 {
			return
		}
		fmt.Println(title)
		line := " "
		for _, x := range xs {
			if len(line)+len(x) > 78 {
				fmt.Println(line)
				line = " "
			}
			line += " " + x
		}
		fmt.Println(line)
	}
	var extra []string
	for _, n := range newp {
		if !pl.Manual[n] {
			extra = append(extra, n)
		}
	}
	var manual []string
	for _, n := range newp {
		if pl.Manual[n] {
			manual = append(manual, n)
		}
	}
	show("Installing:", manual)
	show("Installing dependencies:", extra)
	show("Upgrading:", upg)
	show("DOWNGRADING:", down)
	show("REMOVING:", rm)
	fmt.Printf("\nSummary:\n  Upgrading: %d, Installing: %d, Removing: %d, Downgrading: %d\n", len(upg), len(newp), len(rm), len(down))
	if len(pl.Install)+len(rm) == 0 {
		return false
	}
	if dl > 0 {
		fmt.Printf("  Download size: %s\n", human(dl))
	}
	if grow >= 0 {
		fmt.Printf("  Space needed: %s\n\n", human(grow))
	} else {
		fmt.Printf("  Freed space: %s\n\n", human(-grow))
	}
	return true
}

func confirm(extraNeeded bool) bool {
	if cfg.Yes || !extraNeeded {
		return true
	}
	fi, _ := os.Stdin.Stat()
	if fi == nil || fi.Mode()&os.ModeCharDevice == 0 {
		return true // non-interactive (scripts, agents): proceed like -y
	}
	fmt.Print("Do you want to continue? [Y/n] ")
	r := bufio.NewReader(os.Stdin)
	l, _ := r.ReadString('\n')
	l = strings.TrimSpace(strings.ToLower(l))
	return l == "" || l == "y" || l == "yes"
}

// Execute performs the plan.
func (pl *Plan) Execute(purge bool) error {
	unlock, err := lockDB()
	if err != nil {
		return err
	}
	defer unlock()
	tx := &Tx{db: pl.db, plan: pl, purge: purge, activated: map[string]bool{}, prevVer: map[string]string{}}
	var dlList []*Pkg
	for _, n := range sortedKeys(pl.Install) {
		dlList = append(dlList, pl.Install[n])
	}
	files, err := Download(dlList)
	if err != nil {
		return err
	}
	// Essential-on-demand: interpreters needed by maintainer scripts.
	for round := 0; round < 3; round++ {
		extra := pl.scriptNeeds(files)
		if len(extra) == 0 {
			break
		}
		for _, n := range extra {
			pl.Add(pl.db.Candidate(n), false)
		}
		if err := pl.Resolve(); err != nil {
			return err
		}
		var more []*Pkg
		for _, n := range sortedKeys(pl.Install) {
			if _, ok := files[pl.Install[n]]; !ok {
				more = append(more, pl.Install[n])
			}
		}
		fmt.Printf("Maintainer scripts need: %s (+%d packages)\n", strings.Join(extra, ", "), len(more))
		f2, err := Download(more)
		if err != nil {
			return err
		}
		for k, v := range f2 {
			files[k] = v
		}
	}
	if cfg.DownloadOnly {
		return nil
	}
	tf, _ := os.CreateTemp("", "kpkg-triggers")
	if tf != nil {
		triggerFile = tf.Name()
		tf.Close()
		defer os.Remove(triggerFile)
	}
	tx.loadOwners()
	// removals first (conflicting packages, explicit removes)
	for _, k := range sortedKeys(pl.Remove) {
		if err := tx.remove(pl.Remove[k]); err != nil {
			return err
		}
	}
	for _, group := range pl.Order() {
		for _, p := range group {
			if err := tx.unpack(p, files[p]); err != nil {
				return err
			}
		}
		sort.SliceStable(group, func(i, j int) bool { return configRank(group[i]) < configRank(group[j]) })
		for _, p := range group {
			if err := tx.configure(p); err != nil {
				return err
			}
		}
	}
	tx.runTriggers()
	for n := range pl.NewAuto {
		if !pl.Manual[n] {
			pl.db.Auto[n] = true
		}
	}
	for n := range pl.Manual {
		delete(pl.db.Auto, n)
	}
	pl.db.SaveAuto()
	if !cfg.KeepDebs {
		for p, f := range files {
			if p.LocalDeb == "" {
				os.Remove(f)
			}
		}
	}
	return pl.db.SaveStatus()
}

func parseConffiles(s string) map[string]string {
	m := map[string]string{}
	for _, l := range strings.Split(s, "\n") {
		f := strings.Fields(l)
		if len(f) >= 2 {
			m[f[0]] = f[1]
		}
	}
	return m
}

func (tx *Tx) unpack(p *Pkg, deb string) error {
	dc, err := ReadDebControl(deb)
	if err != nil {
		return err
	}
	ctl := dc.Para
	old := tx.db.lookupInstalled(p.Name)
	oldVer := ""
	var oldConf map[string]string
	if old != nil {
		oldVer = old.Version
		oldConf = parseConffiles(old.Field("Conffiles"))
		if old.State() == "installed" {
			tx.prevVer[p.Name] = oldVer
		}
	}
	verb := "Unpacking"
	if old != nil {
		fmt.Printf("Preparing to unpack .../%s ...\n", filepath.Base(deb))
		verb = "Unpacking"
	} else {
		fmt.Printf("Selecting previously unselected package %s.\n", p.Name)
	}
	// stage control files for preinst
	stage := filepath.Join(cfg.Admin, "tmp.ci")
	os.RemoveAll(stage)
	os.MkdirAll(stage, 0755)
	for n, b := range dc.Files {
		os.WriteFile(filepath.Join(stage, n), b, 0755)
	}
	infoName := p.Name
	if ctl.Get("Multi-Arch") == "same" {
		infoName = p.Name + ":" + ctl.Get("Architecture")
	}
	if old != nil && old.State() == "installed" {
		if err := runInfoScript(old.InfoName(), "prerm", "upgrade", p.Version); err != nil {
			return err
		}
	}
	if dc.Files["preinst"] != nil {
		args := []string{"install"}
		if old != nil {
			args = []string{"upgrade", oldVer}
		}
		if err := tx.withHealing(func() error {
			return runScriptAt(filepath.Join(stage, "preinst"), "/var/lib/dpkg/tmp.ci/preinst", p.Name, "preinst", args...)
		}); err != nil {
			return err
		}
	}
	if old != nil {
		fmt.Printf("%s %s (%s) over (%s) ...\n", verb, p.Name, p.Version, oldVer)
	} else {
		fmt.Printf("%s %s (%s) ...\n", verb, p.Name, p.Version)
	}
	conf := map[string]bool{}
	for _, l := range strings.Split(string(dc.Files["conffiles"]), "\n") {
		if l = strings.TrimSpace(l); strings.HasPrefix(l, "/") {
			conf[strings.Fields(l)[0]] = true
		}
	}
	replacing := map[string]bool{}
	for k := range tx.plan.Remove {
		replacing[k] = true
	}
	newPkg := &Pkg{P: ctl, Name: p.Name, Version: p.Version, Arch: ctl.Get("Architecture")}
	canOverwrite := func(fp string) bool {
		for _, o := range append([]string(nil), tx.owners[fp]...) {
			if o == infoName || o == old.infoNameOr("") || replacing[o] {
				continue
			}
			if isDirPath(fp) {
				continue
			}
			oi := tx.db.Installed[o]
			if oi != nil && (oi.Field("X-Kwick-Base") == "yes" || tx.plan.replaces(newPkg, oi.Pkg)) {
				tx.dropOwnership(fp, o)
				continue
			}
			warn("%s: overwriting '%s', which is also in package %s", p.Name, fp, o)
			tx.dropOwnership(fp, o)
		}
		return true
	}
	res, err := ExtractData(deb, conf, oldConf, canOverwrite)
	if err != nil {
		return fmt.Errorf("error processing archive %s: %v", deb, err)
	}
	tx.unpacked = append(tx.unpacked, res.Files...)
	// obsolete files from the old version
	if old != nil {
		newSet := map[string]bool{}
		for _, f := range res.Files {
			newSet[f] = true
		}
		oldFiles := tx.lists[old.InfoName()]
		for i := len(oldFiles) - 1; i >= 0; i-- {
			f := oldFiles[i]
			if newSet[f] || conf[f] || oldConf[f] != "" {
				continue
			}
			if len(tx.owners[f]) > 1 {
				continue
			}
			removePath(f)
		}
		if err := runInfoScript(old.InfoName(), "postrm", "upgrade", p.Version); err != nil {
			warn("%v", err)
		}
		for _, f := range oldFiles {
			tx.dropOwnership(f, old.InfoName())
		}
		// old control files
		if old.InfoName() != infoName {
			removeInfo(old.InfoName())
		}
	}
	// install control files into the dpkg database
	removeInfo(infoName)
	for n, b := range dc.Files {
		if n == "control" {
			continue
		}
		mode := os.FileMode(0644)
		switch n {
		case "preinst", "postinst", "prerm", "postrm", "config":
			mode = 0755
		}
		os.WriteFile(filepath.Join(infoDir(), infoName+"."+n), b, mode)
	}
	writeList(infoName, res.Files)
	tx.lists[infoName] = res.Files
	for _, f := range res.Files {
		tx.owners[f] = append(tx.owners[f], infoName)
	}
	for _, l := range strings.Split(string(dc.Files["triggers"]), "\n") {
		f := strings.Fields(l)
		if len(f) == 2 && strings.HasPrefix(f[0], "activate") {
			tx.activated[f[1]] = true
		}
	}
	// status entry
	st := NewParagraph()
	st.Set("Package", p.Name)
	st.Set("Status", "install ok unpacked")
	for _, k := range ctl.Keys {
		if k == "Package" || k == "Status" {
			continue
		}
		if k == "Description" {
			continue
		}
		st.Set(k, ctl.Get(k))
	}
	if len(res.Conffiles) > 0 {
		var b strings.Builder
		for _, cf := range sortedKeys(res.Conffiles) {
			fmt.Fprintf(&b, "\n %s %s", cf, res.Conffiles[cf])
		}
		st.Set("Conffiles", b.String())
	}
	st.Set("Description", ctl.Get("Description"))
	if old != nil && old.InfoName() != infoName {
		delete(tx.db.Installed, old.InfoName())
	}
	tx.db.Installed[infoName] = &Installed{Pkg: &Pkg{P: st, Name: p.Name, Version: p.Version, Arch: st.Get("Architecture")}, Status: "install ok unpacked"}
	tx.db.SaveStatus()
	return nil
}

func (in *Installed) infoNameOr(d string) string {
	if in == nil {
		return d
	}
	return in.InfoName()
}

func removeInfo(infoName string) {
	m, _ := filepath.Glob(filepath.Join(infoDir(), infoName+".*"))
	for _, f := range m {
		b := filepath.Base(f)
		ext := strings.TrimPrefix(b, infoName+".")
		if !strings.Contains(ext, ".") || ext == "list" {
			if ext != "list" {
				os.Remove(f)
			}
		}
	}
}

func removePath(p string) {
	host, err := resolveInRoot(cfg.Root, p, false)
	if err != nil {
		return
	}
	fi, err := os.Lstat(host)
	if err != nil {
		return
	}
	if fi.IsDir() {
		syscall.Rmdir(host) // only if empty; never follows symlinks
		return
	}
	os.Remove(host)
}

func (tx *Tx) configure(p *Pkg) error {
	in := tx.db.lookupInstalled(p.Name)
	if in == nil {
		return nil
	}
	prev := tx.prevVer[p.Name]
	fmt.Printf("Setting up %s (%s) ...\n", p.Name, p.Version)
	in.Status = "install ok half-configured"
	in.P.Set("Status", in.Status)
	if err := tx.withHealing(func() error { return runInfoScript(in.InfoName(), "postinst", "configure", prev) }); err != nil {
		tx.db.SaveStatus()
		return err
	}
	in.Status = "install ok installed"
	in.P.Set("Status", in.Status)
	tx.db.SaveStatus()
	return nil
}

func (tx *Tx) remove(in *Installed) error {
	name := in.InfoName()
	fmt.Printf("Removing %s (%s) ...\n", in.Name, in.Version)
	if err := runInfoScript(name, "prerm", "remove"); err != nil {
		return err
	}
	conf := parseConffiles(in.Field("Conffiles"))
	files := tx.lists[name]
	if files == nil {
		files = readList(name)
	}
	sort.Sort(sort.Reverse(sort.StringSlice(files)))
	for _, f := range files {
		if conf[f] != "" && !tx.purge {
			continue
		}
		if len(tx.owners[f]) > 1 {
			tx.dropOwnership(f, name)
			continue
		}
		removePath(f)
		tx.dropOwnership(f, name)
	}
	if err := runInfoScript(name, "postrm", "remove"); err != nil {
		warn("%v", err)
	}
	if tx.purge {
		fmt.Printf("Purging configuration files for %s (%s) ...\n", in.Name, in.Version)
		runInfoScript(name, "postrm", "purge")
	}
	m, _ := filepath.Glob(filepath.Join(infoDir(), name+".*"))
	keepConf := len(conf) > 0 && !tx.purge
	for _, f := range m {
		if keepConf && (strings.HasSuffix(f, ".postrm") || strings.HasSuffix(f, ".list")) {
			continue
		}
		os.Remove(f)
	}
	if keepConf {
		in.Status = "deinstall ok config-files"
		in.P.Set("Status", in.Status)
		var kept []string
		for f := range conf {
			kept = append(kept, f)
		}
		writeList(name, kept)
	} else {
		delete(tx.db.Installed, name)
	}
	delete(tx.db.Auto, in.Name)
	tx.db.SaveStatus()
	restoreBusyboxLinks()
	return nil
}

// restoreBusyboxLinks re-creates applet links a removed package had
// replaced (e.g. after `apt remove coreutils`).
func restoreBusyboxLinks() {
	data, err := os.ReadFile(filepath.Join(cfg.Root, "usr/share/kwick/busybox.links"))
	if err != nil {
		return
	}
	for _, l := range strings.Split(string(data), "\n") {
		l = strings.TrimSpace(l)
		if l == "" {
			continue
		}
		host, err := resolveInRoot(cfg.Root, l, false)
		if err != nil {
			continue
		}
		if _, err := os.Lstat(host); os.IsNotExist(err) {
			os.Symlink("/bin/busybox", host)
		}
	}
}

func (tx *Tx) runTriggers() {
	if b, err := os.ReadFile(triggerFile); err == nil {
		for _, t := range strings.Fields(string(b)) {
			tx.activated[t] = true
		}
	}
	interests := map[string][]string{} // pkg -> triggers
	m, _ := filepath.Glob(filepath.Join(infoDir(), "*.triggers"))
	for _, f := range m {
		pkg := strings.TrimSuffix(filepath.Base(f), ".triggers")
		data, _ := os.ReadFile(f)
		for _, l := range strings.Split(string(data), "\n") {
			fs := strings.Fields(l)
			if len(fs) != 2 || !strings.HasPrefix(fs[0], "interest") {
				continue
			}
			t := fs[1]
			hit := tx.activated[t]
			if !hit && strings.HasPrefix(t, "/") {
				for _, u := range tx.unpacked {
					if u == t || strings.HasPrefix(u, t+"/") {
						hit = true
						break
					}
				}
			}
			if hit {
				interests[pkg] = append(interests[pkg], t)
			}
		}
	}
	for _, pkg := range sortedKeys(interests) {
		if in := tx.db.Installed[pkg]; in == nil || in.State() != "installed" {
			continue
		}
		fmt.Printf("Processing triggers for %s ...\n", pkg)
		if err := runInfoScript(pkg, "postinst", "triggered", strings.Join(interests[pkg], " ")); err != nil {
			warn("%v", err)
		}
	}
}
