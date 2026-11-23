package main

import (
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"text/tabwriter"
	"time"
)

type DownloadInfo struct {
	State   string `json:"state"`
	Done    int64  `json:"done"`
	Total   int64  `json:"total"`
	Rate    int64  `json:"rate"`
	Started string `json:"started"`
	PID     int    `json:"pid"`
	Error   string `json:"error,omitempty"`
}

func pullsDir() string {
	if inferSystem {
		return "/var/lib/kwick-inference/pulls"
	}
	return filepath.Join(userScope().State, "inference-pulls")
}

func pullPath(id string) string { return filepath.Join(pullsDir(), id+".json") }

func pullAlive(pid int) bool {
	if pid <= 1 {
		return false
	}
	if pid == os.Getpid() {
		return true
	}
	cl, err := os.ReadFile(fmt.Sprintf("/proc/%d/cmdline", pid))
	return err == nil && strings.Contains(string(cl), "inference")
}

func loadDownload(id string) *DownloadInfo {
	if !modelIDRe.MatchString(id) {
		return nil
	}
	var d DownloadInfo
	if readJSONFile(pullPath(id), &d) != nil || d.State == "" {
		return nil
	}
	if (d.State == "downloading" || d.State == "verifying") && !pullAlive(d.PID) {
		d.State = "failed"
		d.Rate = 0
		d.Error = "the download was interrupted"
	}
	return &d
}

func allDownloads() map[string]*DownloadInfo {
	out := map[string]*DownloadInfo{}
	ents, _ := os.ReadDir(pullsDir())
	for _, e := range ents {
		id := strings.TrimSuffix(e.Name(), ".json")
		if id == e.Name() {
			continue
		}
		if d := loadDownload(id); d != nil {
			out[id] = d
		}
	}
	return out
}

func partialBytes(m *ModelEntry) int64 {
	var n int64
	for _, f := range m.Files {
		d := filepath.Join(modelDir(m.ID), filepath.FromSlash(f.Name))
		if st, err := os.Stat(d); err == nil && st.Size() == f.Size {
			continue
		}
		if st, err := os.Stat(d + ".part"); err == nil && st.Size() <= f.Size {
			n += st.Size()
		}
	}
	return n
}

type pullTracker struct {
	id      string
	total   int64
	base    int64
	done    int64
	state   string
	started time.Time
	last    time.Time
	lastAt  time.Time
	lastN   int64
	rate    float64
	sigs    chan os.Signal
}

func newPullTracker(m *ModelEntry) *pullTracker {
	t := &pullTracker{id: m.ID, total: m.size(), state: "downloading", started: time.Now()}
	os.MkdirAll(pullsDir(), 0o755)
	t.sigs = make(chan os.Signal, 1)
	signal.Notify(t.sigs, syscall.SIGTERM, syscall.SIGINT)
	go func() {
		s, ok := <-t.sigs
		if !ok {
			return
		}
		os.Remove(pullPath(t.id))
		if s == syscall.SIGINT {
			os.Exit(130)
		}
		os.Exit(143)
	}()
	t.flush("")
	return t
}

func (t *pullTracker) flush(errMsg string) {
	d := DownloadInfo{State: t.state, Done: t.done, Total: t.total, Rate: int64(t.rate), Started: t.started.UTC().Format(time.RFC3339), PID: os.Getpid(), Error: errMsg}
	if t.state != "downloading" {
		d.Rate = 0
	}
	writeJSONFile(pullPath(t.id), d, 0o644)
	t.last = time.Now()
}

func (t *pullTracker) bytes(cur int64) {
	if t == nil {
		return
	}
	t.done = t.base + cur
	t.state = "downloading"
	now := time.Now()
	if t.lastAt.IsZero() {
		t.lastAt, t.lastN = now, t.done
	} else if dt := now.Sub(t.lastAt); dt >= 500*time.Millisecond {
		inst := float64(t.done-t.lastN) / dt.Seconds()
		if t.rate == 0 {
			t.rate = inst
		} else {
			t.rate = 0.6*t.rate + 0.4*inst
		}
		t.lastAt, t.lastN = now, t.done
	}
	if now.Sub(t.last) >= 400*time.Millisecond {
		t.flush("")
	}
}

func (t *pullTracker) finishFile(size int64) {
	if t == nil {
		return
	}
	t.base += size
	t.done = t.base
	t.state = "downloading"
	t.lastAt, t.lastN = time.Time{}, 0
	t.flush("")
}

func (t *pullTracker) verifying() {
	if t == nil {
		return
	}
	t.state = "verifying"
	t.flush("")
}

func (t *pullTracker) fail(err error) {
	if t == nil {
		return
	}
	signal.Stop(t.sigs)
	close(t.sigs)
	t.state = "failed"
	t.rate = 0
	t.flush(err.Error())
}

func (t *pullTracker) clear() {
	if t == nil {
		return
	}
	signal.Stop(t.sigs)
	close(t.sigs)
	os.Remove(pullPath(t.id))
}

type trackWriter struct {
	t   *pullTracker
	cur int64
}

func (w *trackWriter) Write(b []byte) (int, error) {
	w.cur += int64(len(b))
	w.t.bytes(w.cur)
	return len(b), nil
}

func cancelPull(id string) (int64, error) {
	id = strings.ToLower(strings.TrimSpace(id))
	if !modelIDRe.MatchString(id) {
		return 0, fmt.Errorf("invalid model id %q", id)
	}
	d := loadDownload(id)
	if d == nil {
		return 0, nil
	}
	if pullAlive(d.PID) {
		syscall.Kill(d.PID, syscall.SIGTERM)
		for i := 0; i < 50 && pullAlive(d.PID); i++ {
			time.Sleep(100 * time.Millisecond)
		}
		if pullAlive(d.PID) {
			syscall.Kill(d.PID, syscall.SIGKILL)
			time.Sleep(200 * time.Millisecond)
		}
	}
	os.Remove(pullPath(id))
	var kept int64
	if mc, err := loadModelCatalog(); err == nil {
		if m, err := mc.find(id); err == nil {
			kept = partialBytes(m)
		}
	}
	return kept, nil
}

func cmdInferDownloads(o iopts) error {
	dl := allDownloads()
	if o.json {
		emitJSON(map[string]any{"schema": 1, "downloads": dl})
		return nil
	}
	if len(dl) == 0 {
		fmt.Println("no downloads")
		return nil
	}
	ids := make([]string, 0, len(dl))
	for id := range dl {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	tw := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "ID\tSTATE\tDONE\tRATE")
	for _, id := range ids {
		d := dl[id]
		pct := 0.0
		if d.Total > 0 {
			pct = float64(d.Done) * 100 / float64(d.Total)
		}
		fmt.Fprintf(tw, "%s\t%s\t%s of %s (%s%%)\t%s/s\n", id, d.State, humanBytes(d.Done), humanBytes(d.Total), strconv.FormatFloat(pct, 'f', 1, 64), humanBytes(d.Rate))
	}
	return tw.Flush()
}
