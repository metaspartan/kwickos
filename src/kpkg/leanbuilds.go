package main

import "fmt"

const leanField = "X-Kwick-Lean"

var leanFlag int

func applyLeanFlag() {
	if leanFlag != 0 {
		cfg.Lean = leanFlag > 0
	}
}

func leanFor(db *DB, name string) *Pkg {
	if !cfg.Lean || cfg.TargetRelease != "" || name == "" {
		return nil
	}
	if in := db.lookupInstalled(name); in != nil && in.Key() == name {
		return nil
	}
	c := db.Candidate("kwick-" + name)
	if c == nil || c.Field(leanField) != name {
		return nil
	}
	if cfg.Quiet == 0 {
		fmt.Printf("Note, selecting '%s' (KwickOS lean build) for '%s'; use 'apt install --no-lean %s' for Debian's build\n", c.Name, name, name)
	}
	return c
}
