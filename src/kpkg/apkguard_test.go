package main

import (
	"os"
	"testing"
)

// Run with KPKG_APK_SAMPLE=/path/to/some.apk to check file listing on a
// real Alpine package.
func TestApkFileListing(t *testing.T) {
	p := os.Getenv("KPKG_APK_SAMPLE")
	if p == "" {
		t.Skip("KPKG_APK_SAMPLE not set")
	}
	files, err := apkFilesFromPath(p)
	if err != nil {
		t.Fatal(err)
	}
	if len(files) == 0 {
		t.Fatal("no files listed")
	}
	t.Logf("%d files, first %v", len(files), files[:min(3, len(files))])
}

func TestApkInstallingRegex(t *testing.T) {
	out := "( 1/42) Installing libxau (1.0.12-r0)\n(42/42) Installing xwayland (24.1.15-r0)\n(3/9) Upgrading foo (1.0-r0 -> 1.1-r0)\n"
	m := reApkInstalling.FindAllStringSubmatch(out, -1)
	if len(m) != 3 || m[0][1] != "libxau" || m[1][1] != "xwayland" || m[2][2] != "1.0-r0 -> 1.1-r0" {
		t.Fatalf("unexpected matches %q", m)
	}
}
