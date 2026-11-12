package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// dpkg-statoverride: Debian packages use it in postinst to give helpers
// special owners/modes (e.g. dbus-daemon-launch-helper root:messagebus 4754).
func statoverridePath() string { return filepath.Join(cfg.Admin, "statoverride") }

func lookupID(file, name string) (int, bool) {
	if n, err := strconv.Atoi(strings.TrimPrefix(name, "#")); err == nil {
		return n, true
	}
	data, err := os.ReadFile(filepath.Join(cfg.Root, "etc", file))
	if err != nil {
		return 0, false
	}
	for _, l := range strings.Split(string(data), "\n") {
		f := strings.Split(l, ":")
		if len(f) > 2 && f[0] == name {
			n, err := strconv.Atoi(f[2])
			return n, err == nil
		}
	}
	return 0, false
}

func mainStatoverride(args []string) int {
	setupPaths()
	args = parseDpkgOpts(args)
	var op string
	var rest []string
	update := false
	for _, a := range args {
		switch a {
		case "--add", "--remove", "--list":
			op = a
		case "--update":
			update = true
		case "--quiet", "--force", "--force-all", "--force-statoverride-add", "--force-statoverride-del":
		default:
			rest = append(rest, a)
		}
	}
	data, _ := os.ReadFile(statoverridePath())
	var lines []string
	for _, l := range strings.Split(string(data), "\n") {
		if strings.TrimSpace(l) != "" {
			lines = append(lines, l)
		}
	}
	save := func() {
		os.MkdirAll(cfg.Admin, 0755)
		os.WriteFile(statoverridePath(), []byte(strings.Join(lines, "\n")+"\n"), 0644)
	}
	pathOf := func(l string) string { f := strings.Fields(l); return f[len(f)-1] }
	switch op {
	case "--list":
		found := false
		for _, l := range lines {
			if len(rest) == 0 {
				fmt.Println(l)
				found = true
				continue
			}
			if ok, _ := filepath.Match(rest[0], pathOf(l)); ok || pathOf(l) == rest[0] {
				fmt.Println(l)
				found = true
			}
		}
		if !found {
			return 1
		}
	case "--remove":
		if len(rest) < 1 {
			return 2
		}
		var keep []string
		for _, l := range lines {
			if pathOf(l) != rest[0] {
				keep = append(keep, l)
			}
		}
		lines = keep
		save()
	case "--add":
		if len(rest) < 4 {
			fmt.Fprintln(os.Stderr, "dpkg-statoverride: --add needs <owner> <group> <mode> <path>")
			return 2
		}
		user, group, mode, p := rest[0], rest[1], rest[2], rest[3]
		for _, l := range lines {
			if pathOf(l) == p {
				fmt.Fprintf(os.Stderr, "dpkg-statoverride: warning: an override for '%s' already exists\n", p)
				return 0
			}
		}
		lines = append(lines, fmt.Sprintf("%s %s %s %s", user, group, mode, p))
		save()
		if update {
			uid, ok1 := lookupID("passwd", user)
			gid, ok2 := lookupID("group", group)
			m, err := strconv.ParseUint(mode, 8, 32)
			host := filepath.Join(cfg.Root, p)
			if ok1 && ok2 {
				os.Lchown(host, uid, gid)
			}
			if err == nil {
				fm := os.FileMode(m & 0777)
				if m&04000 != 0 {
					fm |= os.ModeSetuid
				}
				if m&02000 != 0 {
					fm |= os.ModeSetgid
				}
				if m&01000 != 0 {
					fm |= os.ModeSticky
				}
				os.Chmod(host, fm)
			}
		}
	default:
		return 0
	}
	return 0
}
