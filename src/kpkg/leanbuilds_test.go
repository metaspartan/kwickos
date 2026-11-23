package main

import "testing"

func leanTestDB() *DB {
	return newTestDB(
		mkPkg("Package: curl", "Version: 8.14.1-2", "Depends: libcurl4t64"),
		mkPkg("Package: libcurl4t64", "Version: 8.14.1-2"),
		mkPkg("Package: kwick-curl", "Version: 8.23.0-0kwick1", "Provides: curl (= 8.23.0-0kwick1)", "Conflicts: curl", "Replaces: curl", "X-Kwick-Lean: curl"),
		mkPkg("Package: kwick-essentials", "Version: 1"),
		mkPkg("Package: essentials", "Version: 1"),
		mkPkg("Package: python3", "Version: 3.13.5-1", "Depends: python3-minimal"),
		mkPkg("Package: python3-minimal", "Version: 3.13.5-1"),
		mkPkg("Package: python3-yaml", "Version: 6.0-1", "Depends: python3 (>= 3.13~)"),
		mkPkg("Package: kwick-python3", "Version: 3.14.10-0kwick1", "Conflicts: python3, python3-minimal", "X-Kwick-Lean: python3"),
		mkPkg("Package: tool", "Version: 1", "Depends: curl (>= 7.0)"),
	)
}

func resolveName(t *testing.T, db *DB, req string) string {
	t.Helper()
	p, err := resolveRequest(db, req)
	if err != nil {
		t.Fatalf("%s: %v", req, err)
	}
	return p.Name
}

func TestLeanBuildsSelection(t *testing.T) {
	setupMA(t)
	db := leanTestDB()
	cfg.Lean = false
	if got := resolveName(t, db, "curl"); got != "curl" {
		t.Errorf("lean off: curl -> %s", got)
	}
	cfg.Lean, cfg.Quiet = true, 1
	t.Cleanup(func() { cfg.Lean, cfg.Quiet, cfg.TargetRelease = false, 0, "" })
	cases := map[string]string{"curl": "kwick-curl", "python3": "kwick-python3", "essentials": "essentials",
		"curl=8.14.1-2": "curl", "curl:amd64": "curl", "libcurl4t64": "libcurl4t64"}
	for req, want := range cases {
		if got := resolveName(t, db, req); got != want {
			t.Errorf("lean on: %s -> %s, want %s", req, got, want)
		}
	}
	cfg.TargetRelease = "trixie"
	if got := resolveName(t, db, "curl"); got != "curl" {
		t.Errorf("-t trixie: curl -> %s", got)
	}
}

func TestLeanBuildsKeepDebianInstalled(t *testing.T) {
	setupMA(t)
	db := leanTestDB()
	cfg.Lean, cfg.Quiet = true, 1
	t.Cleanup(func() { cfg.Lean, cfg.Quiet = false, 0 })
	in := &Installed{Pkg: mkPkg("Package: curl", "Version: 8.14.1-2", "Status: install ok installed"), Status: "install ok installed"}
	db.Installed["curl"] = in
	if got := resolveName(t, db, "curl"); got != "curl" {
		t.Errorf("with Debian curl installed: curl -> %s", got)
	}
}

func TestLeanBuildsDependenciesUseDebianOrProvides(t *testing.T) {
	setupMA(t)
	db := leanTestDB()
	cfg.Lean = true
	t.Cleanup(func() { cfg.Lean = false })
	pl := db.NewPlan(ResolveOpts{Upgrade: true})
	pl.Add(db.Candidate("tool"), true)
	if err := pl.Resolve(); err != nil {
		t.Fatal(err)
	}
	if _, ok := pl.Install["kwick-curl"]; ok {
		t.Errorf("a dependency picked the lean build: %v", sortedKeys(pl.Install))
	}

	kc := db.Candidate("kwick-curl")
	db.Installed["kwick-curl"] = &Installed{Pkg: kc, Status: "install ok installed"}
	kc.P.Set("Status", "install ok installed")
	pl = db.NewPlan(ResolveOpts{Upgrade: true})
	pl.Add(db.Candidate("tool"), true)
	if err := pl.Resolve(); err != nil {
		t.Fatal(err)
	}
	if _, ok := pl.Install["curl"]; ok {
		t.Errorf("installed kwick-curl did not satisfy curl (>= 7.0): %v", sortedKeys(pl.Install))
	}

	kp := db.Candidate("kwick-python3")
	db.Installed["kwick-python3"] = &Installed{Pkg: kp, Status: "install ok installed"}
	kp.P.Set("Status", "install ok installed")
	pl = db.NewPlan(ResolveOpts{Upgrade: true})
	pl.Add(db.Candidate("python3-yaml"), true)
	if err := pl.Resolve(); err != nil {
		t.Fatal(err)
	}
	if _, ok := pl.Install["python3"]; !ok {
		t.Errorf("python3-yaml did not pull Debian's python3: %v", sortedKeys(pl.Install))
	}
	if pl.Remove["kwick-python3"] == nil {
		t.Errorf("kwick-python3 not replaced by Debian's python3")
	}
}
