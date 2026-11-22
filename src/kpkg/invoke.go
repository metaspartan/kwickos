package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

func readAptConfLists(data string, out map[string][]string) {
	var scope []string
	var toks []string
	i := 0
	for i < len(data) {
		c := data[i]
		switch {
		case c == ' ' || c == '\t' || c == '\n' || c == '\r':
			i++
		case c == '#' && (i == 0 || data[i-1] == '\n'):
			for i < len(data) && data[i] != '\n' {
				i++
			}
		case strings.HasPrefix(data[i:], "//"):
			for i < len(data) && data[i] != '\n' {
				i++
			}
		case strings.HasPrefix(data[i:], "/*"):
			j := strings.Index(data[i+2:], "*/")
			if j < 0 {
				return
			}
			i += j + 4
		case c == '"':
			j := i + 1
			for j < len(data) && data[j] != '"' {
				j++
			}
			toks = append(toks, `"`+data[i+1:min(j, len(data))])
			i = j + 1
		case c == '{':
			if len(toks) > 0 {
				scope = append(scope, toks[0])
			} else {
				scope = append(scope, "")
			}
			toks = toks[:0]
			i++
		case c == '}':
			if len(scope) > 0 {
				scope = scope[:len(scope)-1]
			}
			toks = toks[:0]
			i++
		case c == ';':
			switch {
			case len(toks) == 1 && strings.HasPrefix(toks[0], `"`) && len(scope) > 0:
				key := strings.ToLower(strings.Trim(strings.Join(scope, "::"), ":"))
				out[key] = append(out[key], toks[0][1:])
			case len(toks) == 2 && strings.HasSuffix(toks[0], "::") && strings.HasPrefix(toks[1], `"`):
				key := strings.ToLower(strings.Trim(strings.Join(append(append([]string{}, scope...), toks[0]), "::"), ":"))
				out[key] = append(out[key], toks[1][1:])
			}
			toks = toks[:0]
			i++
		default:
			j := i
			for j < len(data) && !strings.ContainsRune(" \t\r\n{};\"", rune(data[j])) {
				j++
			}
			toks = append(toks, data[i:j])
			i = j
		}
	}
}

func aptConfList(key string) []string {
	files := []string{filepath.Join(cfg.Root, "etc/apt/apt.conf")}
	dir := filepath.Join(cfg.Root, "etc/apt/apt.conf.d")
	ents, _ := os.ReadDir(dir)
	var names []string
	for _, e := range ents {
		n := e.Name()
		if e.IsDir() || strings.HasPrefix(n, ".") || strings.HasSuffix(n, "~") || strings.HasSuffix(n, ".dpkg-new") || strings.HasSuffix(n, ".dpkg-old") {
			continue
		}
		names = append(names, n)
	}
	sort.Strings(names)
	for _, n := range names {
		files = append(files, filepath.Join(dir, n))
	}
	out := map[string][]string{}
	for _, f := range files {
		if data, err := os.ReadFile(f); err == nil {
			readAptConfLists(string(data), out)
		}
	}
	return out[strings.ToLower(key)]
}

func runInvokeHooks(key string) error {
	if cfg.Root != "/" || os.Getenv("KPKG_NO_INVOKE") != "" {
		return nil
	}
	for _, c := range aptConfList(key) {
		cmd := exec.Command("/bin/sh", "-c", c)
		cmd.Dir = "/"
		cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("Problem executing scripts %s '%s'", key, c)
		}
	}
	return nil
}
