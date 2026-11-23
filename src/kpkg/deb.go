package main

import (
	"archive/tar"
	"bufio"
	"bytes"
	"compress/bzip2"
	"crypto/md5"
	"encoding/hex"
	"errors"
	"fmt"
	"github.com/klauspost/compress/gzip"
	"io"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"

	"github.com/klauspost/compress/zstd"
	"github.com/ulikunitz/xz"
)

func decompressor(name string, r io.Reader) (io.Reader, error) {
	switch {
	case strings.HasSuffix(name, ".xz"):
		return xz.NewReader(bufio.NewReaderSize(r, 1<<16))
	case strings.HasSuffix(name, ".gz"):
		return gzip.NewReader(r)
	case strings.HasSuffix(name, ".zst"):
		d, err := zstd.NewReader(r, zstd.WithDecoderConcurrency(1), zstd.WithDecoderLowmem(true))
		if err != nil {
			return nil, err
		}
		return d.IOReadCloser(), nil
	case strings.HasSuffix(name, ".bz2"):
		return bzip2.NewReader(r), nil
	}
	return r, nil
}

func arIter(f io.Reader, fn func(name string, size int64, r io.Reader) (stop bool, err error)) error {
	br := bufio.NewReaderSize(f, 1<<16)
	magic := make([]byte, 8)
	if _, err := io.ReadFull(br, magic); err != nil || string(magic) != "!<arch>\n" {
		return errors.New("not a debian package (bad ar magic)")
	}
	hdr := make([]byte, 60)
	for {
		if _, err := io.ReadFull(br, hdr); err != nil {
			if err == io.EOF {
				return nil
			}
			return err
		}
		name := strings.TrimRight(strings.TrimSpace(string(hdr[0:16])), "/")
		size, err := strconv.ParseInt(strings.TrimSpace(string(hdr[48:58])), 10, 64)
		if err != nil {
			return errors.New("corrupt ar header")
		}
		lr := io.LimitReader(br, size)
		stop, err := fn(name, size, lr)
		if err != nil || stop {
			return err
		}
		io.Copy(io.Discard, lr)
		if size%2 == 1 {
			br.ReadByte()
		}
	}
}

type DebControl struct {
	Para  *Paragraph
	Files map[string][]byte
}

func ReadDebControl(debPath string) (*DebControl, error) {
	f, err := os.Open(debPath)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	dc := &DebControl{Files: map[string][]byte{}}
	err = arIter(f, func(name string, size int64, r io.Reader) (bool, error) {
		if !strings.HasPrefix(name, "control.tar") {
			return false, nil
		}
		dr, err := decompressor(name, r)
		if err != nil {
			return true, err
		}
		tr := tar.NewReader(dr)
		for {
			h, err := tr.Next()
			if err == io.EOF {
				break
			}
			if err != nil {
				return true, err
			}
			n := strings.TrimPrefix(path.Clean("/"+h.Name), "/")
			if h.Typeflag == tar.TypeReg && n != "" {
				b, err := io.ReadAll(io.LimitReader(tr, 64<<20))
				if err != nil {
					return true, err
				}
				dc.Files[n] = b
			}
		}
		return true, nil
	})
	if err != nil {
		return nil, err
	}
	ctrl, ok := dc.Files["control"]
	if !ok {
		return nil, fmt.Errorf("%s: no control file", debPath)
	}
	ParseParagraphs(bytes.NewReader(ctrl), nil, func(p *Paragraph) error { dc.Para = p; return io.EOF })
	if dc.Para == nil {
		return nil, fmt.Errorf("%s: empty control file", debPath)
	}
	return dc, nil
}

func resolveInRoot(root, p string, followLast bool) (string, error) {
	parts := strings.Split(strings.Trim(path.Clean("/"+p), "/"), "/")
	cur := "/"
	hops := 0
	for i := 0; i < len(parts); i++ {
		c := parts[i]
		if c == "" || c == "." {
			continue
		}
		if c == ".." {
			cur = path.Dir(cur)
			continue
		}
		next := path.Join(cur, c)
		if i == len(parts)-1 && !followLast {
			cur = next
			break
		}
		host := filepath.Join(root, next)
		fi, err := os.Lstat(host)
		if err == nil && fi.Mode()&os.ModeSymlink != 0 {
			hops++
			if hops > 40 {
				return "", errors.New("too many symlinks")
			}
			tgt, err := os.Readlink(host)
			if err != nil {
				return "", err
			}
			var rest []string
			if path.IsAbs(tgt) {
				rest = append(strings.Split(strings.Trim(tgt, "/"), "/"), parts[i+1:]...)
				cur = "/"
			} else {
				rest = append(strings.Split(tgt, "/"), parts[i+1:]...)
			}
			parts = append(make([]string, 0, len(rest)), rest...)
			i = -1
			continue
		}
		cur = next
	}
	return filepath.Join(root, cur), nil
}

var protectedPaths = map[string]bool{"/sbin/init": true, "/usr/sbin/init": true, "/sbin/kinit": true,
	"/usr/sbin/kinit": true, "/usr/bin/kpkg": true, "/init": true}

type extractResult struct {
	Files     []string
	Conffiles map[string]string
}

func ExtractData(debPath string, conffiles map[string]bool, oldConf map[string]string, canOverwrite func(p string) bool, shared func(p string) int, filt *pathFilter) (*extractResult, error) {
	f, err := os.Open(debPath)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	res := &extractResult{Conffiles: map[string]string{}}
	var hardlinks [][2]string
	var staged stagedFiles
	defer staged.abort()
	member := func(fn func(dr io.Reader) error) error {
		if pt := takePreTar(debPath); pt != "" {
			tf, err := os.Open(pt)
			if err == nil {
				defer os.Remove(pt)
				defer tf.Close()
				return fn(bufio.NewReaderSize(tf, 1<<16))
			}
		}
		return arIter(f, func(name string, size int64, r io.Reader) (bool, error) {
			if !strings.HasPrefix(name, "data.tar") {
				return false, nil
			}
			dr, err := decompressor(name, r)
			if err != nil {
				return true, err
			}
			return true, fn(dr)
		})
	}
	err = member(func(dr io.Reader) error {
		tr := tar.NewReader(dr)
		for {
			h, err := tr.Next()
			if err == io.EOF {
				break
			}
			if err != nil {
				return err
			}
			p := path.Clean("/" + h.Name)
			if p == "/" {
				continue
			}
			res.Files = append(res.Files, p)
			if filt.skip(p, h.Typeflag) {
				continue
			}
			if h.Typeflag != tar.TypeDir && kwickOwned(p) {
				continue
			}
			if protectedPaths[p] && h.Typeflag != tar.TypeDir {
				warn("not overwriting protected KwickOS file %s", p)
				continue
			}
			parent, err := resolveInRoot(cfg.Root, path.Dir(p), true)
			if err != nil {
				return err
			}
			host := filepath.Join(parent, path.Base(p))
			if h.Typeflag != tar.TypeDir && canOverwrite != nil && !canOverwrite(p) {
				continue
			}
			if h.Typeflag != tar.TypeDir && shared != nil && shared(p) == 1 && !conffiles[p] {
				done, err := checkSharedIdentical(host, p, h, tr)
				if err != nil {
					return err
				}
				if done {
					continue
				}
			}
			mode := os.FileMode(h.Mode & 0777)
			if h.Mode&04000 != 0 {
				mode |= os.ModeSetuid
			}
			if h.Mode&02000 != 0 {
				mode |= os.ModeSetgid
			}
			if h.Mode&01000 != 0 {
				mode |= os.ModeSticky
			}
			switch h.Typeflag {
			case tar.TypeDir:
				fi, err := os.Stat(host)
				if err == nil && fi.IsDir() {
					continue
				}
				os.MkdirAll(parent, 0755)
				if err := os.Mkdir(host, mode); err != nil && !os.IsExist(err) {
					return err
				}
				os.Lchown(host, h.Uid, h.Gid)
				os.Chmod(host, mode)
			case tar.TypeReg:
				os.MkdirAll(parent, 0755)
				if conffiles[p] {
					data, err := io.ReadAll(tr)
					if err != nil {
						return err
					}
					sum := md5.Sum(data)
					newMD5 := hex.EncodeToString(sum[:])
					res.Conffiles[p] = newMD5
					old, tracked := oldConf[p]
					tracked = tracked && old != "" && old != "newconffile"
					cur, rerr := os.ReadFile(host)
					if tracked && os.IsNotExist(rerr) {
						if _, lerr := os.Lstat(host); os.IsNotExist(lerr) {
							continue
						}
					}
					if rerr == nil {
						cs := md5.Sum(cur)
						curMD5 := hex.EncodeToString(cs[:])
						if curMD5 != newMD5 && tracked && newMD5 == old {
							continue
						}
						if curMD5 != newMD5 && (!tracked || curMD5 != old) {
							if err := staged.add(host+".dpkg-dist", bytes.NewReader(data), mode, h); err != nil {
								return err
							}
							fmt.Printf("Configuration file '%s' modified locally; new version saved as %s.dpkg-dist\n", p, p)
							continue
						}
					}
					if err := staged.add(host, bytes.NewReader(data), mode, h); err != nil {
						return err
					}
					continue
				}
				if err := staged.add(host, tr, mode, h); err != nil {
					return fmt.Errorf("unpacking %s: %w", p, err)
				}
			case tar.TypeSymlink:
				os.MkdirAll(parent, 0755)
				if fi, err := os.Lstat(host); err == nil && fi.IsDir() && fi.Mode()&os.ModeSymlink == 0 {
					continue
				}
				tmp := host + ".dpkg-new"
				os.Remove(tmp)
				if err := os.Symlink(h.Linkname, tmp); err != nil {
					return err
				}
				os.Lchown(tmp, h.Uid, h.Gid)
				if err := os.Rename(tmp, host); err != nil {
					return err
				}
			case tar.TypeLink:
				hardlinks = append(hardlinks, [2]string{path.Clean("/" + h.Linkname), p})
			case tar.TypeChar, tar.TypeBlock, tar.TypeFifo:
				os.MkdirAll(parent, 0755)
				m := uint32(mode.Perm())
				switch h.Typeflag {
				case tar.TypeChar:
					m |= syscall.S_IFCHR
				case tar.TypeBlock:
					m |= syscall.S_IFBLK
				default:
					m |= syscall.S_IFIFO
				}
				os.Remove(host)
				syscall.Mknod(host, m, int(mkdev(h.Devmajor, h.Devminor)))
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	if err := staged.commit(); err != nil {
		return nil, err
	}
	for _, hl := range hardlinks {
		src, _ := resolveInRoot(cfg.Root, hl[0], true)
		dst, _ := resolveInRoot(cfg.Root, hl[1], false)
		tmp := dst + ".dpkg-new"
		os.Remove(tmp)
		if err := os.Link(src, tmp); err == nil {
			os.Rename(tmp, dst)
		}
	}
	return res, nil
}

func checkSharedIdentical(host, p string, h *tar.Header, tr io.Reader) (bool, error) {
	fi, err := os.Lstat(host)
	if err != nil {
		return false, nil
	}
	differ := fmt.Errorf("trying to overwrite shared '%s', which is different from other instances of the package", p)
	switch h.Typeflag {
	case tar.TypeSymlink:
		if fi.Mode()&os.ModeSymlink == 0 {
			return false, differ
		}
		if t, err := os.Readlink(host); err != nil || t != h.Linkname {
			return false, differ
		}
		return true, nil
	case tar.TypeReg:
		if !fi.Mode().IsRegular() {
			return false, differ
		}
		f, err := os.Open(host)
		if err != nil {
			return false, nil
		}
		defer f.Close()
		a, b := bufio.NewReaderSize(f, 1<<16), bufio.NewReaderSize(tr, 1<<16)
		bufA, bufB := make([]byte, 1<<15), make([]byte, 1<<15)
		for {
			na, errA := io.ReadFull(a, bufA)
			nb, errB := io.ReadFull(b, bufB)
			if na != nb || !bytes.Equal(bufA[:na], bufB[:nb]) {
				return false, differ
			}
			if errA != nil || errB != nil {
				return true, nil
			}
		}
	case tar.TypeLink:
		return true, nil
	}
	return false, nil
}

func mkdev(maj, min int64) uint64 {
	return uint64((min & 0xff) | ((maj & 0xfff) << 8) | ((min &^ 0xff) << 12) | ((maj &^ 0xfff) << 32))
}

type stagedFiles struct {
	tmp, dst []string
	seen     map[string]bool
}

func (s *stagedFiles) add(host string, r io.Reader, mode os.FileMode, h *tar.Header) error {
	if fi, err := os.Lstat(host); err == nil && fi.IsDir() && fi.Mode()&os.ModeSymlink == 0 {
		return fmt.Errorf("cannot replace directory %s with a file", host)
	}
	tmp := host + ".dpkg-new"
	os.Remove(tmp)
	f, err := os.OpenFile(tmp, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return err
	}
	_, err = io.Copy(f, r)
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		os.Remove(tmp)
		return err
	}
	os.Lchown(tmp, h.Uid, h.Gid)
	os.Chmod(tmp, mode)
	os.Chtimes(tmp, h.ModTime, h.ModTime)
	if s.seen == nil {
		s.seen = map[string]bool{}
	}
	if !s.seen[host] {
		s.seen[host] = true
		s.tmp = append(s.tmp, tmp)
		s.dst = append(s.dst, host)
	}
	return nil
}

func (s *stagedFiles) sync() error {
	if len(s.tmp) == 0 {
		return nil
	}
	if len(s.tmp) > 16 {
		syscall.Sync()
		return nil
	}
	for _, t := range s.tmp {
		f, err := os.Open(t)
		if err != nil {
			return err
		}
		err = f.Sync()
		f.Close()
		if err != nil {
			return fmt.Errorf("sync %s: %v", t, err)
		}
	}
	return nil
}

func (s *stagedFiles) commit() error {
	if err := s.sync(); err != nil {
		return err
	}
	for i, t := range s.tmp {
		if err := os.Rename(t, s.dst[i]); err != nil {
			s.tmp = s.tmp[i:]
			s.dst = s.dst[i:]
			return err
		}
	}
	s.tmp, s.dst, s.seen = nil, nil, nil
	return nil
}

func (s *stagedFiles) abort() {
	for _, t := range s.tmp {
		os.Remove(t)
	}
	s.tmp, s.dst = nil, nil
}

func kwickOwned(p string) bool {
	host := filepath.Join(cfg.Root, p)
	t, err := os.Readlink(host)
	if err != nil {
		return false
	}
	b := path.Base(t)
	return b == "kinit" || b == "kpkg"
}
