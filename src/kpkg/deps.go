package main

import "strings"

// Dep is one alternative of a dependency relation.
type Dep struct {
	Name, Arch, Op, Ver string
}

func (d Dep) String() string {
	s := d.Name
	if d.Arch != "" {
		s += ":" + d.Arch
	}
	if d.Op != "" {
		s += " (" + d.Op + " " + d.Ver + ")"
	}
	return s
}

// ParseDeps parses "a (>= 1) | b, c [amd64]" into groups of alternatives,
// dropping alternatives whose architecture restriction excludes arch.
func ParseDeps(s, arch string) [][]Dep {
	var out [][]Dep
	s = strings.ReplaceAll(s, "\n", " ")
	for _, grp := range strings.Split(s, ",") {
		grp = strings.TrimSpace(grp)
		if grp == "" {
			continue
		}
		var alts []Dep
		for _, a := range strings.Split(grp, "|") {
			d, ok := parseOneDep(strings.TrimSpace(a), arch)
			if ok {
				alts = append(alts, d)
			}
		}
		if len(alts) > 0 {
			out = append(out, alts)
		}
	}
	return out
}

func parseOneDep(a, arch string) (Dep, bool) {
	var d Dep
	// strip build profiles <...>
	if i := strings.IndexByte(a, '<'); i >= 0 && (strings.IndexByte(a, '(') < 0 || i < strings.IndexByte(a, '(')) {
		a = strings.TrimSpace(a[:i])
	}
	if i := strings.IndexByte(a, '['); i >= 0 {
		j := strings.IndexByte(a, ']')
		if j > i {
			restr := strings.Fields(a[i+1 : j])
			a = strings.TrimSpace(a[:i] + a[j+1:])
			if !archMatches(restr, arch) {
				return d, false
			}
		}
	}
	if i := strings.IndexByte(a, '('); i >= 0 {
		j := strings.IndexByte(a, ')')
		if j < i {
			j = len(a)
		}
		rel := strings.TrimSpace(a[i+1 : j])
		a = strings.TrimSpace(a[:i])
		k := 0
		for k < len(rel) && strings.IndexByte("<>=", rel[k]) >= 0 {
			k++
		}
		d.Op = rel[:k]
		d.Ver = strings.TrimSpace(rel[k:])
	}
	if i := strings.IndexByte(a, ':'); i >= 0 {
		d.Arch = a[i+1:]
		a = a[:i]
	}
	d.Name = strings.TrimSpace(a)
	return d, d.Name != ""
}

func archMatches(restr []string, arch string) bool {
	neg := false
	for _, r := range restr {
		if strings.HasPrefix(r, "!") {
			neg = true
			if r[1:] == arch || r[1:] == "any" || r[1:] == "linux-any" || r[1:] == "linux-"+arch {
				return false
			}
		} else if r == arch || r == "any" || r == "linux-any" || r == "linux-"+arch {
			return true
		}
	}
	return neg
}

// Provided is one entry of a Provides field.
type Provided struct{ Name, Ver string }

func ParseProvides(s string) []Provided {
	var out []Provided
	for _, g := range ParseDeps(s, "") {
		for _, d := range g {
			out = append(out, Provided{Name: d.Name, Ver: d.Ver})
		}
	}
	return out
}
