package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

func protectedDirs() []string {
	u, sy := userScope(), systemScope()
	return []string{u.Config, u.State, u.Data, sy.Config, sy.State, sy.Data, runtimeDir(), libDir}
}

func isProtected(real string) bool {
	for _, d := range protectedDirs() {
		if d == "" || d == "/" {
			continue
		}
		if within(real, filepath.Clean(d)) {
			return true
		}
		if r, err := filepath.EvalSymlinks(d); err == nil && within(real, r) {
			return true
		}
	}
	return false
}

func isSecretFile(real string) bool {
	for _, sc := range []Scope{userScope(), systemScope()} {
		for _, n := range []string{"secrets.json", "secrets.json.tmp"} {
			p := filepath.Join(sc.Config, n)
			if real == p {
				return true
			}
			if r, err := filepath.EvalSymlinks(filepath.Dir(p)); err == nil && real == filepath.Join(r, n) {
				return true
			}
		}
	}
	return false
}

func (s *Server) realRoots() []string {
	var out []string
	for _, root := range s.allowedRoots() {
		rr := filepath.Clean(root)
		if r, err := filepath.EvalSymlinks(root); err == nil {
			rr = r
		}
		out = append(out, rr)
	}
	return out
}

func (s *Server) rootFor(real string) (string, error) {
	best := ""
	for _, rr := range s.realRoots() {
		if within(real, rr) && len(rr) > len(best) {
			best = rr
		}
	}
	if best == "" {
		return "", fmt.Errorf("Denied: %s is outside the folders %s may use", real, s.agent)
	}
	return best, nil
}

func (s *Server) resolveWrite(p string) (string, error) {
	rp, err := s.resolvePath(p, false)
	if err != nil {
		return "", err
	}
	if isProtected(rp) {
		return "", fmt.Errorf("Denied: %s belongs to kwick-agents (its settings, grants, state or data); agents can never change it through kwick-mcp", rp)
	}
	if st, err := os.Lstat(rp); err == nil && st.Mode()&os.ModeSymlink != 0 {
		return "", fmt.Errorf("Denied: %s is a symbolic link; write to the file it points to instead", rp)
	}
	return rp, nil
}

func fdPath(f *os.File) (string, bool) {
	l, err := os.Readlink("/proc/self/fd/" + strconv.Itoa(int(f.Fd())))
	if err != nil || !filepath.IsAbs(l) {
		return "", false
	}
	return strings.TrimSuffix(l, " (deleted)"), true
}

func (s *Server) checkOpened(f *os.File, root string, write bool) error {
	real, ok := fdPath(f)
	if !ok {
		return nil
	}
	if !within(real, root) {
		return fmt.Errorf("Denied: the path changed while it was opened and now leads outside %s", root)
	}
	if write && isProtected(real) {
		return fmt.Errorf("Denied: %s belongs to kwick-agents; agents can never change it through kwick-mcp", real)
	}
	if isSecretFile(real) {
		return fmt.Errorf("Denied: %s holds API keys", real)
	}
	return nil
}

func (s *Server) openRead(real string) (*os.File, error) {
	if isSecretFile(real) {
		return nil, fmt.Errorf("Denied: %s holds API keys", real)
	}
	root, err := s.rootFor(real)
	if err != nil {
		return nil, err
	}
	rel, err := filepath.Rel(root, real)
	if err != nil {
		return nil, err
	}
	r, err := os.OpenRoot(root)
	if err != nil {
		return nil, err
	}
	defer r.Close()
	f, err := r.Open(rel)
	if err != nil {
		return nil, cleanRootErr(err, real)
	}
	if err := s.checkOpened(f, root, false); err != nil {
		f.Close()
		return nil, err
	}
	return f, nil
}

func (s *Server) writeFile(real, mode, content string) (int, error) {
	root, err := s.rootFor(real)
	if err != nil {
		return 0, err
	}
	rel, err := filepath.Rel(root, real)
	if err != nil || rel == "." {
		return 0, fmt.Errorf("%s is a folder", real)
	}
	r, err := os.OpenRoot(root)
	if err != nil {
		return 0, err
	}
	defer r.Close()
	if d := filepath.Dir(rel); d != "." {
		if err := r.MkdirAll(d, 0o755); err != nil {
			return 0, cleanRootErr(err, real)
		}
	}
	flags := os.O_WRONLY | os.O_CREATE
	if mode == "create" {
		flags |= os.O_EXCL
	}
	f, err := r.OpenFile(rel, flags, 0o644)
	if err != nil {
		return 0, cleanRootErr(err, real)
	}
	if err := s.checkOpened(f, root, true); err != nil {
		f.Close()
		if mode == "create" {
			r.Remove(rel)
		}
		return 0, err
	}
	switch mode {
	case "overwrite":
		if err := f.Truncate(0); err != nil {
			f.Close()
			return 0, err
		}
	case "append":
		if _, err := f.Seek(0, io.SeekEnd); err != nil {
			f.Close()
			return 0, err
		}
	}
	n, err := f.WriteString(content)
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	return n, err
}

func cleanRootErr(err error, p string) error {
	var pe *os.PathError
	if errors.As(err, &pe) && strings.Contains(pe.Err.Error(), "escapes") {
		return fmt.Errorf("Denied: %s leads outside the folders this agent may use (through a symbolic link)", p)
	}
	if errors.Is(err, os.ErrExist) {
		return fmt.Errorf("%s already exists (mode create)", p)
	}
	return err
}
