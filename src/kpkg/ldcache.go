package main

import (
	"os"
	"path/filepath"
	"strings"
)

func (tx *Tx) refreshLdCache() {
	if tx.ldSeen >= len(tx.unpacked) {
		return
	}
	newLibs := false
	for _, f := range tx.unpacked[tx.ldSeen:] {
		if strings.Contains(f, ".so") && (strings.Contains(f, "/lib/") || strings.Contains(f, "/lib64/")) {
			newLibs = true
			break
		}
	}
	tx.ldSeen = len(tx.unpacked)
	if !newLibs {
		return
	}
	for _, p := range []string{"usr/sbin/ldconfig", "sbin/ldconfig.real", "usr/sbin/ldconfig.real"} {
		host := filepath.Join(cfg.Root, p)
		if fi, err := os.Lstat(host); err == nil && fi.Mode().IsRegular() {
			if t, err := os.ReadFile(host); err == nil && len(t) > 4 && string(t[:4]) == "\x7fELF" {
				runScriptAt(host, "/"+p, "libc-bin", "ldconfig")
				return
			}
		}
	}
}
