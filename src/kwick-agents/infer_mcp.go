package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
)

const inferenceDocURI = "kwickos://docs/inference"

func init() {
	capabilities = append(capabilities, capInfo{"inference.manage", "ask", "Start and stop the local model endpoint and download models", false})
}

func inferenceTools() []tool {
	return []tool{
		{Name: "inference_status", Title: "Local models status", Cap: "system.read", ReadOnly: true,
			Description: "The local inference endpoint (llama.cpp): engine and backend, GPUs and memory budget, whether the service runs, the model served as \"local\" and connected agents. The API key itself is never returned; agents get it as $KWICK_INFERENCE_API_KEY.",
			fn:          toolInferStatus},
		{Name: "inference_models", Title: "Local models", Cap: "system.read", ReadOnly: true,
			Description: "Curated local models with size, licence, whether they are downloaded and whether they fit this machine (gpu, moe-offload, cpu-split, cpu or no).",
			Schema:      obj(map[string]any{"fits_only": map[string]any{"type": "boolean"}, "ctx": map[string]any{"type": "integer", "minimum": 0, "maximum": 1048576}}),
			fn:          toolInferModels},
		{Name: "inference_start", Title: "Start the local endpoint", Cap: "inference.manage",
			Description: "Start the local endpoint on http://127.0.0.1:11435/v1 with the selected model (or choose one with model).",
			Schema:      obj(map[string]any{"model": str("Model id from inference_models; empty keeps the current one")}),
			fn:          toolInferStart, precheck: inferModelCheck, detail: func(s *Server, a map[string]any) string {
				if m := argStr(a, "model"); m != "" {
					return "Start the local model endpoint with " + m
				}
				return "Start the local model endpoint"
			}},
		{Name: "inference_stop", Title: "Stop the local endpoint", Cap: "inference.manage",
			Description: "Stop the local endpoint and free the GPU memory.",
			fn:          toolInferStop, detail: func(s *Server, a map[string]any) string { return "Stop the local model endpoint" }},
		{Name: "inference_pull", Title: "Download a local model", Cap: "inference.manage",
			Description: "Download a curated model (sha256 verified) in the background. The user sees its size and licence before agreeing.",
			Schema:      obj(map[string]any{"model": str("Model id from inference_models")}, "model"),
			fn:          toolInferPull, precheck: inferModelCheck, detail: pullDetail},
	}
}

func inferModelCheck(s *Server, a map[string]any) error {
	id := argStr(a, "model")
	if id == "" {
		return nil
	}
	mc, err := loadModelCatalog()
	if err != nil {
		return err
	}
	_, err = mc.find(id)
	return err
}

func pullDetail(s *Server, a map[string]any) string {
	id := argStr(a, "model")
	mc, err := loadModelCatalog()
	if err != nil {
		return "Download the local model " + id
	}
	m, err := mc.find(id)
	if err != nil {
		return "Download the local model " + id
	}
	com := "commercial use allowed"
	if !m.CommercialOK {
		com = "check whether commercial use is allowed"
	}
	return fmt.Sprintf("Download the local model %s (%s, %s from huggingface.co/%s); licence %s, %s", m.ID, m.Title, humanBytes(m.size()), m.Repo, m.License, com)
}

func toolInferStatus(s *Server, a map[string]any) (toolResult, error) {
	return toolResult{Data: buildStatus()}, nil
}

func toolInferModels(s *Server, a map[string]any) (toolResult, error) {
	mc, err := loadModelCatalog()
	if err != nil {
		return toolResult{}, err
	}
	cfg := loadInferConfig()
	hw := detectHardware()
	items := modelItems(mc, hw, int64(argInt(a, "ctx", 0)), cfg, false)
	if fo, _ := a["fits_only"].(bool); fo {
		var out []ModelItem
		for _, it := range items {
			if it.Fit != nil && it.Fit.Verdict != "no" {
				out = append(out, it)
			}
		}
		items = out
	}
	return toolResult{Data: map[string]any{"current": cfg.Model, "memory_budget_mb": hw.MemoryBudgetMB, "models": items}}, nil
}

func selfCommand(args ...string) *exec.Cmd {
	c := exec.Command(selfExe(), args...)
	c.Env = os.Environ()
	return c
}

func toolInferStart(s *Server, a map[string]any) (toolResult, error) {
	if m := argStr(a, "model"); m != "" {
		mc, err := loadModelCatalog()
		if err != nil {
			return toolResult{}, err
		}
		me, err := mc.find(m)
		if err != nil {
			return toolResult{}, err
		}
		if inst, _ := installedModel(me); !inst {
			return toolResult{}, fmt.Errorf("%s is not downloaded (%s); download it first with inference_pull", me.ID, humanBytes(me.size()))
		}
		out, err := selfCommand("inference", "use", m).CombinedOutput()
		if err != nil {
			return toolResult{}, fmt.Errorf("%s", lastLines(string(out), 4))
		}
	}
	cfg := loadInferConfig()
	if serviceRunning() {
		return toolResult{Text: fmt.Sprintf("The local endpoint runs at %s/v1 with %s as model %q.", cfg.baseURL(), cfg.Model, inferAlias)}, nil
	}
	out, err := selfCommand("inference", "service", "start").CombinedOutput()
	if err != nil {
		return toolResult{}, fmt.Errorf("could not start the endpoint: %s", lastLines(string(out), 4))
	}
	return toolResult{Text: fmt.Sprintf("Started: %s/v1 (OpenAI) and %s/v1/messages (Anthropic), model %q = %s. The key is in $%s.", cfg.baseURL(), cfg.baseURL(), inferAlias, cfg.Model, inferKeyEnv)}, nil
}

func toolInferStop(s *Server, a map[string]any) (toolResult, error) {
	if !serviceRunning() {
		return toolResult{Text: "The local endpoint is not running."}, nil
	}
	if err := stopService(); err != nil {
		return toolResult{}, err
	}
	return toolResult{Text: "The local endpoint was stopped."}, nil
}

func toolInferPull(s *Server, a map[string]any) (toolResult, error) {
	id := argStr(a, "model")
	mc, err := loadModelCatalog()
	if err != nil {
		return toolResult{}, err
	}
	m, err := mc.find(id)
	if err != nil {
		return toolResult{}, err
	}
	if inst, ver := installedModel(m); inst && ver {
		return toolResult{Text: m.ID + " is already downloaded and verified."}, nil
	}
	logp := filepath.Join(userScope().State, "inference-pull-"+m.ID+".log")
	os.MkdirAll(filepath.Dir(logp), 0o755)
	lf, err := os.OpenFile(logp, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
	if err != nil {
		return toolResult{}, err
	}
	defer lf.Close()
	c := selfCommand("inference", "model", "pull", m.ID)
	devnull, _ := os.Open(os.DevNull)
	c.Stdin, c.Stdout, c.Stderr = devnull, lf, lf
	c.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := c.Start(); err != nil {
		return toolResult{}, err
	}
	c.Process.Release()
	return toolResult{Text: fmt.Sprintf("Downloading %s (%s) in the background; progress in %s. inference_models shows it as installed when the sha256 is verified.", m.ID, humanBytes(m.size()), logp)}, nil
}

func inferenceDocResource() map[string]any {
	var b []byte
	var err error
	for _, p := range []string{"/usr/share/doc/kwick-agents/INFERENCE.md", "/usr/share/doc/kwickos/INFERENCE.md"} {
		if b, err = os.ReadFile(p); err == nil {
			break
		}
	}
	if err != nil {
		b = []byte("Local models on KwickOS: kwick-agents inference status|models|use ID|service start. Endpoint http://127.0.0.1:11435/v1, model \"local\", key in $KWICK_INFERENCE_API_KEY.")
	}
	return map[string]any{"contents": []map[string]any{{"uri": inferenceDocURI, "mimeType": "text/markdown", "text": string(b)}}}
}
