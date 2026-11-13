package main

import (
	"fmt"
	"os"
	"sort"
	"strings"
)

type ResolveOpts struct {
	Recommends bool
	Upgrade    bool // allow upgrading installed packages to satisfy deps
	NoRemove   bool
}

type Plan struct {
	db       *DB
	opts     ResolveOpts
	Install  map[string]*Pkg       // name -> version to install/upgrade
	Remove   map[string]*Installed // infoName -> installed pkg
	NewAuto  map[string]bool
	Manual   map[string]bool
	instProv map[string][]provider
	queue    []*Pkg
	extra    map[string][]string // implicit ordering edges
}

func (db *DB) NewPlan(opts ResolveOpts) *Plan {
	pl := &Plan{db: db, opts: opts, Install: map[string]*Pkg{}, Remove: map[string]*Installed{},
		NewAuto: map[string]bool{}, Manual: map[string]bool{}, instProv: map[string][]provider{}}
	for _, in := range db.Installed {
		if in.State() == "not-installed" {
			continue
		}
		for _, pv := range in.Provides() {
			pl.instProv[pv.Name] = append(pl.instProv[pv.Name], provider{in.Pkg, pv.Ver})
		}
	}
	return pl
}

func (pl *Plan) effective(key string) (*Pkg, bool) {
	if p, ok := pl.Install[key]; ok {
		return p, true
	}
	in := pl.db.lookupInstalled(key)
	if in == nil || in.Key() != key || pl.Remove[in.InfoName()] != nil {
		return nil, false
	}
	if st := in.State(); st != "installed" && st != "unpacked" && st != "half-configured" && st != "triggers-pending" && st != "triggers-awaited" {
		return nil, false
	}
	return in.Pkg, true
}

func (pl *Plan) satisfied(d Dep, from string) bool {
	if !depArchOK(d) {
		return false
	}
	for _, k := range nameKeys(d.Name) {
		if p, ok := pl.effective(k); ok && archFits(d.Arch, from, p) && VersionSatisfies(p.Version, d.Op, d.Ver) {
			return true
		}
	}
	check := func(pr provider) bool {
		if d.Op != "" && (pr.ver == "" || !VersionSatisfies(pr.ver, d.Op, d.Ver)) {
			return false
		}
		if !archFits(d.Arch, from, pr.pkg) {
			return false
		}
		eff, ok := pl.effective(pr.pkg.Key())
		return ok && eff == pr.pkg || ok && eff.Version == pr.pkg.Version
	}
	for _, pr := range pl.instProv[d.Name] {
		if check(pr) {
			return true
		}
	}
	for _, p := range pl.Install {
		if !archFits(d.Arch, from, p) {
			continue
		}
		for _, pv := range p.Provides() {
			if pv.Name == d.Name && (d.Op == "" || (pv.Ver != "" && VersionSatisfies(pv.Ver, d.Op, d.Ver))) {
				return true
			}
		}
	}
	return false
}

func (pl *Plan) groupSatisfied(g []Dep, from string) bool {
	for _, d := range g {
		if pl.satisfied(d, from) {
			return true
		}
	}
	return false
}

var prioRank = map[string]int{"required": 0, "important": 1, "standard": 2, "optional": 3, "extra": 4}

// choose picks a package version to satisfy one alternative.
func (pl *Plan) choose(d Dep, from string) *Pkg {
	if !depArchOK(d) {
		return nil
	}
	var direct *Pkg
	best := 1 << 30
	for _, k := range nameKeys(d.Name) {
		for _, c := range pl.db.Avail[k] {
			if !archFits(d.Arch, from, c) || !VersionSatisfies(c.Version, d.Op, d.Ver) {
				continue
			}
			if r := archRank(c, from); r < best {
				direct, best = c, r
			}
			break
		}
	}
	if direct != nil {
		return direct
	}
	var cands []*Pkg
	for _, pr := range pl.db.provAvail[d.Name] {
		if d.Op != "" && (pr.ver == "" || !VersionSatisfies(pr.ver, d.Op, d.Ver)) {
			continue
		}
		if !archFits(d.Arch, from, pr.pkg) {
			continue
		}
		// only the newest version of each provider
		if top := pl.db.Candidate(pr.pkg.Key()); top != pr.pkg {
			continue
		}
		cands = append(cands, pr.pkg)
	}
	if len(cands) == 0 {
		return nil
	}
	sort.SliceStable(cands, func(i, j int) bool {
		bi, bj := pl.disfavored(cands[i]), pl.disfavored(cands[j])
		if bi != bj {
			return !bi
		}
		ai, aj := archRank(cands[i], from), archRank(cands[j], from)
		if ai != aj {
			return ai < aj
		}
		ri, rj := prioRank[cands[i].Field("Priority")], prioRank[cands[j].Field("Priority")]
		if ri != rj {
			return ri < rj
		}
		return cands[i].Name < cands[j].Name
	})
	return cands[0]
}

// Add schedules p for installation (manual=true for user requests).
func (pl *Plan) Add(p *Pkg, manual bool) {
	key := p.Key()
	if cur, ok := pl.Install[key]; ok && cur.Version == p.Version {
		if manual {
			pl.Manual[key] = true
		}
		return
	}
	pl.Install[key] = p
	if manual {
		pl.Manual[key] = true
	} else if pl.db.installedByKey(key) == nil {
		pl.NewAuto[key] = true
	}
	pl.queue = append(pl.queue, p)
}

func (pl *Plan) Resolve() error {
	for iter := 0; iter < 50; iter++ {
		for len(pl.queue) > 0 {
			p := pl.queue[0]
			pl.queue = pl.queue[1:]
			if pl.Install[p.Key()] != p {
				continue
			}
			from := p.selfArch()
			fields := []string{"Pre-Depends", "Depends"}
			fields = append(fields, "Recommends")
			for _, fld := range fields {
				for _, g := range p.Deps(fld) {
					if fld == "Recommends" && !pl.opts.Recommends && !essentialRecommend(g) {
						continue
					}
					if pl.groupSatisfied(g, from) {
						continue
					}
					var pick, fallback *Pkg
					for _, d := range g {
						c := pl.choose(d, from)
						if c == nil {
							continue
						}
						if !pl.disfavored(c) {
							pick = c
							break
						}
						if fallback == nil {
							fallback = c
						}
					}
					if pick == nil {
						pick = fallback
					}
					if pick != nil && os.Getenv("KPKG_DEBUG") != "" {
						fmt.Fprintf(os.Stderr, "debug: %s %s -> %s\n", p.Key(), fld, pick.Key())
					}
					if pick == nil {
						if fld == "Recommends" {
							continue
						}
						alts := make([]string, len(g))
						for i, d := range g {
							alts[i] = d.String()
						}
						return fmt.Errorf("unmet dependencies: %s %s: %s %s but it is not installable",
							p.Key(), p.Version, fld, strings.Join(alts, " | "))
					}
					pl.Add(pick, false)
				}
			}
		}
		changed, err := pl.checkConflicts()
		if err != nil {
			return err
		}
		if pl.addImplicit() {
			changed = true
		}
		sc, err := pl.syncSameVersions()
		if err != nil {
			return err
		}
		if sc {
			changed = true
		}
		if !changed {
			return nil
		}
	}
	return fmt.Errorf("dependency resolution did not converge")
}

func confArchOK(q string, t *Pkg) bool {
	switch q {
	case "", "any":
		return true
	case "native":
		return t.Arch == cfg.Arch || t.Arch == "all"
	}
	return t.Arch == q || t.Arch == "all"
}

func (pl *Plan) matchTargets(d Dep, self *Pkg) []*Pkg {
	var out []*Pkg
	for _, k := range nameKeys(d.Name) {
		if p, ok := pl.effective(k); ok && p.Name != self.Name && confArchOK(d.Arch, p) && VersionSatisfies(p.Version, d.Op, d.Ver) {
			out = append(out, p)
		}
	}
	add := func(pk *Pkg, ver string) {
		if pk.Name == self.Name || !confArchOK(d.Arch, pk) {
			return
		}
		if d.Op != "" && (ver == "" || !VersionSatisfies(ver, d.Op, d.Ver)) {
			return
		}
		if eff, ok := pl.effective(pk.Key()); ok && eff.Version == pk.Version {
			out = append(out, eff)
		}
	}
	for _, pr := range pl.instProv[d.Name] {
		add(pr.pkg, pr.ver)
	}
	for _, p := range pl.Install {
		for _, pv := range p.Provides() {
			if pv.Name == d.Name {
				add(p, pv.Ver)
			}
		}
	}
	return out
}

func (pl *Plan) replaces(p, t *Pkg) bool {
	for _, g := range p.Deps("Replaces") {
		for _, d := range g {
			if d.Name == t.Name && VersionSatisfies(t.Version, d.Op, d.Ver) {
				return true
			}
			for _, pv := range t.Provides() {
				if pv.Name == d.Name {
					return true
				}
			}
		}
	}
	return false
}

func (pl *Plan) checkConflicts() (bool, error) {
	changed := false
	handle := func(p, t *Pkg, kind string) error {
		if t.Field("X-Kwick-Base") == "yes" {
			return nil // virtual base provides are never removed
		}
		_, planned := pl.Install[t.Key()]
		if kind == "Breaks" || !planned {
			// try upgrading the victim to a version that is not affected
			if c := pl.db.Candidate(t.Key()); c != nil && c.Version != t.Version && !planned {
				ok := true
				for _, g := range p.Deps(kind) {
					for _, d := range g {
						if d.Name == c.Name && VersionSatisfies(c.Version, d.Op, d.Ver) {
							ok = false
						}
					}
				}
				if ok {
					pl.Add(c, false)
					changed = true
					return nil
				}
			}
		}
		if planned {
			return fmt.Errorf("%s %s %s %s %s; cannot install both", p.Key(), p.Version, strings.ToLower(kind), t.Key(), t.Version)
		}
		in := pl.db.lookupInstalled(t.Key())
		if in == nil {
			return nil
		}
		if in.Essential() {
			return fmt.Errorf("%s conflicts with essential package %s", p.Key(), t.Key())
		}
		if pl.opts.NoRemove {
			return fmt.Errorf("%s needs %s to be removed (use full-upgrade)", p.Key(), t.Key())
		}
		if pl.Remove[in.InfoName()] == nil {
			pl.Remove[in.InfoName()] = in
			changed = true
		}
		return nil
	}
	names := sortedKeys(pl.Install)
	for _, n := range names {
		p := pl.Install[n]
		for _, kind := range []string{"Conflicts", "Breaks"} {
			for _, g := range p.Deps(kind) {
				for _, d := range g {
					for _, t := range pl.matchTargets(d, p) {
						if err := handle(p, t, kind); err != nil {
							return false, err
						}
					}
				}
			}
		}
	}
	// installed packages that conflict with / break planned versions
	for _, k := range sortedKeys(pl.db.Installed) {
		in := pl.db.Installed[k]
		if _, up := pl.Install[in.Key()]; up || pl.Remove[k] != nil {
			continue
		}
		for _, kind := range []string{"Conflicts", "Breaks"} {
			for _, g := range in.Deps(kind) {
				for _, d := range g {
					for _, pk := range nameKeys(d.Name) {
						if p, ok := pl.Install[pk]; ok && p.Name != in.Name && confArchOK(d.Arch, p) && VersionSatisfies(p.Version, d.Op, d.Ver) {
							if err := handle(p, in.Pkg, kind); err != nil {
								return false, err
							}
						}
					}
				}
			}
		}
	}
	// removing a package may break reverse dependencies
	if len(pl.Remove) > 0 {
		if pl.closeRemovals() {
			changed = true
		}
	}
	return changed, nil
}

// closeRemovals adds installed packages whose dependencies would become
// unsatisfied. Returns true if the set grew.
func (pl *Plan) closeRemovals() bool {
	grew := false
	for {
		added := false
		for _, k := range sortedKeys(pl.db.Installed) {
			in := pl.db.Installed[k]
			if pl.Remove[k] != nil || in.Field("X-Kwick-Base") == "yes" {
				continue
			}
			if _, up := pl.Install[in.Key()]; up {
				continue
			}
			from := in.selfArch()
			for _, fld := range []string{"Pre-Depends", "Depends"} {
				for _, g := range in.Deps(fld) {
					if !pl.groupSatisfied(g, from) {
						// try to satisfy by installing something new instead
						var pick *Pkg
						if pl.db.provAvail != nil {
							for _, d := range g {
								if pick = pl.choose(d, from); pick != nil && pl.Remove[pick.InfoName()] == nil && pl.removingKey(pick.Key()) == false {
									break
								}
								pick = nil
							}
						}
						if pick != nil && !pl.removingKey(pick.Key()) {
							pl.Add(pick, false)
						} else {
							pl.Remove[k] = in
						}
						added, grew = true, true
						break
					}
				}
				if pl.Remove[k] != nil {
					break
				}
			}
		}
		if !added {
			return grew
		}
	}
}

func (pl *Plan) removingKey(key string) bool {
	for _, in := range pl.Remove {
		if in.Key() == key {
			return true
		}
	}
	return false
}

// Order returns planned packages so that dependencies come first. Packages
// in a dependency cycle are returned together as one group.
func (pl *Plan) Order() [][]*Pkg {
	names := sortedKeys(pl.Install)
	idx := map[string]int{}
	for i, n := range names {
		idx[n] = i
	}
	provIdx := map[string][]int{}
	for i, n := range names {
		for _, pv := range pl.Install[n].Provides() {
			provIdx[pv.Name] = append(provIdx[pv.Name], i)
		}
	}
	edges := make([][]int, len(names))
	for i, n := range names {
		p := pl.Install[n]
		from := p.selfArch()
		for _, x := range pl.extra[n] {
			if j, ok := idx[x]; ok && j != i {
				edges[i] = append(edges[i], j)
			}
		}
		for _, fld := range []string{"Pre-Depends", "Depends"} {
			for _, g := range p.Deps(fld) {
				for _, d := range g {
					for _, k := range nameKeys(d.Name) {
						if j, ok := idx[k]; ok && j != i && archFits(d.Arch, from, pl.Install[k]) {
							edges[i] = append(edges[i], j)
						}
					}
					for _, j := range provIdx[d.Name] {
						if j != i && archFits(d.Arch, from, pl.Install[names[j]]) {
							edges[i] = append(edges[i], j)
						}
					}
				}
			}
		}
	}
	// Tarjan SCC; SCCs are emitted in reverse topological order = deps first.
	index, low := make([]int, len(names)), make([]int, len(names))
	on := make([]bool, len(names))
	for i := range index {
		index[i] = -1
	}
	var stack []int
	var out [][]*Pkg
	counter := 0
	var strong func(v int)
	strong = func(v int) {
		index[v], low[v] = counter, counter
		counter++
		stack = append(stack, v)
		on[v] = true
		for _, w := range edges[v] {
			if index[w] < 0 {
				strong(w)
				low[v] = min(low[v], low[w])
			} else if on[w] {
				low[v] = min(low[v], index[w])
			}
		}
		if low[v] == index[v] {
			var comp []*Pkg
			for {
				w := stack[len(stack)-1]
				stack = stack[:len(stack)-1]
				on[w] = false
				comp = append(comp, pl.Install[names[w]])
				if w == v {
					break
				}
			}
			out = append(out, comp)
		}
	}
	for i := range names {
		if index[i] < 0 {
			strong(i)
		}
	}
	return out
}

// RemovalPlan computes packages to remove when removing names.
func (db *DB) RemovalPlan(names []string) (*Plan, error) {
	pl := db.NewPlan(ResolveOpts{})
	for _, n := range names {
		in := db.lookupInstalled(n)
		if in == nil {
			fmt.Printf("Package '%s' is not installed, so not removed\n", n)
			continue
		}
		if in.Field("X-Kwick-Base") == "yes" || in.Essential() {
			return nil, fmt.Errorf("refusing to remove essential package %s", n)
		}
		pl.Remove[in.InfoName()] = in
	}
	saved := db.provAvail
	db.provAvail = nil // removals never pull in replacements
	pl.closeRemovals()
	db.provAvail = saved
	for k, in := range pl.Remove {
		if in.Essential() || in.Field("X-Kwick-Base") == "yes" {
			return nil, fmt.Errorf("removing %s would remove essential package %s", strings.Join(names, " "), k)
		}
	}
	return pl, nil
}

// Autoremovable lists auto-installed packages nothing manual depends on.
func (db *DB) Autoremovable() []*Installed {
	keep := map[string]bool{}
	var walk func(p *Pkg)
	pl := db.NewPlan(ResolveOpts{})
	walk = func(p *Pkg) {
		if keep[p.Key()] {
			return
		}
		keep[p.Key()] = true
		from := p.selfArch()
		for _, fld := range []string{"Pre-Depends", "Depends", "Recommends"} {
			for _, g := range p.Deps(fld) {
				for _, d := range g {
					for _, k := range nameKeys(d.Name) {
						if in := db.lookupInstalled(k); in != nil && in.Key() == k && archFits(d.Arch, from, in.Pkg) {
							walk(in.Pkg)
						}
					}
					for _, pr := range pl.instProv[d.Name] {
						if archFits(d.Arch, from, pr.pkg) {
							walk(pr.pkg)
						}
					}
				}
			}
		}
	}
	for _, in := range db.Installed {
		if !db.Auto[in.Key()] || in.Essential() || in.Field("X-Kwick-Base") == "yes" {
			walk(in.Pkg)
		}
	}
	var out []*Installed
	for _, k := range sortedKeys(db.Installed) {
		if in := db.Installed[k]; !keep[in.Key()] {
			out = append(out, in)
		}
	}
	return out
}
