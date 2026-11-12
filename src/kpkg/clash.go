package main

// clashes reports whether choosing c would conflict with (or break) a
// package already planned or installed - or vice versa. Used to pick the
// next alternative of an "a | b" dependency, the way apt backtracks
// (e.g. "systemd | systemd-standalone-sysusers" when elogind is requested).
func (pl *Plan) disfavored(c *Pkg) bool {
	return cfg.Avoid[c.Name] || pl.clashes(c)
}

func (pl *Plan) clashes(c *Pkg) bool {
	hits := func(p *Pkg, target *Pkg) bool {
		for _, kind := range []string{"Conflicts", "Breaks"} {
			for _, g := range p.Deps(kind) {
				for _, d := range g {
					if d.Name == target.Name && VersionSatisfies(target.Version, d.Op, d.Ver) {
						return true
					}
					for _, pv := range target.Provides() {
						if pv.Name == d.Name && d.Op == "" && p.Name != target.Name {
							return true
						}
					}
				}
			}
		}
		return false
	}
	for _, p := range pl.Install {
		if p.Name != c.Name && (hits(c, p) || hits(p, c)) {
			return true
		}
	}
	for _, in := range pl.db.Installed {
		if in.Name == c.Name || in.Field("X-Kwick-Base") == "yes" || pl.Remove[in.InfoName()] != nil {
			continue
		}
		if in.State() == "installed" && (hits(c, in.Pkg) || hits(in.Pkg, c)) {
			return true
		}
	}
	return false
}
