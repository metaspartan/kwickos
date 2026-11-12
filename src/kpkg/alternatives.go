package main

// update-alternatives, storing state in Debian's on-disk format
// (/var/lib/dpkg/alternatives/<name>) so the real tool could take over.

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

type altChoice struct {
	Path     string
	Priority int
	Slaves   map[string]string // slave name -> path
}

type altGroup struct {
	Name, Link string
	Mode       string // auto | manual
	SlaveLinks map[string]string
	SlaveOrder []string
	Choices    []*altChoice
}

func altDir() string   { return filepath.Join(cfg.Root, "etc/alternatives") }
func altAdmin() string { return filepath.Join(cfg.Admin, "alternatives") }

func loadAlt(name string) *altGroup {
	data, err := os.ReadFile(filepath.Join(altAdmin(), name))
	if err != nil {
		return nil
	}
	l := strings.Split(string(data), "\n")
	g := &altGroup{Name: name, SlaveLinks: map[string]string{}}
	if len(l) < 2 {
		return nil
	}
	g.Mode, g.Link = l[0], l[1]
	i := 2
	for i+1 < len(l) && l[i] != "" {
		g.SlaveLinks[l[i]] = l[i+1]
		g.SlaveOrder = append(g.SlaveOrder, l[i])
		i += 2
	}
	i++
	for i+1 < len(l) && l[i] != "" {
		c := &altChoice{Path: l[i], Slaves: map[string]string{}}
		c.Priority, _ = strconv.Atoi(l[i+1])
		i += 2
		for _, s := range g.SlaveOrder {
			if i < len(l) {
				if l[i] != "" {
					c.Slaves[s] = l[i]
				}
				i++
			}
		}
		g.Choices = append(g.Choices, c)
	}
	return g
}

func (g *altGroup) save() error {
	os.MkdirAll(altAdmin(), 0755)
	if len(g.Choices) == 0 {
		os.Remove(filepath.Join(altAdmin(), g.Name))
		return nil
	}
	var b strings.Builder
	fmt.Fprintf(&b, "%s\n%s\n", g.Mode, g.Link)
	for _, s := range g.SlaveOrder {
		fmt.Fprintf(&b, "%s\n%s\n", s, g.SlaveLinks[s])
	}
	b.WriteString("\n")
	for _, c := range g.Choices {
		fmt.Fprintf(&b, "%s\n%d\n", c.Path, c.Priority)
		for _, s := range g.SlaveOrder {
			fmt.Fprintf(&b, "%s\n", c.Slaves[s])
		}
	}
	b.WriteString("\n")
	return os.WriteFile(filepath.Join(altAdmin(), g.Name), []byte(b.String()), 0644)
}

func (g *altGroup) best() *altChoice {
	var best *altChoice
	for _, c := range g.Choices {
		if best == nil || c.Priority > best.Priority {
			best = c
		}
	}
	return best
}

func (g *altGroup) current() string {
	t, _ := os.Readlink(filepath.Join(altDir(), g.Name))
	return t
}

func setLink(link, target string) {
	host := filepath.Join(cfg.Root, link)
	os.MkdirAll(filepath.Dir(host), 0755)
	tmp := host + ".dpkg-tmp"
	os.Remove(tmp)
	if os.Symlink(target, tmp) == nil {
		os.Rename(tmp, host)
	}
}

func (g *altGroup) apply(c *altChoice) {
	if c == nil {
		os.Remove(filepath.Join(altDir(), g.Name))
		os.Remove(filepath.Join(cfg.Root, g.Link))
		for _, s := range g.SlaveOrder {
			os.Remove(filepath.Join(altDir(), s))
			os.Remove(filepath.Join(cfg.Root, g.SlaveLinks[s]))
		}
		return
	}
	setLink("/etc/alternatives/"+g.Name, c.Path)
	if fi, err := os.Lstat(filepath.Join(cfg.Root, g.Link)); err != nil || fi.Mode()&os.ModeSymlink != 0 {
		setLink(g.Link, "/etc/alternatives/"+g.Name)
	}
	for _, s := range g.SlaveOrder {
		if p := c.Slaves[s]; p != "" {
			setLink("/etc/alternatives/"+s, p)
			setLink(g.SlaveLinks[s], "/etc/alternatives/"+s)
		} else {
			os.Remove(filepath.Join(altDir(), s))
			os.Remove(filepath.Join(cfg.Root, g.SlaveLinks[s]))
		}
	}
}

func mainAlternatives(args []string) int {
	quiet := false
	var a []string
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--quiet":
			quiet = true
		case "--verbose", "--force", "--skip-auto":
		case "--altdir", "--admindir", "--log":
			i++
		default:
			a = append(a, args[i])
		}
	}
	if len(a) == 0 {
		fmt.Fprintln(os.Stderr, "update-alternatives: need --install, --remove, --set, --auto, --display, --query, --list or --config")
		return 2
	}
	switch a[0] {
	case "--install":
		if len(a) < 5 {
			fmt.Fprintln(os.Stderr, "update-alternatives: --install needs <link> <name> <path> <priority>")
			return 2
		}
		link, name, p := a[1], a[2], a[3]
		prio, _ := strconv.Atoi(a[4])
		g := loadAlt(name)
		if g == nil {
			g = &altGroup{Name: name, Link: link, Mode: "auto", SlaveLinks: map[string]string{}}
		}
		g.Link = link
		c := &altChoice{Path: p, Priority: prio, Slaves: map[string]string{}}
		for i := 5; i+3 < len(a)+0 && a[i] == "--slave"; i += 4 {
			sl, sn, sp := a[i+1], a[i+2], a[i+3]
			if _, ok := g.SlaveLinks[sn]; !ok {
				g.SlaveOrder = append(g.SlaveOrder, sn)
			}
			g.SlaveLinks[sn] = sl
			c.Slaves[sn] = sp
		}
		replaced := false
		for i, x := range g.Choices {
			if x.Path == p {
				g.Choices[i], replaced = c, true
			}
		}
		if !replaced {
			g.Choices = append(g.Choices, c)
		}
		if g.Mode == "auto" {
			b := g.best()
			if g.current() != b.Path && !quiet {
				fmt.Printf("update-alternatives: using %s to provide %s (%s) in auto mode\n", b.Path, link, name)
			}
			g.apply(b)
		} else if cur := g.current(); cur == p {
			g.apply(c)
		}
		g.save()
	case "--remove":
		if len(a) < 3 {
			return 2
		}
		g := loadAlt(a[1])
		if g == nil {
			return 0
		}
		cur := g.current()
		for i, c := range g.Choices {
			if c.Path == a[2] {
				g.Choices = append(g.Choices[:i], g.Choices[i+1:]...)
				break
			}
		}
		if cur == a[2] || g.Mode == "auto" {
			g.Mode = "auto"
			g.apply(g.best())
		}
		g.save()
	case "--remove-all":
		if g := loadAlt(a[1]); g != nil {
			g.apply(nil)
			g.Choices = nil
			g.save()
		}
	case "--auto":
		if g := loadAlt(a[1]); g != nil {
			g.Mode = "auto"
			g.apply(g.best())
			g.save()
		}
	case "--set":
		if len(a) < 3 {
			return 2
		}
		g := loadAlt(a[1])
		if g == nil {
			fmt.Fprintf(os.Stderr, "update-alternatives: error: no alternatives for %s\n", a[1])
			return 2
		}
		for _, c := range g.Choices {
			if c.Path == a[2] {
				g.Mode = "manual"
				g.apply(c)
				g.save()
				fmt.Printf("update-alternatives: using %s to provide %s (%s) in manual mode\n", c.Path, g.Link, g.Name)
				return 0
			}
		}
		fmt.Fprintf(os.Stderr, "update-alternatives: error: alternative %s for %s not registered\n", a[2], a[1])
		return 2
	case "--display", "--query", "--list", "--config":
		if len(a) < 2 {
			return 2
		}
		g := loadAlt(a[1])
		if g == nil {
			fmt.Fprintf(os.Stderr, "update-alternatives: error: no alternatives for %s\n", a[1])
			return 2
		}
		sort.SliceStable(g.Choices, func(i, j int) bool { return g.Choices[i].Priority > g.Choices[j].Priority })
		switch a[0] {
		case "--list":
			for _, c := range g.Choices {
				fmt.Println(c.Path)
			}
		case "--query":
			fmt.Printf("Name: %s\nLink: %s\nStatus: %s\nBest: %s\nValue: %s\n\n", g.Name, g.Link, g.Mode, g.best().Path, g.current())
			for _, c := range g.Choices {
				fmt.Printf("Alternative: %s\nPriority: %d\n\n", c.Path, c.Priority)
			}
		default:
			fmt.Printf("%s - %s mode\n  link best version is %s\n  link currently points to %s\n  link %s is %s\n", g.Name, g.Mode, g.best().Path, g.current(), g.Name, g.Link)
			for _, c := range g.Choices {
				fmt.Printf("%s - priority %d\n", c.Path, c.Priority)
			}
		}
	case "--get-selections":
		ents, _ := os.ReadDir(altAdmin())
		for _, e := range ents {
			if g := loadAlt(e.Name()); g != nil {
				fmt.Printf("%-30s %-8s %s\n", g.Name, g.Mode, g.current())
			}
		}
	default:
		fmt.Fprintf(os.Stderr, "update-alternatives: unknown action %s\n", a[0])
		return 2
	}
	return 0
}
