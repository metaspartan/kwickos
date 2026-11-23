package main

import (
	"archive/tar"
	"archive/zip"
	"compress/bzip2"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"

	"github.com/klauspost/compress/zstd"
)

var httpClient = &http.Client{Timeout: 0, Transport: &http.Transport{Proxy: http.ProxyFromEnvironment, TLSHandshakeTimeout: 30 * time.Second, ResponseHeaderTimeout: 60 * time.Second}}

type progress struct {
	total, done int64
	last        time.Time
	label       string
	tty         bool
}

func (p *progress) Write(b []byte) (int, error) {
	p.done += int64(len(b))
	if p.tty && time.Since(p.last) > 200*time.Millisecond {
		p.last = time.Now()
		if p.total > 0 {
			fmt.Fprintf(os.Stderr, "\r  %s %5.1f%% of %s", p.label, float64(p.done)*100/float64(p.total), humanBytes(p.total))
		} else {
			fmt.Fprintf(os.Stderr, "\r  %s %s", p.label, humanBytes(p.done))
		}
	}
	return len(b), nil
}

func humanBytes(n int64) string {
	f := float64(n)
	for _, u := range []string{"B", "KB", "MB", "GB"} {
		if f < 1024 || u == "GB" {
			if u == "B" {
				return fmt.Sprintf("%d B", n)
			}
			return fmt.Sprintf("%.1f %s", f, u)
		}
		f /= 1024
	}
	return ""
}

func download(url, want string, size int64, dest string) error {
	want = strings.ToLower(want)
	if len(want) != 64 {
		return fmt.Errorf("refusing to download %s without a pinned sha256", url)
	}
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return err
	}
	if f, err := os.Open(dest); err == nil {
		h := sha256.New()
		io.Copy(h, f)
		f.Close()
		if hex.EncodeToString(h.Sum(nil)) == want {
			return nil
		}
		os.Remove(dest)
	}
	var lastErr error
	for attempt := 0; attempt < 3; attempt++ {
		if attempt > 0 {
			time.Sleep(time.Duration(attempt*2) * time.Second)
		}
		lastErr = downloadOnce(url, want, size, dest)
		if lastErr == nil {
			return nil
		}
		var hm hashMismatch
		if errors.As(lastErr, &hm) {
			return lastErr
		}
	}
	return lastErr
}

type hashMismatch struct{ url, got, want string }

func (h hashMismatch) Error() string {
	return fmt.Sprintf("sha256 mismatch for %s: got %s, want %s; nothing was installed", h.url, h.got, h.want)
}

func downloadOnce(url, want string, size int64, dest string) error {
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", "kwick-agents/"+version)
	resp, err := httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("download failed: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("download failed: %s returned %s", url, resp.Status)
	}
	part := dest + ".part"
	f, err := os.OpenFile(part, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	h := sha256.New()
	total := resp.ContentLength
	if total <= 0 {
		total = size
	}
	p := &progress{total: total, label: path.Base(url), tty: isTerminal(2)}
	_, err = io.Copy(io.MultiWriter(f, h, p), resp.Body)
	if p.tty {
		fmt.Fprint(os.Stderr, "\r\033[K")
	}
	cerr := f.Close()
	if err != nil {
		os.Remove(part)
		return fmt.Errorf("download failed: %v", err)
	}
	if cerr != nil {
		os.Remove(part)
		return cerr
	}
	got := hex.EncodeToString(h.Sum(nil))
	if got != want {
		os.Remove(part)
		return hashMismatch{url, got, want}
	}
	return os.Rename(part, dest)
}

func fetchText(url string, limit int64) (string, error) {
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", "kwick-agents/"+version)
	hfAuth(req)
	c := &http.Client{Timeout: 60 * time.Second}
	resp, err := c.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("%s returned %s", url, resp.Status)
	}
	b, err := io.ReadAll(io.LimitReader(resp.Body, limit))
	return string(b), err
}

func safeJoin(root, rel string) (string, error) {
	rel = path.Clean("/" + strings.ReplaceAll(rel, "\\", "/"))
	if rel == "/" {
		return root, nil
	}
	return filepath.Join(root, filepath.FromSlash(rel[1:])), nil
}

func stripRename(name string, strip int, rename map[string]string) (string, bool) {
	name = strings.TrimPrefix(path.Clean("/"+name), "/")
	if name == "" || name == "." {
		return "", false
	}
	parts := strings.Split(name, "/")
	if len(parts) <= strip {
		return "", false
	}
	rel := strings.Join(parts[strip:], "/")
	if r, ok := rename[rel]; ok {
		rel = r
	}
	return rel, true
}

func extract(archive, format, dest string, strip int, rename map[string]string) error {
	if err := os.MkdirAll(dest, 0o755); err != nil {
		return err
	}
	if format == "zip" {
		return extractZip(archive, dest, strip, rename)
	}
	f, err := os.Open(archive)
	if err != nil {
		return err
	}
	defer f.Close()
	var r io.Reader
	switch format {
	case "tar.gz", "tgz":
		gz, err := gzip.NewReader(f)
		if err != nil {
			return err
		}
		defer gz.Close()
		r = gz
	case "tar.bz2":
		r = bzip2.NewReader(f)
	case "tar.zst":
		zr, err := zstd.NewReader(f)
		if err != nil {
			return err
		}
		defer zr.Close()
		r = zr
	case "tar":
		r = f
	default:
		return fmt.Errorf("unknown archive format %q", format)
	}
	tr := tar.NewReader(r)
	type link struct{ path, target string }
	var hard []link
	for {
		h, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("reading %s: %v", filepath.Base(archive), err)
		}
		rel, ok := stripRename(h.Name, strip, rename)
		if !ok {
			continue
		}
		p, _ := safeJoin(dest, rel)
		mode := os.FileMode(h.Mode).Perm() | 0o200
		switch h.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(p, mode|0o700); err != nil {
				return err
			}
		case tar.TypeReg:
			if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
				return err
			}
			os.Remove(p)
			w, err := os.OpenFile(p, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, mode)
			if err != nil {
				return err
			}
			if _, err := io.Copy(w, tr); err != nil {
				w.Close()
				return err
			}
			if err := w.Close(); err != nil {
				return err
			}
		case tar.TypeSymlink:
			t := h.Linkname
			if filepath.IsAbs(t) {
				continue
			}
			resolved := path.Clean(path.Join(path.Dir("/"+rel), t))
			if strings.HasPrefix(resolved, "/..") {
				continue
			}
			os.MkdirAll(filepath.Dir(p), 0o755)
			os.Remove(p)
			if err := os.Symlink(t, p); err != nil {
				return err
			}
		case tar.TypeLink:
			trel, ok := stripRename(h.Linkname, strip, rename)
			if ok {
				hard = append(hard, link{p, trel})
			}
		}
	}
	for _, l := range hard {
		src, _ := safeJoin(dest, l.target)
		os.Remove(l.path)
		if err := os.Link(src, l.path); err != nil {
			return err
		}
	}
	return nil
}

func extractZip(archive, dest string, strip int, rename map[string]string) error {
	zr, err := zip.OpenReader(archive)
	if err != nil {
		return err
	}
	defer zr.Close()
	for _, f := range zr.File {
		rel, ok := stripRename(f.Name, strip, rename)
		if !ok {
			continue
		}
		p, _ := safeJoin(dest, rel)
		if f.FileInfo().IsDir() {
			os.MkdirAll(p, 0o755)
			continue
		}
		mode := f.Mode()
		if mode&os.ModeSymlink != 0 {
			rc, err := f.Open()
			if err != nil {
				return err
			}
			t, _ := io.ReadAll(io.LimitReader(rc, 4096))
			rc.Close()
			if filepath.IsAbs(string(t)) {
				continue
			}
			os.MkdirAll(filepath.Dir(p), 0o755)
			os.Remove(p)
			if err := os.Symlink(string(t), p); err != nil {
				return err
			}
			continue
		}
		perm := mode.Perm() | 0o200
		if perm&0o111 == 0 && perm&0o400 == 0 {
			perm = 0o644
		}
		os.MkdirAll(filepath.Dir(p), 0o755)
		rc, err := f.Open()
		if err != nil {
			return err
		}
		os.Remove(p)
		w, err := os.OpenFile(p, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, perm)
		if err != nil {
			rc.Close()
			return err
		}
		_, err = io.Copy(w, rc)
		rc.Close()
		if cerr := w.Close(); err == nil {
			err = cerr
		}
		if err != nil {
			return err
		}
	}
	return nil
}
