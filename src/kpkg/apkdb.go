package main

import (
	"archive/tar"
	"bufio"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"strings"
)

var apkInstalledDBs = []string{"/lib/apk/db/installed", "/usr/lib/apk/db/installed"}

func apkBasePackage(name, origin string) bool {
	return name == "kwick-base" || origin == "kwick-base"
}

func loadApkOwners(root string) map[string]string {
	owners := map[string]string{}
	seen := map[string]bool{}
	dirs := map[string]string{}
	for _, db := range apkInstalledDBs {
		host, err := resolveInRoot(root, db, true)
		if err != nil || seen[host] {
			continue
		}
		seen[host] = true
		data, err := os.ReadFile(host)
		if err != nil {
			continue
		}
		parseApkInstalled(string(data), func(pkg, dir, name string) {
			d, ok := dirs[dir]
			if !ok {
				d, err = resolveInRoot(root, "/"+dir, true)
				if err != nil {
					d = ""
				}
				dirs[dir] = d
			}
			if d != "" {
				owners[filepath.Join(d, name)] = pkg
			}
		})
	}
	return owners
}

func parseApkInstalled(s string, fn func(pkg, dir, name string)) {
	var pkg, origin, dir string
	var files [][2]string
	flush := func() {
		if pkg != "" && !apkBasePackage(pkg, origin) {
			for _, f := range files {
				fn(pkg, f[0], f[1])
			}
		}
		pkg, origin, dir, files = "", "", "", files[:0]
	}
	for _, l := range strings.Split(s, "\n") {
		l = strings.TrimRight(l, "\r")
		if l == "" {
			flush()
			continue
		}
		if len(l) < 2 || l[1] != ':' {
			continue
		}
		v := l[2:]
		switch l[0] {
		case 'P':
			pkg = v
		case 'o':
			origin = v
		case 'F':
			dir = strings.Trim(v, "/")
		case 'R':
			if v != "" {
				files = append(files, [2]string{dir, v})
			}
		}
	}
	flush()
}

func debDataEntries(deb string, fn func(h *tar.Header) error) error {
	if v, ok := preTar.Load(deb); ok {
		if f, err := os.Open(v.(string)); err == nil {
			defer f.Close()
			return walkTar(bufio.NewReaderSize(f, 1<<16), fn)
		}
	}
	f, err := os.Open(deb)
	if err != nil {
		return err
	}
	defer f.Close()
	return arIter(f, func(name string, size int64, r io.Reader) (bool, error) {
		if !strings.HasPrefix(name, "data.tar") {
			return false, nil
		}
		dr, err := decompressor(name, r)
		if err != nil {
			return true, err
		}
		return true, walkTar(dr, fn)
	})
}

func walkTar(r io.Reader, fn func(h *tar.Header) error) error {
	tr := tar.NewReader(r)
	for {
		h, err := tr.Next()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		if err := fn(h); err != nil {
			return err
		}
	}
}

func (tx *Tx) checkApkConflicts(p *Pkg, deb string) error {
	if tx.apkOwners == nil {
		tx.apkOwners = loadApkOwners(cfg.Root)
	}
	if len(tx.apkOwners) == 0 {
		return nil
	}
	filt := tx.filters()
	type hit struct{ path, owner string }
	var hits []hit
	if tx.owners == nil {
		tx.loadOwners()
	}
	links := map[string]string{}
	err := debDataEntries(deb, func(h *tar.Header) error {
		if h.Typeflag == tar.TypeDir {
			return nil
		}
		fp := path.Clean("/" + h.Name)
		if h.Typeflag == tar.TypeSymlink {
			links[fp] = h.Linkname
		}
		if fp == "/" || protectedPaths[fp] || filt.skip(fp, h.Typeflag) {
			return nil
		}
		parent, err := resolveInRootLinks(cfg.Root, path.Dir(fp), true, links)
		if err != nil {
			return nil
		}
		host := filepath.Join(parent, path.Base(fp))
		o := tx.apkOwners[host]
		if o == "" || kwickOwned(fp) {
			return nil
		}
		logical := path.Join("/", filepath.ToSlash(strings.TrimPrefix(parent, cfg.Root)), path.Base(fp))
		if len(tx.owners[fp]) > 0 || len(tx.owners[logical]) > 0 {
			return nil
		}
		hits = append(hits, hit{fp, o})
		return nil
	})
	if err != nil {
		return fmt.Errorf("error processing archive %s: %v", deb, err)
	}
	if len(hits) == 0 {
		return nil
	}
	if cfg.ForceOverwrite {
		for _, h := range hits {
			warn("%s: overwriting '%s', which is also in Alpine (apk) package %s", p.Name, h.path, h.owner)
		}
		return nil
	}
	var b strings.Builder
	pkgs := map[string]bool{}
	for i, h := range hits {
		pkgs[h.owner] = true
		if i < 10 {
			fmt.Fprintf(&b, "\n  trying to overwrite '%s', which is also in Alpine (apk) package %s", h.path, h.owner)
		}
	}
	if len(hits) > 10 {
		fmt.Fprintf(&b, "\n  ... and %d more", len(hits)-10)
	}
	return fmt.Errorf("%s (%s) conflicts with files installed by apk:%s\nRemove the Alpine package first (apk del %s), or pass --force-overwrite if you really mean it",
		p.Name, p.Version, b.String(), strings.Join(sortedKeys(pkgs), " "))
}
