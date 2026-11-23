package main

import (
	"archive/tar"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type filterRule struct {
	include bool
	pat     string
}

type pathFilter struct {
	rules []filterRule
}

func dpkgOption(opt string) bool {
	opt = strings.TrimPrefix(opt, "--")
	name, val, _ := strings.Cut(opt, "=")
	switch name {
	case "force-overwrite":
		cfg.ForceOverwrite = true
	case "path-exclude", "path-include":
		if val == "" {
			return false
		}
		cfg.PathFilters = append(cfg.PathFilters, filterRule{include: name == "path-include", pat: val})
	default:
		return false
	}
	return true
}

func validConfigName(n string) bool {
	if n == "" || n[0] == '.' {
		return false
	}
	for i := 0; i < len(n); i++ {
		c := n[i]
		if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '_' || c == '-') {
			return false
		}
	}
	return true
}

func dpkgConfigFiles(root string) []string {
	dir := filepath.Join(root, "etc/dpkg/dpkg.cfg.d")
	ents, _ := os.ReadDir(dir)
	var names []string
	for _, e := range ents {
		if validConfigName(e.Name()) {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)
	var out []string
	for _, n := range names {
		out = append(out, filepath.Join(dir, n))
	}
	return append(out, filepath.Join(root, "etc/dpkg/dpkg.cfg"))
}

func parseDpkgConfigFilters(data string) []filterRule {
	var out []filterRule
	for _, l := range strings.Split(data, "\n") {
		l = strings.TrimSpace(l)
		if l == "" || l[0] == '#' {
			continue
		}
		i := strings.IndexAny(l, " \t=")
		name, val := l, ""
		if i >= 0 {
			name = l[:i]
			val = strings.TrimLeft(l[i:], " \t")
			if l[i] == '=' {
				val = strings.TrimLeft(l[i+1:], " \t")
			} else if strings.HasPrefix(val, "=") {
				val = strings.TrimLeft(val[1:], " \t")
			}
		}
		if len(val) >= 2 && (val[0] == '"' || val[0] == '\'') && val[len(val)-1] == val[0] {
			val = val[1 : len(val)-1]
		}
		name = strings.TrimPrefix(name, "--")
		if (name == "path-exclude" || name == "path-include") && val != "" {
			out = append(out, filterRule{include: name == "path-include", pat: val})
		}
	}
	return out
}

func loadPathFilters(root string) *pathFilter {
	var rules []filterRule
	for _, f := range dpkgConfigFiles(root) {
		data, err := os.ReadFile(f)
		if err != nil {
			continue
		}
		rules = append(rules, parseDpkgConfigFilters(string(data))...)
	}
	rules = append(rules, cfg.PathFilters...)
	if len(rules) == 0 {
		return nil
	}
	return &pathFilter{rules: rules}
}

func (tx *Tx) filters() *pathFilter {
	if !tx.filtDone {
		tx.filt = loadPathFilters(cfg.Root)
		tx.filtDone = true
	}
	return tx.filt
}

func (f *pathFilter) skip(p string, typ byte) bool {
	if f == nil {
		return false
	}
	skip := false
	for _, r := range f.rules {
		if fnmatch(r.pat, p) {
			skip = !r.include
		}
	}
	if skip && (typ == tar.TypeDir || typ == tar.TypeSymlink) {
		for _, r := range f.rules {
			if !r.include {
				continue
			}
			w := strings.IndexAny(r.pat, "*?[\\")
			if w < 0 {
				w = len(r.pat)
			}
			for w > 0 && r.pat[w-1] == '/' {
				w--
			}
			if strings.HasPrefix(p, r.pat[:w]) {
				return false
			}
		}
	}
	return skip
}

func fnmatch(pat, s string) bool {
	px, sx := 0, 0
	star, mark := -1, 0
	for px < len(pat) || sx < len(s) {
		if px < len(pat) {
			switch c := pat[px]; c {
			case '*':
				star, mark = px, sx
				px++
				continue
			case '?':
				if sx < len(s) {
					px++
					sx++
					continue
				}
			case '[':
				if sx < len(s) {
					ok, n, valid := matchBracket(pat[px:], s[sx])
					if !valid {
						if s[sx] == '[' {
							px++
							sx++
							continue
						}
					} else if ok {
						px += n
						sx++
						continue
					}
				}
			case '\\':
				lit := byte('\\')
				adv := 1
				if px+1 < len(pat) {
					lit, adv = pat[px+1], 2
				}
				if sx < len(s) && s[sx] == lit {
					px += adv
					sx++
					continue
				}
			default:
				if sx < len(s) && s[sx] == c {
					px++
					sx++
					continue
				}
			}
		}
		if star >= 0 && mark < len(s) {
			mark++
			px, sx = star+1, mark
			continue
		}
		return false
	}
	return true
}

func matchBracket(p string, ch byte) (bool, int, bool) {
	i := 1
	neg := false
	if i < len(p) && (p[i] == '!' || p[i] == '^') {
		neg = true
		i++
	}
	matched := false
	first := true
	for i < len(p) {
		c := p[i]
		if c == ']' && !first {
			return matched != neg, i + 1, true
		}
		first = false
		if c == '[' && i+1 < len(p) && p[i+1] == ':' {
			if j := strings.Index(p[i+2:], ":]"); j >= 0 {
				if classMatch(p[i+2:i+2+j], ch) {
					matched = true
				}
				i += j + 4
				continue
			}
		}
		if c == '\\' && i+1 < len(p) {
			i++
			c = p[i]
		}
		i++
		if i+1 < len(p) && p[i] == '-' && p[i+1] != ']' {
			hi := p[i+1]
			i += 2
			if hi == '\\' && i < len(p) {
				hi = p[i]
				i++
			}
			if c <= ch && ch <= hi {
				matched = true
			}
			continue
		}
		if ch == c {
			matched = true
		}
	}
	return false, 0, false
}

func classMatch(class string, c byte) bool {
	lower := c >= 'a' && c <= 'z'
	upper := c >= 'A' && c <= 'Z'
	digit := c >= '0' && c <= '9'
	switch class {
	case "alpha":
		return lower || upper
	case "digit":
		return digit
	case "alnum":
		return lower || upper || digit
	case "lower":
		return lower
	case "upper":
		return upper
	case "xdigit":
		return digit || c >= 'a' && c <= 'f' || c >= 'A' && c <= 'F'
	case "space":
		return c == ' ' || c >= '\t' && c <= '\r'
	case "blank":
		return c == ' ' || c == '\t'
	case "cntrl":
		return c < 32 || c == 127
	case "print":
		return c >= 32 && c < 127
	case "graph":
		return c > 32 && c < 127
	case "punct":
		return c > 32 && c < 127 && !lower && !upper && !digit
	}
	return false
}
