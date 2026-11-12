package main

// Parallel pre-decompression.
//
// Unpacking must happen in dependency order, but decompressing the
// data.tar.{xz,zst,gz} members does not. kpkg therefore decompresses every
// downloaded package concurrently (one worker per CPU) into a plain tar in
// the archive cache, and the ordered unpack phase just streams those tars.
// On a 2-vCPU VM this roughly halves install time for multi-package
// transactions; on bigger machines the win is larger.

import (
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
)

var preTar sync.Map // deb path -> decompressed data tar path

func predecompress(debs []string) {
	n := runtime.NumCPU()
	if n > 8 {
		n = 8
	}
	if n < 2 || len(debs) < 2 {
		return
	}
	dir := filepath.Join(cfg.Cache, "partial")
	os.MkdirAll(dir, 0755)
	jobs := make(chan string)
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for deb := range jobs {
				out := filepath.Join(dir, filepath.Base(deb)+".data.tar")
				if err := extractDataMember(deb, out); err == nil {
					preTar.Store(deb, out)
				} else {
					os.Remove(out)
				}
			}
		}()
	}
	for _, d := range debs {
		jobs <- d
	}
	close(jobs)
	wg.Wait()
}

func extractDataMember(deb, out string) error {
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
		w, err := os.Create(out)
		if err != nil {
			return true, err
		}
		_, err = io.Copy(w, dr)
		if cerr := w.Close(); err == nil {
			err = cerr
		}
		return true, err
	})
}

// takePreTar returns (and forgets) the pre-decompressed tar for deb.
func takePreTar(deb string) string {
	if v, ok := preTar.LoadAndDelete(deb); ok {
		return v.(string)
	}
	return ""
}
