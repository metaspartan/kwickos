package main

import "strings"

// Debian version comparison, a faithful port of dpkg's verrevcmp.

type Version struct {
	Epoch              int
	Upstream, Revision string
}

func ParseVersion(s string) Version {
	s = strings.TrimSpace(s)
	v := Version{}
	if i := strings.IndexByte(s, ':'); i >= 0 {
		for _, c := range s[:i] {
			if c >= '0' && c <= '9' {
				v.Epoch = v.Epoch*10 + int(c-'0')
			}
		}
		s = s[i+1:]
	}
	if i := strings.LastIndexByte(s, '-'); i >= 0 {
		v.Upstream, v.Revision = s[:i], s[i+1:]
	} else {
		v.Upstream = s
	}
	return v
}

func isDigit(c byte) bool { return c >= '0' && c <= '9' }
func isAlpha(c byte) bool { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') }

func order(s string, i int) int {
	if i >= len(s) {
		return 0
	}
	c := s[i]
	switch {
	case isDigit(c):
		return 0
	case isAlpha(c):
		return int(c)
	case c == '~':
		return -1
	default:
		return int(c) + 256
	}
}

func verrevcmp(a, b string) int {
	i, j := 0, 0
	for i < len(a) || j < len(b) {
		firstDiff := 0
		for (i < len(a) && !isDigit(a[i])) || (j < len(b) && !isDigit(b[j])) {
			ac, bc := order(a, i), order(b, j)
			if ac != bc {
				return ac - bc
			}
			i++
			j++
		}
		for i < len(a) && a[i] == '0' {
			i++
		}
		for j < len(b) && b[j] == '0' {
			j++
		}
		for i < len(a) && isDigit(a[i]) && j < len(b) && isDigit(b[j]) {
			if firstDiff == 0 {
				firstDiff = int(a[i]) - int(b[j])
			}
			i++
			j++
		}
		if i < len(a) && isDigit(a[i]) {
			return 1
		}
		if j < len(b) && isDigit(b[j]) {
			return -1
		}
		if firstDiff != 0 {
			return firstDiff
		}
	}
	return 0
}

func CompareVersions(a, b string) int {
	va, vb := ParseVersion(a), ParseVersion(b)
	if va.Epoch != vb.Epoch {
		if va.Epoch > vb.Epoch {
			return 1
		}
		return -1
	}
	if r := verrevcmp(va.Upstream, vb.Upstream); r != 0 {
		return sign(r)
	}
	return sign(verrevcmp(va.Revision, vb.Revision))
}

func sign(r int) int {
	switch {
	case r > 0:
		return 1
	case r < 0:
		return -1
	}
	return 0
}

// VersionSatisfies reports whether version v satisfies "op want".
func VersionSatisfies(v, op, want string) bool {
	if op == "" {
		return true
	}
	c := CompareVersions(v, want)
	switch op {
	case "<<":
		return c < 0
	case "<=", "<":
		return c <= 0
	case "=":
		return c == 0
	case ">=", ">":
		return c >= 0
	case ">>":
		return c > 0
	}
	return false
}
