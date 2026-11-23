package main

import (
	"bufio"
	"encoding/binary"
	"fmt"
	"io"
	"math"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"
)

type ggufTensor struct {
	Name   string
	Type   uint32
	Dims   []uint64
	Offset uint64
}

type ggufFile struct {
	Version    uint32
	KV         map[string]any
	Tensors    []ggufTensor
	DataOffset int64
}

type countingReader struct {
	r *bufio.Reader
	n int64
}

func (c *countingReader) Read(p []byte) (int, error) {
	n, err := c.r.Read(p)
	c.n += int64(n)
	return n, err
}

const ggufMaxString = 1 << 24
const ggufMaxArray = 1 << 26

func ggufReadString(r io.Reader) (string, error) {
	var n uint64
	if err := binary.Read(r, binary.LittleEndian, &n); err != nil {
		return "", err
	}
	if n > ggufMaxString {
		return "", fmt.Errorf("gguf: string of %d bytes", n)
	}
	b := make([]byte, n)
	_, err := io.ReadFull(r, b)
	return string(b), err
}

func ggufScalarSize(t uint32) int {
	switch t {
	case 0, 1, 7:
		return 1
	case 2, 3:
		return 2
	case 4, 5, 6:
		return 4
	case 10, 11, 12:
		return 8
	}
	return 0
}

func ggufReadScalar(r io.Reader, t uint32) (any, error) {
	var b [8]byte
	n := ggufScalarSize(t)
	if n == 0 {
		return nil, fmt.Errorf("gguf: unknown value type %d", t)
	}
	if _, err := io.ReadFull(r, b[:n]); err != nil {
		return nil, err
	}
	le := binary.LittleEndian
	switch t {
	case 0:
		return int64(b[0]), nil
	case 1:
		return int64(int8(b[0])), nil
	case 2:
		return int64(le.Uint16(b[:])), nil
	case 3:
		return int64(int16(le.Uint16(b[:]))), nil
	case 4:
		return int64(le.Uint32(b[:])), nil
	case 5:
		return int64(int32(le.Uint32(b[:]))), nil
	case 6:
		return float64(math.Float32frombits(le.Uint32(b[:]))), nil
	case 7:
		return b[0] != 0, nil
	case 10:
		return int64(le.Uint64(b[:])), nil
	case 11:
		return int64(le.Uint64(b[:])), nil
	case 12:
		return math.Float64frombits(le.Uint64(b[:])), nil
	}
	return nil, fmt.Errorf("gguf: unknown value type %d", t)
}

func ggufReadValue(r io.Reader, t uint32, keep bool) (any, error) {
	switch t {
	case 8:
		return ggufReadString(r)
	case 9:
		var et uint32
		var n uint64
		if err := binary.Read(r, binary.LittleEndian, &et); err != nil {
			return nil, err
		}
		if err := binary.Read(r, binary.LittleEndian, &n); err != nil {
			return nil, err
		}
		if n > ggufMaxArray {
			return nil, fmt.Errorf("gguf: array of %d values", n)
		}
		if et == 8 {
			for i := uint64(0); i < n; i++ {
				var l uint64
				if err := binary.Read(r, binary.LittleEndian, &l); err != nil {
					return nil, err
				}
				if l > ggufMaxString {
					return nil, fmt.Errorf("gguf: string of %d bytes", l)
				}
				if _, err := io.CopyN(io.Discard, r, int64(l)); err != nil {
					return nil, err
				}
			}
			return []any{}, nil
		}
		sz := ggufScalarSize(et)
		if sz == 0 {
			return nil, fmt.Errorf("gguf: unsupported array type %d", et)
		}
		if !keep || n > 4096 {
			_, err := io.CopyN(io.Discard, r, int64(n)*int64(sz))
			return []any{}, err
		}
		out := make([]any, 0, n)
		for i := uint64(0); i < n; i++ {
			v, err := ggufReadScalar(r, et)
			if err != nil {
				return nil, err
			}
			out = append(out, v)
		}
		return out, nil
	}
	return ggufReadScalar(r, t)
}

func parseGGUF(src io.Reader) (*ggufFile, error) {
	cr := &countingReader{r: bufio.NewReaderSize(src, 1<<20)}
	var magic [4]byte
	if _, err := io.ReadFull(cr, magic[:]); err != nil {
		return nil, err
	}
	if string(magic[:]) != "GGUF" {
		return nil, fmt.Errorf("not a GGUF file")
	}
	g := &ggufFile{KV: map[string]any{}}
	var nt, nkv uint64
	if err := binary.Read(cr, binary.LittleEndian, &g.Version); err != nil {
		return nil, err
	}
	if g.Version < 2 || g.Version > 3 {
		return nil, fmt.Errorf("unsupported GGUF version %d", g.Version)
	}
	binary.Read(cr, binary.LittleEndian, &nt)
	if err := binary.Read(cr, binary.LittleEndian, &nkv); err != nil {
		return nil, err
	}
	if nt > 1<<20 || nkv > 1<<20 {
		return nil, fmt.Errorf("gguf: implausible header (%d tensors, %d keys)", nt, nkv)
	}
	for i := uint64(0); i < nkv; i++ {
		k, err := ggufReadString(cr)
		if err != nil {
			return nil, err
		}
		var t uint32
		if err := binary.Read(cr, binary.LittleEndian, &t); err != nil {
			return nil, err
		}
		keep := !strings.HasPrefix(k, "tokenizer.")
		v, err := ggufReadValue(cr, t, keep)
		if err != nil {
			return nil, fmt.Errorf("gguf key %s: %v", k, err)
		}
		if keep {
			g.KV[k] = v
		}
	}
	for i := uint64(0); i < nt; i++ {
		name, err := ggufReadString(cr)
		if err != nil {
			return nil, err
		}
		var nd uint32
		if err := binary.Read(cr, binary.LittleEndian, &nd); err != nil {
			return nil, err
		}
		if nd > 8 {
			return nil, fmt.Errorf("gguf: tensor %s has %d dimensions", name, nd)
		}
		t := ggufTensor{Name: name, Dims: make([]uint64, nd)}
		for j := range t.Dims {
			binary.Read(cr, binary.LittleEndian, &t.Dims[j])
		}
		binary.Read(cr, binary.LittleEndian, &t.Type)
		if err := binary.Read(cr, binary.LittleEndian, &t.Offset); err != nil {
			return nil, err
		}
		g.Tensors = append(g.Tensors, t)
	}
	align := int64(32)
	if a, ok := g.KV["general.alignment"].(int64); ok && a > 0 {
		align = a
	}
	g.DataOffset = (cr.n + align - 1) / align * align
	return g, nil
}

func (g *ggufFile) str(k string) string {
	s, _ := g.KV[k].(string)
	return s
}

func (g *ggufFile) num(k string) (int64, bool) {
	switch v := g.KV[k].(type) {
	case int64:
		return v, true
	case float64:
		return int64(v), true
	case bool:
		if v {
			return 1, true
		}
		return 0, true
	}
	return 0, false
}

func (g *ggufFile) perLayer(k string, n int) ([]int64, bool) {
	out := make([]int64, n)
	switch v := g.KV[k].(type) {
	case []any:
		if len(v) == 0 {
			return nil, false
		}
		for i := range out {
			x := v[len(v)-1]
			if i < len(v) {
				x = v[i]
			}
			switch y := x.(type) {
			case int64:
				out[i] = y
			case float64:
				out[i] = int64(y)
			case bool:
				if y {
					out[i] = 1
				}
			}
		}
		return out, true
	}
	if x, ok := g.num(k); ok {
		for i := range out {
			out[i] = x
		}
		return out, true
	}
	return nil, false
}

type ModelShape struct {
	Arch          string  `json:"arch"`
	Layers        int     `json:"layers"`
	ContextMax    int64   `json:"context_max"`
	KVPerTokenB   int64   `json:"kv_bytes_per_token"`
	SWAPerTokenB  int64   `json:"swa_kv_bytes_per_token,omitempty"`
	SlidingWindow int64   `json:"sliding_window,omitempty"`
	Experts       int64   `json:"experts,omitempty"`
	ExpertsUsed   int64   `json:"experts_used,omitempty"`
	WeightsB      int64   `json:"weights_bytes"`
	ExpertB       int64   `json:"expert_bytes,omitempty"`
	ParamsB       float64 `json:"params_b,omitempty"`
}

func shapeFromGGUF(gs []*ggufFile, sizes []int64) (ModelShape, error) {
	if len(gs) == 0 {
		return ModelShape{}, fmt.Errorf("no GGUF header")
	}
	g := gs[0]
	arch := g.str("general.architecture")
	if arch == "" {
		return ModelShape{}, fmt.Errorf("GGUF has no general.architecture")
	}
	s := ModelShape{Arch: arch}
	n, _ := g.num(arch + ".block_count")
	s.Layers = int(n)
	s.ContextMax, _ = g.num(arch + ".context_length")
	s.Experts, _ = g.num(arch + ".expert_count")
	s.ExpertsUsed, _ = g.num(arch + ".expert_used_count")
	emb, _ := g.num(arch + ".embedding_length")
	heads, okH := g.perLayer(arch+".attention.head_count", s.Layers)
	kvh, okKV := g.perLayer(arch+".attention.head_count_kv", s.Layers)
	if !okKV {
		kvh, okKV = heads, okH
	}
	kl, okK := g.num(arch + ".attention.key_length")
	vl, okV := g.num(arch + ".attention.value_length")
	if (!okK || !okV) && okH && heads[0] > 0 {
		kl, vl = emb/heads[0], emb/heads[0]
	}
	if !okK && okV {
		kl = vl
	}
	if !okV && okK {
		vl = kl
	}
	if mla, ok := g.num(arch + ".attention.kv_lora_rank"); ok && mla > 0 {
		rope, _ := g.num(arch + ".rope.dimension_count")
		for i := range kvh {
			kvh[i] = 1
		}
		kl, vl = mla+rope, 0
	}
	s.SlidingWindow, _ = g.num(arch + ".attention.sliding_window")
	swa := make([]bool, s.Layers)
	if s.SlidingWindow > 0 {
		if pat, ok := g.KV[arch+".attention.sliding_window_pattern"].([]any); ok && len(pat) > 0 {
			for i := range swa {
				if b, ok := pat[i%len(pat)].(bool); ok {
					swa[i] = b
				}
			}
		} else if p, ok := g.num(arch + ".attention.sliding_window_pattern"); ok && p > 1 {
			for i := range swa {
				swa[i] = (i+1)%int(p) != 0
			}
		} else if arch == "gpt-oss" {
			for i := range swa {
				swa[i] = i%2 == 0
			}
		}
	}
	full := make([]bool, s.Layers)
	for i := range full {
		full[i] = true
	}
	fi, ok := g.num(arch + ".full_attention_interval")
	if !ok && arch == "qwen3next" {
		fi, ok = 4, true
	}
	if ok && fi > 1 {
		for i := range full {
			full[i] = (i+1)%int(fi) == 0
		}
	}
	kls, okKS := g.num(arch + ".attention.key_length_swa")
	vls, okVS := g.num(arch + ".attention.value_length_swa")
	if !okKS {
		kls = kl
	}
	if !okVS {
		vls = vl
	}
	if okKV {
		for i := 0; i < s.Layers; i++ {
			if !full[i] || kvh[i] == 0 {
				continue
			}
			if swa[i] {
				s.SWAPerTokenB += kvh[i] * (kls + vls) * 2
			} else {
				b := kvh[i] * (kl + vl) * 2
				s.KVPerTokenB += b
			}
		}
	}
	for i, gf := range gs {
		var size int64
		if i < len(sizes) {
			size = sizes[i]
		}
		ts := append([]ggufTensor{}, gf.Tensors...)
		sort.Slice(ts, func(a, b int) bool { return ts[a].Offset < ts[b].Offset })
		dataLen := size - gf.DataOffset
		for j, t := range ts {
			var tb int64
			if j+1 < len(ts) {
				tb = int64(ts[j+1].Offset - t.Offset)
			} else if dataLen > 0 {
				tb = dataLen - int64(t.Offset)
			} else {
				tb = ggmlTensorBytes(t)
			}
			if tb < 0 {
				tb = ggmlTensorBytes(t)
			}
			s.WeightsB += tb
			if strings.Contains(t.Name, "_exps") {
				s.ExpertB += tb
			}
			var p int64 = 1
			for _, d := range t.Dims {
				p *= int64(d)
			}
			s.ParamsB += float64(p) / 1e9
		}
	}
	s.ParamsB = math.Round(s.ParamsB*100) / 100
	return s, nil
}

var ggmlBlocks = map[uint32][2]int64{
	0: {1, 4}, 1: {1, 2}, 2: {32, 18}, 3: {32, 20}, 6: {32, 22}, 7: {32, 24}, 8: {32, 34}, 9: {32, 36},
	10: {256, 84}, 11: {256, 110}, 12: {256, 144}, 13: {256, 176}, 14: {256, 210}, 15: {256, 292},
	16: {256, 66}, 17: {256, 74}, 18: {256, 98}, 19: {256, 50}, 20: {32, 18}, 21: {256, 110}, 22: {256, 82},
	23: {256, 136}, 24: {1, 1}, 25: {1, 2}, 26: {1, 4}, 27: {1, 8}, 28: {1, 8}, 29: {256, 56}, 30: {1, 2},
	34: {256, 54}, 35: {256, 66}, 39: {32, 17},
}

func ggmlTensorBytes(t ggufTensor) int64 {
	var n int64 = 1
	for _, d := range t.Dims {
		n *= int64(d)
	}
	b, ok := ggmlBlocks[t.Type]
	if !ok {
		return n / 2
	}
	return n / b[0] * b[1]
}

type rangeReader struct {
	url   string
	off   int64
	buf   []byte
	chunk int64
	limit int64
	size  int64
}

func (r *rangeReader) Read(p []byte) (int, error) {
	if len(r.buf) == 0 {
		if r.off >= r.limit {
			return 0, fmt.Errorf("GGUF header is larger than %d MB", r.limit>>20)
		}
		var b []byte
		var err error
		for attempt := 0; attempt < 4; attempt++ {
			if attempt > 0 {
				time.Sleep(time.Duration(attempt) * time.Second)
			}
			b, err = r.fetch()
			if err == nil {
				break
			}
		}
		if err != nil {
			return 0, err
		}
		if len(b) == 0 {
			return 0, io.EOF
		}
		r.buf = b
		r.off += int64(len(b))
		r.chunk *= 2
		if r.chunk > 16<<20 {
			r.chunk = 16 << 20
		}
	}
	n := copy(p, r.buf)
	r.buf = r.buf[n:]
	return n, nil
}

func (r *rangeReader) fetch() ([]byte, error) {
	req, err := http.NewRequest("GET", r.url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "kwick-agents/"+version)
	req.Header.Set("Range", fmt.Sprintf("bytes=%d-%d", r.off, r.off+r.chunk-1))
	c := &http.Client{Timeout: 120 * time.Second}
	resp, err := c.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 206 {
		return nil, fmt.Errorf("%s: range request returned %s", r.url, resp.Status)
	}
	if cr := resp.Header.Get("Content-Range"); cr != "" {
		if i := strings.LastIndex(cr, "/"); i >= 0 {
			r.size, _ = strconv.ParseInt(cr[i+1:], 10, 64)
		}
	}
	return io.ReadAll(io.LimitReader(resp.Body, r.chunk))
}

func remoteGGUF(url string) (*ggufFile, int64, error) {
	rr := &rangeReader{url: url, chunk: 2 << 20, limit: 96 << 20}
	g, err := parseGGUF(rr)
	return g, rr.size, err
}

func localGGUF(path string) (*ggufFile, int64, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, 0, err
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		return nil, 0, err
	}
	g, err := parseGGUF(f)
	return g, st.Size(), err
}

type Fit struct {
	Verdict    string `json:"verdict"`
	Ctx        int64  `json:"ctx"`
	MaxCtx     int64  `json:"max_ctx"`
	WeightsMB  int64  `json:"weights_mb"`
	KVMB       int64  `json:"kv_mb"`
	OverheadMB int64  `json:"overhead_mb"`
	NeedMB     int64  `json:"need_mb"`
	BudgetMB   int64  `json:"budget_mb"`
	GPUMB      int64  `json:"gpu_mb"`
	CPUMB      int64  `json:"cpu_mb"`
	CPUMoE     bool   `json:"cpu_moe,omitempty"`
	Reason     string `json:"reason"`
}

const (
	fitOverheadMB = 700
	fitCtxFloor   = 32768
)

func kvBytes(s ModelShape, ctx int64) int64 {
	swaTok := ctx
	if s.SlidingWindow > 0 && s.SlidingWindow < ctx {
		swaTok = s.SlidingWindow
	}
	return s.KVPerTokenB*ctx + s.SWAPerTokenB*swaTok
}

func mb(b int64) int64 { return (b + (1<<20 - 1)) >> 20 }

func ctxLabel(n int64) string {
	if n >= 1024 && n%1024 == 0 {
		return strconv.FormatInt(n/1024, 10) + "K"
	}
	return strconv.FormatInt(n, 10)
}

func gbLabel(m int64) string {
	return strconv.FormatFloat(float64(m)/1024, 'f', 1, 64) + " GB"
}

func computeFit(s ModelShape, hw Hardware, ctx int64) Fit {
	if ctx <= 0 {
		ctx = fitCtxFloor
		if s.ContextMax > 0 && s.ContextMax < ctx {
			ctx = s.ContextMax
		}
	}
	f := Fit{Ctx: ctx, OverheadMB: fitOverheadMB, WeightsMB: mb(s.WeightsB), KVMB: mb(kvBytes(s, ctx))}
	f.NeedMB = f.WeightsMB + f.KVMB + f.OverheadMB
	usable := func(m int64) int64 { return m * 9 / 10 }
	gpu := hw.Accelerator != "cpu" && hw.Accelerator != ""
	f.BudgetMB = hw.MemoryBudgetMB
	maxCtx := func(room int64) int64 {
		if room <= 0 {
			return 0
		}
		lo, hi := int64(0), s.ContextMax
		if hi <= 0 {
			hi = 1 << 20
		}
		for lo < hi {
			mid := (lo + hi + 1) / 2
			if mb(kvBytes(s, mid)) <= room {
				lo = mid
			} else {
				hi = mid - 1
			}
		}
		return lo / 1024 * 1024
	}
	switch {
	case gpu && f.NeedMB <= usable(hw.MemoryBudgetMB):
		f.Verdict = "gpu"
		f.GPUMB = f.NeedMB
		f.MaxCtx = maxCtx(usable(hw.MemoryBudgetMB) - f.WeightsMB - f.OverheadMB)
		where := "VRAM"
		if hw.Unified {
			where = "unified memory"
		}
		f.Reason = fmt.Sprintf("fits in %s of %s with %s context", gbLabel(hw.MemoryBudgetMB), where, ctxLabel(ctx))
	case !gpu && f.NeedMB <= usable(hw.RAMBudgetMB):
		f.Verdict = "cpu"
		f.CPUMB = f.NeedMB
		f.BudgetMB = hw.RAMBudgetMB
		f.MaxCtx = maxCtx(usable(hw.RAMBudgetMB) - f.WeightsMB - f.OverheadMB)
		f.Reason = fmt.Sprintf("runs on the CPU in %s of RAM with %s context", gbLabel(hw.RAMBudgetMB), ctxLabel(ctx))
	case gpu && !hw.Unified && s.Experts > 0 && s.ExpertB > 0 &&
		f.NeedMB-mb(s.ExpertB) <= usable(hw.MemoryBudgetMB) && f.NeedMB <= usable(hw.MemoryBudgetMB)+usable(hw.RAMBudgetMB):
		f.Verdict = "moe-offload"
		f.CPUMoE = true
		f.GPUMB = usable(hw.MemoryBudgetMB)
		f.CPUMB = f.NeedMB - f.GPUMB
		f.BudgetMB = hw.MemoryBudgetMB + hw.RAMBudgetMB
		f.MaxCtx = maxCtx(usable(hw.MemoryBudgetMB) - (f.NeedMB - f.KVMB - mb(s.ExpertB)))
		f.Reason = fmt.Sprintf("mixture of experts: attention, %s context and some experts on the GPU, %s of expert weights in RAM", ctxLabel(ctx), gbLabel(f.CPUMB))
	case gpu && !hw.Unified && f.NeedMB <= usable(hw.MemoryBudgetMB)+usable(hw.RAMBudgetMB):
		f.Verdict = "cpu-split"
		f.GPUMB = usable(hw.MemoryBudgetMB)
		f.CPUMB = f.NeedMB - f.GPUMB
		f.BudgetMB = hw.MemoryBudgetMB + hw.RAMBudgetMB
		f.MaxCtx = maxCtx(usable(hw.MemoryBudgetMB) + usable(hw.RAMBudgetMB) - f.WeightsMB - f.OverheadMB)
		f.Reason = fmt.Sprintf("needs %s: %s on the GPU, the rest of the layers on the CPU (slower)", gbLabel(f.NeedMB), gbLabel(f.GPUMB))
	default:
		f.Verdict = "no"
		lim := hw.MemoryBudgetMB
		if gpu && !hw.Unified {
			lim += hw.RAMBudgetMB
		} else if !gpu {
			lim = hw.RAMBudgetMB
			f.BudgetMB = lim
		}
		f.Reason = fmt.Sprintf("needs %s with %s context; this machine has %s for models", gbLabel(f.NeedMB), ctxLabel(ctx), gbLabel(lim))
	}
	if f.MaxCtx > s.ContextMax && s.ContextMax > 0 {
		f.MaxCtx = s.ContextMax
	}
	return f
}

func cmdInferFit(o iopts, pos []string) error {
	if len(pos) != 1 {
		return fmt.Errorf("usage: kwick-agents inference fit ID [--ctx N] [--json]")
	}
	mc, err := loadModelCatalog()
	if err != nil {
		return err
	}
	m, err := mc.find(pos[0])
	if err != nil {
		return err
	}
	hw := detectHardware()
	sh, err := modelShape(m)
	if err != nil {
		return err
	}
	f := computeFit(sh, hw, int64(o.ctx))
	if o.json {
		emitJSON(map[string]any{"schema": 1, "id": m.ID, "shape": sh, "fit": f, "hardware": hw})
		return nil
	}
	fmt.Printf("%s: %s\n", m.ID, f.Verdict)
	fmt.Printf("  %s\n", f.Reason)
	fmt.Printf("  weights %d MB + KV cache %d MB (%s context) + overhead %d MB = %d MB; budget %d MB (90%% usable)\n", f.WeightsMB, f.KVMB, ctxLabel(f.Ctx), f.OverheadMB, f.NeedMB, f.BudgetMB)
	if f.MaxCtx > 0 {
		fmt.Printf("  largest context that fits: %s\n", ctxLabel(f.MaxCtx))
	}
	return nil
}
