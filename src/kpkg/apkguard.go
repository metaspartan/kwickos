package main

import (
	"archive/tar"
	"bytes"
	"fmt"
	"github.com/klauspost/compress/gzip"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

var reApkInstalling = regexp.MustCompile(`\(\s*\d+/\d+\) (?:Installing|Upgrading) ([^ ]+) \(([^)]+)\)`)

func apkPlannedPackages(bin string, args []string) ([][2]string, error) {
	sim := append([]string{"apk", "--simulate"}, args...)
	out, err := exec.Command(bin, sim[1:]...).CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("%s", strings.TrimSpace(string(out)))
	}
	var res [][2]string
	for _, m := range reApkInstalling.FindAllStringSubmatch(string(out), -1) {
		v := m[2]
		if i := strings.Index(v, " -> "); i >= 0 {
			v = v[i+4:]
		}
		res = append(res, [2]string{m[1], v})
	}
	return res, nil
}

func apkFiles(bin, name, ver string) ([]string, error) {
	dir := filepath.Join(cfg.Root, "var/cache/apk/kwick-guard")
	os.MkdirAll(dir, 0755)
	if out, err := exec.Command(bin, "fetch", "--quiet", "-o", dir, name).CombinedOutput(); err != nil {
		return nil, fmt.Errorf("fetch %s: %s", name, strings.TrimSpace(string(out)))
	}
	return apkFilesFromPath(filepath.Join(dir, name+"-"+ver+".apk"))
}

func apkFilesFromPath(path string) ([]string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	segs, err := gzipMembers(data)
	if err != nil || len(segs) < 2 {
		return nil, fmt.Errorf("bad package %s", path)
	}
	start := len(segs) - 1
	for i, seg := range segs {
		has := false
		forEachTar(seg, func(name string, _ []byte) {
			if name == ".PKGINFO" {
				has = true
			}
		})
		if has {
			start = i + 1
			break
		}
	}
	var files []string
	for _, seg := range segs[start:] {
		zr, err := gzip.NewReader(bytes.NewReader(seg))
		if err != nil {
			continue
		}
		zr.Multistream(false)
		tr := tar.NewReader(zr)
		for {
			h, err := tr.Next()
			if err != nil {
				break
			}
			if h.Typeflag != tar.TypeDir && !strings.HasPrefix(h.Name, ".") {
				files = append(files, "/"+strings.TrimPrefix(h.Name, "./"))
			}
		}
	}
	return files, nil
}

func dpkgOwner(owners map[string]string, p string) string {
	for _, c := range []string{p, strings.TrimPrefix(p, "/usr"), "/usr" + p} {
		if o := owners[c]; o != "" {
			return o
		}
	}
	return ""
}

func guardApkAdd(bin string, args []string) ([]string, error) {
	if len(args) == 0 || args[0] != "add" {
		return args, nil
	}
	for _, a := range args {
		if a == "--force-overwrite" || a == "--simulate" || a == "-s" {
			return args, nil
		}
	}
	db, err := OpenDB()
	if err != nil || len(db.Installed) <= 1 {
		return args, nil
	}
	plan, err := apkPlannedPackages(bin, args)
	if err != nil {
		return args, nil
	}
	owners := db.installedFiles()
	var clobber []string
	for _, pv := range plan {
		files, err := apkFiles(bin, pv[0], pv[1])
		if err != nil {
			continue
		}
		for _, f := range files {
			if o := dpkgOwner(owners, f); o != "" && o != "kwick-base" && !strings.Contains(o, "kwick-base") {
				clobber = append(clobber, fmt.Sprintf("  %s (%s) would replace %s from Debian package %s", pv[0], pv[1], f, o))
				break
			}
		}
	}
	os.RemoveAll(filepath.Join(cfg.Root, "var/cache/apk/kwick-guard"))
	if len(clobber) > 0 {
		return nil, fmt.Errorf("refusing to let Alpine packages overwrite Debian files:\n%s\n"+
			"Use the Debian package instead, or pass --force-overwrite if you really mean it", strings.Join(clobber, "\n"))
	}
	return args, nil
}
