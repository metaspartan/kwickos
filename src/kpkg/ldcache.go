package main

import (
	"os"
	"path/filepath"
	"strings"
)

// refreshLdCache runs ldconfig before maintainer scripts when new shared
// libraries were unpacked. Debian's dpkg defers this to the libc-bin
// trigger, which is fine on Debian where /etc/ld.so.cache already lists the
// multiarch directories. On KwickOS the first glibc install starts without a
// cache, and Alpine (musl) libraries installed with `apk` live in /usr/lib,
// which glibc searches by default - so a Debian binary run from a postinst
// could pick up Alpine's libcrypto. A fresh cache puts the multiarch
// directories first.
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
