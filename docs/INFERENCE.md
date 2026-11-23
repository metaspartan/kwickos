# Local models on KwickOS

`kwick-agents inference` (also installed as `kwick-inference`) runs open models on the machine itself and gives every agent one
endpoint:

* OpenAI-compatible: `http://127.0.0.1:11435/v1` (chat completions, responses, completions, models)
* Anthropic-compatible: `http://127.0.0.1:11435/v1/messages`
* model name `local`, which is always the model chosen with `kwick-agents inference use`
* a bearer key in the keystore as the shared key `KWICK_INFERENCE_API_KEY`, so every agent started by kwick-agents gets it as an
  environment variable; it is never written into an agent's config file or into `endpoint.json`

The engine is llama.cpp (`llama-server` in router mode), pinned in the agent catalog with a sha256 for each GPU backend. Models come
from a curated, sha256-pinned list or from any GGUF repository on Hugging Face pinned to a commit. Nothing runs until you ask: the
service is off by default.

```
kwick-agents inference install            # llama.cpp for this GPU (CUDA, Vulkan or CPU)
kwick-agents inference use best           # the best model that fits, downloaded and verified
kwick-agents inference service start      # 127.0.0.1:11435
kwick-agents inference connect --all      # point the installed agents at it
```

## Commands

```
kwick-agents inference status [--json]
kwick-agents inference doctor [--json]
kwick-agents inference gpu [--json]
kwick-agents inference install [--backend cpu|vulkan|cuda12|cuda13|rocm] [--json]
kwick-agents inference remove | update [--json]
kwick-agents inference models [--json] [--fits] [--installed] [--ctx N]
kwick-agents inference model pull ID|hf://REPO[:QUANT] | cancel ID | add hf://REPO[:QUANT] | rm ID | verify [ID]
kwick-agents inference downloads [--json]
kwick-agents inference use ID|best [--ctx N]
kwick-agents inference unload [ID] [--json]
kwick-agents inference fit ID [--ctx N] [--json]
kwick-agents inference config [--json] | config set idle-minutes N|never | config set lan on|off
kwick-agents inference bench [--json]
kwick-agents inference service enable|disable|start|stop|restart|status|logs [-n N] [-f]
kwick-agents inference connect [AGENT...|--all] | disconnect [AGENT...|--all] [--json]
kwick-agents inference endpoint [--json]
kwick-agents inference key rotate
kwick-agents run --local aider|claude-code [-- ARGS]
```

`--system` (as root) manages the engine, models and service for the whole machine instead of the calling user (see below).
`KWICK_INFERENCE_BACKEND` overrides the backend choice like `--backend`. Exit codes: 0 success, 1 failure, 2 usage error.

## Engine and backend

`install` downloads only the backend this machine needs and checks it against the catalog's sha256 before unpacking. Then it runs a
smoke test inside the same sandbox the service uses: `ldd` on `llama-server` and the backend library (any `not found` fails the install
with a hint), and `llama-server --list-devices`, whose device list is kept in the status.

| Hardware | Backend | Why |
|---|---|---|
| NVIDIA with the NVIDIA driver, CUDA 13 driver (580 or newer, or `nvidia-smi` reports CUDA 13) | `cuda13` (CUDA 13.5 build) | amd64 and arm64 (GB10) |
| NVIDIA with a CUDA 12 driver (525 to 579) | `cuda12` (CUDA 12.8 build) | amd64 only; on arm64 Vulkan |
| NVIDIA with an older driver, or nouveau | `vulkan` | NVK or the NVIDIA Vulkan driver |
| AMD | `vulkan` (RADV) | the ROCm build needs ROCm 7, which Debian 13 does not ship; `--backend rocm` when it is installed |
| Intel | `vulkan` (ANV) | |
| Apple Silicon (Asahi), Raspberry Pi | `cpu` | Vulkan is opt-in with `--backend vulkan` |
| no GPU, virtual GPU | `cpu` | |
| any GPU without a Vulkan driver (no ICD in `/usr/share/vulkan/icd.d`) | `cpu` | `kwick-gpu install` adds `mesa-vulkan-drivers` |
| riscv64 | none | llama.cpp publishes no riscv64 build |

What the release archives contain (checked with `ldd` and `objdump -p` on build b12648):

* Every archive is self-contained for llama.cpp itself (`RUNPATH $ORIGIN`): `llama-server`, `libllama`, `libggml-base` and CPU
  variants for every x86 level. They need only `libstdc++6`, `libgcc-s1` and `libgomp1` from Debian.
* **CUDA:** `libggml-cuda.so` needs `libcudart.so.13`, `libcublas.so.13` and `libcublasLt.so.13` (`.so.12` for the 12.8 build), which
  the archive does **not** contain, plus `libcuda.so.1` from the NVIDIA driver. The `cudart-llama-…` runtime pack (444 MB for 13.5
  x64, 594 MB for 12.8, 560 MB for 13.5 arm64) holds exactly those three libraries, so kwick-agents installs it into the same folder
  and `$ORIGIN` finds them. Debian 13 has no CUDA 13 runtime, so without the pack the CUDA build cannot start.
* **ROCm:** the ROCm 10.0 build bundles **no** ROCm runtime: `libggml-hip.so` (most of the 1.4 GB unpacked) needs `libamdhip64.so.7`,
  `librocblas.so.5` and `libhipblas.so.3` from the system. Debian 13 ships older ROCm libraries with other sonames, so ROCm works only
  with AMD's ROCm 7 packages; `install --backend rocm` refuses with that explanation when `ldconfig` does not list them.
* **Vulkan:** needs `libvulkan.so.1` and a Vulkan ICD from Mesa or NVIDIA.

`update` moves the engine to the build pinned in the catalog and keeps the backend. The pins come from `tools/pin-llama.sh BUILD`, which
reads the GitHub release API and writes every backend's URL, size and the `digest` sha256 into
`desktop/agents/rootfs/usr/lib/kwick/agents/catalog.json` (entry `inference`).

## Models

The curated list is `/usr/lib/kwick/agents/inference-models.json`. Every entry is pinned to a Hugging Face commit, with the size and sha256
of every file taken from the API (`/api/models/REPO?blobs=true`), the licence from the model card and `commercial_ok`. The GGUF shape
(layers, KV cache bytes per token, sliding window, experts) is stored too, so fits are known offline.

| ID | Repository | Quant | Size | Class | Licence |
|---|---|---|---|---|---|
| `qwen3.5-0.8b` | unsloth/Qwen3.5-0.8B-GGUF | Q4_K_M | 0.5 GB | tiny | Apache-2.0 |
| `qwen3.5-2b` | unsloth/Qwen3.5-2B-GGUF | Q4_K_M | 1.3 GB | tiny | Apache-2.0 |
| `gemma-4-e2b` | unsloth/gemma-4-E2B-it-GGUF | Q4_K_M | 3.1 GB | 4 GB | Apache-2.0 |
| `gemma-4-e4b` | unsloth/gemma-4-E4B-it-GGUF | Q4_K_M | 5.0 GB | 4 GB | Apache-2.0 |
| `qwen3.5-4b` | unsloth/Qwen3.5-4B-GGUF | Q4_K_M | 2.7 GB | 4 GB | Apache-2.0 |
| `qwen3.5-9b` | unsloth/Qwen3.5-9B-GGUF | Q4_K_M | 5.7 GB | 8 GB | Apache-2.0 |
| `gemma-4-12b` | google/gemma-4-12B-it-qat-q4_0-gguf | Q4_0 (QAT) | 7.0 GB | 8 GB | Apache-2.0 |
| `gpt-oss-20b` | ggml-org/gpt-oss-20b-GGUF | MXFP4 | 12.1 GB | 16 GB | Apache-2.0 |
| `gemma-4-26b-a4b` | unsloth/gemma-4-26B-A4B-it-GGUF | MXFP4_MOE | 16.6 GB | 24 GB | Apache-2.0 |
| `qwen3.5-35b-a3b` | unsloth/Qwen3.5-35B-A3B-GGUF | Q4_K_M | 22.0 GB | 24 GB | Apache-2.0 |
| `qwen3.8-27b` | unsloth/Qwen3.8-27B-GGUF | UD-Q4_K_M | 16.6 GB | 24 GB | Apache-2.0 |
| `qwen3-coder-next` | Qwen/Qwen3-Coder-Next-GGUF | Q4_K_M (4 files) | 48.4 GB | 64 GB | Apache-2.0 |
| `gpt-oss-120b` | ggml-org/gpt-oss-120b-GGUF | MXFP4 | 63.4 GB | 128 GB | Apache-2.0 |

`model pull` downloads `https://huggingface.co/REPO/resolve/COMMIT/FILE` into `FILE.part` and resumes with a Range request after an
interruption, checks free space first, verifies the sha256 of the whole file and only then renames it. `model add hf://REPO[:QUANT]`
reads the repository through the API, pins its current commit, the file sizes and LFS sha256 values and the licence, and adds it to
`~/.config/kwick-inference/models.json`; without a quant it picks Q4_K_M, Q4_K_S, MXFP4, Q4_0, IQ4_XS, Q4_1, Q5_K_M or Q8_0 in that
order. Multi-file (sharded) quants are downloaded together; projector (`mmproj`), MTP and imatrix files are skipped. `model verify`
re-hashes the files.

**Progress and cancel.** While `model pull` (or `use`, or the MCP tool) runs, it keeps `~/.local/state/kwick-agents/inference-pulls/ID.json`
up to date twice a second: bytes done and total over all files of the model, a smoothed rate in bytes per second, the start time and
the pid. `models --json` and `status --json` put it in each model as `download`, and `downloads --json` lists every active one without
computing fits, which is cheap enough to poll every second. The file is removed when the download finishes or is cancelled; a pull that
fails leaves `state: "failed"` with the error until the next pull, `model cancel` or `model rm`. A state file whose process is gone
reads as `failed` ("the download was interrupted"). `model cancel ID` stops the pull (SIGTERM, then SIGKILL after 5 seconds) and keeps
the `.part` file, so the next `pull` resumes from it; `partial_bytes` in `models --json` tells how much is there.

**Hugging Face token.** Gated and private repositories need a token. It is the shared keystore key `HF_TOKEN`
(`kwick-agents key set shared HF_TOKEN --dialog`, remove with `key rm shared HF_TOKEN`); the `HF_TOKEN` environment variable is used
when no key is stored. The token goes in an `Authorization` header of requests to `huggingface.co` only, is dropped on a redirect to
another host (the CDN), and is never logged, printed or written to `status --json` (which only has `hf_token: true|false`). Because
it is a shared key, agents started by kwick-agents get it as an environment variable like every other shared key. Without a token a
gated repository is refused with the instruction to set one; with one, `model add` accepts it when the token can see the files.

`use ID` downloads the model when needed, makes it the model `local`, writes `endpoint.json` and restarts a running service. `use best`
picks the highest-ranked curated model whose verdict is `gpu` (or `cpu` on a machine without a usable GPU; there only models marked
`cpu_ok`, which have at most about 5B active parameters, are considered), then `moe-offload`.

### Fit

```
need = weights + KV cache + 700 MB overhead        must be <= 90 % of the budget
KV   = sum over layers with attention of 2 x kv_heads x head_dim x tokens x 2 bytes (f16)
```

The GGUF header is read with Range requests (about 2-10 MB, cached in `~/.local/state/kwick-agents/gguf/`), or from the catalog. Hybrid
models (Qwen3.5, Qwen3-Next) only count their full-attention layers, sliding-window layers count at most the window, and per-layer KV head
counts and separate sliding-window head sizes (Gemma 4) are honoured. The default context is 32K (the floor for agent work) or the
model's maximum if smaller; `--ctx` changes it, and `max_ctx` reports the largest context that fits.

Memory budget (`memory_budget_mb`, also in `kwick-gpu status --json`):

* discrete GPUs of the vendor with the most VRAM: sum of their VRAM minus 1536 MB on a GPU that drives a display, 512 MB otherwise;
* unified memory (AMD APUs and Strix Halo, Apple Silicon, NVIDIA GB10, Intel integrated): VRAM + GTT, at most RAM minus the reserve;
* no usable GPU: RAM minus the reserve. The reserve is one eighth of RAM, at least 2 GB; `ram_budget_mb` is RAM minus the reserve.

| Verdict | Meaning |
|---|---|
| `gpu` | everything on the GPU (or in unified memory) |
| `moe-offload` | mixture of experts: attention, KV cache and some experts on the GPU, the other experts in RAM |
| `cpu-split` | part of the layers on the CPU (works, slower) |
| `cpu` | no usable GPU; runs on the CPU in RAM |
| `no` | does not fit at this context |

llama.cpp's own `--fit` (on by default) places layers and experts at load time; the verdict says what to expect.

## Service

`service start` writes the key file and a router preset to `$XDG_RUNTIME_DIR/kwick-agents/inference/` (mode 700), then starts
`kwick-agents inference service run`, a small supervisor that restarts `llama-server` with a back-off and gives up after 5 crashes in 2
minutes. Output goes to `~/.local/state/kwick-agents/inference.log` (`service logs`). `service enable` adds
`~/.config/autostart/kwick-inference.desktop`, so it starts at login, and starts it now; `disable` removes it and stops it.

```
llama-server --host 127.0.0.1 --port 11435 --api-key-file RUN/api-key --models-preset RUN/models.ini --models-max 1
             --models-memory-margin HEADROOM --sleep-idle-seconds 900 --no-webui
```

`config set idle-minutes N|never` (1 to 1440) and `config set lan on|off` write `~/.config/kwick-inference/config.json` and restart a
running service. `never` leaves out `--sleep-idle-seconds`. `lan on` starts `llama-server` with `--host 0.0.0.0`; the key is still
required for every endpoint except `/health` (which only says `ok`), but the traffic is plain HTTP, so it is for a network you trust.
`status --json` reports `host`, `lan` and, when on, `lan_url` (the first private IPv4 address of this machine). Checked from a second
address of the machine: without a key `/v1/models`, `/models`, `/props`, `/metrics`, `/slots`, `/v1/chat/completions` and
`/v1/messages` answer 401; with the key they work; after `lan off` the port is refused on that address.

`unload [ID]` posts to the router's `POST /models/unload` for every loaded, loading or sleeping model (or the named one; the chosen
model's id means `local`) and waits until `GET /models` shows them gone. The model loads again with the next request. It fails when the
service is not running.

`bench` runs `llama-bench` from the engine folder, in the same sandbox as the service, on the chosen model with 128 prompt tokens, 32
generated tokens and 2 repetitions. A loaded model is unloaded first, so the numbers have the whole memory to themselves. It prints
prompt and generation tokens per second, `--json` gives the result below, and the last good result is kept in
`~/.local/state/kwick-agents/inference-bench.json` and shown as `bench` in `status --json` while the same model is chosen.

* Router mode with one preset section `local` (the chosen model) and one per downloaded model, all with `load-on-startup = false`,
  `jinja = true`, `fit = on`, `c = 32768` (or `--ctx`), `fit-target = HEADROOM`.
* Idle unload: after 15 minutes without requests the model leaves memory and loads again on the next request (`idle_seconds` in
  `~/.config/kwick-inference/config.json`; set it with `config set idle-minutes`).
* VRAM headroom: 1536 MB stay free on a GPU that drives a display (512 MB otherwise), both for `--fit` and for the router's
  `--models-memory-margin`, so the desktop and games keep room.
* Sandbox: bubblewrap with all namespaces unshared except the network (the port must be reachable on the host loopback), `/usr` and `/etc`
  read-only, a private `/proc`, `/dev`, `/tmp`, `/run`, an empty `/home` and `/root`, the engine folder and the models folder read-only,
  the run folder (key and preset) read-only, and only the GPU device nodes the backend needs (`/dev/dri`, `/dev/kfd`, `/dev/nvidia*`;
  none for `cpu`). No D-Bus, no display, no home. `"sandbox": false` in the config or `KWICK_INFERENCE_NO_SANDBOX=1` turn it off.
* `~/.config/kwick-inference/endpoint.json` describes the endpoint for programs that cannot be configured (never the key).

System-wide (`--system`, as root, for servers): the engine goes to `/opt/kwick-agents`, models to `/var/lib/kwick-inference/models`, the
config and `endpoint.json` to `/etc/kwick-inference`, the key to `/etc/kwick-inference/api-key` (mode 640, group `kwick-inference`). The
kinit unit `/usr/lib/systemd/system/kwick-inference.service` runs it as the user `kwick-inference` (groups `video` and `render`); it is
disabled by default and `service enable --system` runs `systemctl enable --now kwick-inference`. `kwick-inference.service` in
`/usr/lib/systemd/user` serves the same purpose on Debian hosts that run a systemd user manager.

## Agents

`connect` writes a provider entry with the id `kwickos-local` and makes `kwickos-local/local` the default model. Every change is
idempotent and reversible: what was there before (the previous default model or provider) is recorded in
`~/.config/kwick-inference/config.json` and put back by `disconnect`. `--all` connects every installed agent except Aider and Claude Code.

| Agent | What `connect` writes | Key |
|---|---|---|
| Cybara | a provider `KwickOS local (kwickos-local)` of type `custom` through Cybara's gateway API (`POST /api/providers` on `CYBARA_API` or `http://localhost:4269`, authenticated with `~/.cybara/api_key` or `$CYBARA_API_KEY`), made the default; its models are discovered from `/v1/models` | copied into Cybara's database (Cybara has no environment reference for custom providers); `key rotate` updates it |
| opencode | `provider.kwickos-local` (`@ai-sdk/openai-compatible`) and `model` in `~/.config/opencode/opencode.json` | `{env:KWICK_INFERENCE_API_KEY}` |
| Codex | `[model_providers.kwickos-local]` (`wire_api = "responses"`, the only value Codex 0.171 accepts) and `[profiles.kwickos-local]` in `~/.codex/config.toml`; start it with `codex --profile kwickos-local` | `env_key` |
| Goose | `~/.config/goose/custom_providers/kwickos-local.json` (engine `openai`) and `GOOSE_PROVIDER`/`GOOSE_MODEL` in `config.yaml` | `api_key_env` |
| Hermes | the `model:` block of `~/.hermes/config.yaml` (`provider: custom`, `base_url`), marked with a `# kwickos-local` comment; the previous block is restored | `${KWICK_INFERENCE_API_KEY}` |
| OpenClaw | `models.providers.kwickos-local` (`api: openai-completions`) and `agents.defaults.model.primary` in `~/.openclaw/openclaw.json` (plain JSON only) | `${KWICK_INFERENCE_API_KEY}` |
| oh-my-pi | `providers.kwickos-local` in `~/.omp/agent/models.yml` and `modelRoles.default` in `~/.omp/agent/config.yml` | `apiKey: KWICK_INFERENCE_API_KEY` (a variable name) |
| Aider | nothing; `kwick-agents run --local aider` sets `OPENAI_API_BASE`, `OPENAI_API_KEY` and `AIDER_MODEL=openai/local` for that run | environment |
| Claude Code | never written to its settings; `kwick-agents run --local claude-code` prints a warning and sets `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_MODEL` and the default model variables to `local` for that run only. Anthropic does not support Claude Code with other models. | environment |

The schemas were checked against the pinned releases (opencode 1.19.6, Codex 0.171.0, Goose 1.60.2, Hermes 0.23.3, OpenClaw 2026.11.6,
oh-my-pi 19.0.1 and 19.1.0, Cybara 1.0.2596). When Cybara's gateway is not running, `connect cybara` says so and changes nothing; start it with
`cybara start` and connect again.

## kwick-mcp

| Tool | Capability | Default |
|---|---|---|
| `inference_status`, `inference_models` | `system.read` | allow |
| `inference_start`, `inference_stop`, `inference_pull` | `inference.manage` | ask |

The consent text of `inference_pull` names the model, its size, the repository and the licence and whether commercial use is allowed.
Downloads started through MCP run in the background, log to `~/.local/state/kwick-agents/inference-pull-ID.log` and show their progress in `inference_models` and `kwick-agents inference downloads`. No tool returns the
key. The resource `kwickos://docs/inference` is this document.

## Stable JSON

Schema 1. Fields are only ever added; `schema` changes if one is removed or changes meaning. Sizes are bytes unless the name ends in `_mb`.

`kwick-agents inference status --json`:

```json
{
  "schema": 1,
  "scope": "user",
  "engine": {
    "name": "llama.cpp", "pinned_build": "b12648", "installed": true, "build": "b12648", "backend": "cuda13",
    "update_available": false, "dir": "/home/u/.local/share/kwick-agents/pkgs/inference/b12648-cuda13",
    "smoke_ok": true, "devices": ["CUDA0: NVIDIA GeForce RTX 4090 (24080 MiB, 23400 MiB free)"]
  },
  "backend": {
    "recommended": "cuda13", "reason": "NVIDIA driver 590.44 supports CUDA 13", "override": "",
    "available": ["cpu", "vulkan", "cuda12", "cuda13", "rocm"], "download_size": 668557928
  },
  "hardware": {
    "arch": "amd64", "ram_mb": 64216, "memory_budget_mb": 23028, "ram_budget_mb": 56189, "vram_mb": 24564,
    "unified": false, "accelerator": "nvidia",
    "devices": [
      {"index": 0, "vendor": "nvidia", "name": "NVIDIA GeForce RTX 4090", "pci": "0000:01:00.0", "card": "card1",
       "vram_mb": 24564, "gtt_mb": 0, "compute_cap": "8.9", "driver": "nvidia", "driver_version": "590.44.01",
       "cuda_version": "13.1", "unified": false, "display": true}
    ]
  },
  "service": {
    "enabled": false, "running": true, "healthy": true, "pid": 4242,
    "url": "http://127.0.0.1:11435/v1", "anthropic_url": "http://127.0.0.1:11435", "host": "127.0.0.1", "port": 11435,
    "alias": "local", "key_env": "KWICK_INFERENCE_API_KEY", "key_set": true, "idle_seconds": 900, "vram_headroom_mb": 1536,
    "lan": false, "sandbox": true, "supervisor": "kwick-agents", "loaded": ["local"], "log": "/home/u/.local/state/kwick-agents/inference.log"
  },
  "memory": {"measured": true, "source": "nvidia-smi", "kind": "gpu", "used_mb": 9168, "total_mb": 24564, "process": true},
  "hf_token": false,
  "bench": null,
  "model": { "...": "one entry of models --json, with current true; null when no model is chosen" },
  "models": {"installed": 2, "bytes": 19294200832, "dir": "/home/u/.local/share/kwick-inference/models"},
  "endpoint_file": "/home/u/.config/kwick-inference/endpoint.json",
  "agents": [
    {"name": "cybara", "title": "Cybara", "installed": true, "supported": true, "connected": true, "method": "api",
     "file": "http://localhost:4269/api/providers", "note": "..."},
    {"name": "opencode", "title": "opencode", "installed": true, "supported": true, "connected": false, "method": "config",
     "file": "/home/u/.config/opencode/opencode.json"}
  ],
  "issues": [{"code": "no-model", "message": "no model selected (kwick-agents inference use best)"}]
}
```

`agents` lists cybara, opencode, codex, goose, hermes, openclaw, omp, aider and claude-code in that order; `method` is `api`, `config` or
`run --local`. Issue codes: `catalog`, `backend`, `backend-mismatch`, `engine-missing`, `model-missing`, `model-too-big`, `no-model`,
`models-catalog`, `service-down`. `pid` is 0 and `loaded` empty when the service is stopped. `idle_seconds` is 0 when the model never
leaves memory on its own. `host` is `0.0.0.0` and `lan_url` is set while `lan` is true.

`memory` is null unless the service runs (and always for `--system`). When it is measured, `used_mb` is what the model's processes
(the service's children, which include the router's model instances) hold, and `total_mb` is the device or memory budget it is
compared with; `used_mb` is 0 while no model is loaded. `process` is false when only the whole device could be read.

| `source` | `kind` | How |
|---|---|---|
| `nvidia-smi` | `gpu` | `--query-compute-apps=pid,used_memory` summed over the model's pids; when the driver lists none (Vulkan on NVIDIA) the whole GPU from `--query-gpu=memory.used,memory.total` |
| `amdgpu-fdinfo` | `gpu` | `drm-memory-vram` and `drm-memory-gtt` of the model's DRM file descriptors in `/proc/PID/fdinfo` |
| `amdgpu-sysfs` | `gpu` | `mem_info_vram_used` (plus `mem_info_gtt_used` on unified memory) of the AMD GPUs, whole device |
| `process-rss` | `ram` | resident memory of the model's processes with the CPU backend |

Without one of these (Intel GPUs, or a machine without `nvidia-smi`) `memory` is null and the estimate in `model.fit` is all there is; llama-server's `/metrics` has no memory figures. `hf_token` is true when the key `HF_TOKEN` (or the
environment variable) is set; the value is never in any output. `bench` is the last good `bench` result for the chosen model.

`kwick-agents inference models --json`:

```json
{
  "schema": 1,
  "current": "qwen3.8-27b",
  "models_dir": "/home/u/.local/share/kwick-inference/models",
  "budget": {"memory_budget_mb": 23028, "ram_budget_mb": 56189, "vram_mb": 24564, "unified": false, "accelerator": "nvidia"},
  "models": [
    {
      "id": "qwen3.8-27b", "title": "Qwen3.8 27B", "family": "qwen3.8", "class": "24gb", "description": "...",
      "repo": "unsloth/Qwen3.8-27B-GGUF", "commit": "4af51b3542f775b0a8e4b310bfb3f17e01c306c9", "quant": "UD-Q4_K_M",
      "files": [{"name": "Qwen3.8-27B-UD-Q4_K_M.gguf", "size": 16564259744, "sha256": "1bce50..."}],
      "license": "apache-2.0", "license_url": "https://huggingface.co/unsloth/Qwen3.8-27B-GGUF", "commercial_ok": true,
      "params_b": 27.32, "active_params_b": 27.32, "rank": 85, "tags": ["chat", "tools", "code"], "source": "catalog",
      "size": 16564259744, "moe": false, "context_max": 262144,
      "installed": true, "verified": true, "current": true, "recommended": true, "download": null,
      "fit": {
        "verdict": "gpu", "ctx": 32768, "max_ctx": 65536, "weights_mb": 15787, "kv_mb": 2048, "overhead_mb": 700,
        "need_mb": 18535, "budget_mb": 23028, "gpu_mb": 18535, "cpu_mb": 0, "reason": "fits in 22.5 GB of VRAM with 32K context"
      }
    }
  ]
}
```

`download` is null, or while a model is being pulled (or its last pull failed)
`{"state": "downloading"|"verifying"|"failed", "done": 1182793728, "total": 16564259744, "rate": 18874368, "started": "2026-11-23T05:00:00Z", "pid": 4242, "error": "..."}`
(`error` only for `failed`; `rate` is bytes per second and 0 unless `downloading`; `done` and `total` cover all files of the model).
`partial_bytes` appears on a model that is not installed but has `.part` files, so a pull resumes. `source` is `catalog` or `hf` (added with `model add`). `cpu_ok` is present for models that run well on a CPU. `fit` is null and
`fit_error` says why when the shape is unknown (a model added from Hugging Face that was never read). `cpu_moe` is true for
`moe-offload`. `--installed` and `--fits` filter the list; `--ctx` changes the context of every fit.

`kwick-agents inference fit ID --json`: `{"schema":1,"id","shape":{"arch","layers","context_max","kv_bytes_per_token","swa_kv_bytes_per_token","sliding_window","experts","experts_used","weights_bytes","expert_bytes","params_b"},"fit":{...},"hardware":{...}}`.

`kwick-agents inference gpu --json`: `{"schema":1,"hardware":{...}}` as in status.

`~/.config/kwick-inference/endpoint.json` (also `endpoint --json`):

```json
{
  "schema": 1, "url": "http://127.0.0.1:11435/v1", "anthropic_url": "http://127.0.0.1:11435", "model": "local",
  "model_id": "qwen3.8-27b", "key_env": "KWICK_INFERENCE_API_KEY",
  "key_source": "kwick-agents keystore, shared key KWICK_INFERENCE_API_KEY (given to every agent kwick-agents starts)",
  "context": 32768, "openai_compatible": true, "anthropic_compatible": true, "engine": "llama.cpp", "updated": "2026-11-23T05:00:00Z"
}
```

`kwick-agents inference downloads --json`: `{"schema":1,"downloads":{"qwen3.8-27b":{"state","done","total","rate","started","pid","error"}}}`, only models with a state file.
`model cancel ID --json`: `{"schema":1,"ok":true,"id","kept_bytes"}`. `unload --json`: `{"schema":1,"ok":true,"unloaded":["local"]}`.
`config --json`: `{"schema":1,"config":{"idle_seconds","idle_minutes","lan","host","port","ctx","model","lan_url"}}` (`config set ... --json` adds `ok`).

`kwick-agents inference bench --json`:

```json
{"schema": 1, "ok": true, "model": "qwen3.5-0.8b", "engine": "b12648", "backend": "cuda13", "devices": "CUDA: NVIDIA GeForce RTX 4090",
 "prompt_tokens": 128, "gen_tokens": 32, "prompt_tps": 8431.2, "gen_tps": 301.4, "seconds": 6.2, "at": "2026-11-23T05:00:00Z", "error": ""}
```

`ok` is false with `error` when llama-bench fails (exit code 1); only good results are kept for `status`.

Other JSON: `install --json` (`{"schema":1,"ok","engine":{"build","backend","dir","installed_at","smoke_ok","devices","smoke_error"},"error"}`),
`update --json` (`{"schema":1,"updated":[{"name","from","to","scope","ok","backend","error"}]}`), `doctor --json` (`{"schema":1,"ok","checks":[{"name","ok","detail"}]}`),
`connect --json` (`{"schema":1,"agents":[{"name","ok","file","error"}]}`), `service status --json` (`{"schema":1,"service":{...}}`),
`model add --json` (`{"schema":1,"model":{...}}`).

## Files

| Path | What |
|---|---|
| `~/.local/share/kwick-agents/pkgs/inference/BUILD-BACKEND/` | llama.cpp and, for CUDA, the runtime pack |
| `~/.local/state/kwick-agents/inference.json` | installed build, backend and smoke test result |
| `~/.local/share/kwick-inference/models/ID/` | model files and `manifest.json` (`KWICK_INFERENCE_MODELS_DIR` moves it) |
| `~/.local/state/kwick-agents/inference-pulls/ID.json` | progress of a running or failed download |
| `~/.local/state/kwick-agents/inference-bench.json` | last good `bench` result |
| `~/.config/kwick-inference/config.json` | chosen model, context, backend override, port, idle time (`idle_seconds`, -1 = never), `lan`, sandbox, connected agents |
| `~/.config/kwick-inference/models.json` | models added from Hugging Face |
| `~/.config/kwick-inference/endpoint.json` | endpoint description for other programs |
| `$XDG_RUNTIME_DIR/kwick-agents/inference/` | `api-key`, `models.ini`, `pid` while the service runs |
| `~/.local/state/kwick-agents/inference.log` | service log (rotated at 5 MB) |
| `/usr/lib/kwick/agents/inference-models.json` | curated models |

## Not yet

Phase 2: vLLM and SGLang for CUDA 13 and ROCm servers, a UNIX socket with a Go reverse proxy (Host check, per-request audit, network
namespace for llama-server), tensor parallelism and a GB10 profile. Phase 3: riscv64 and Asahi builds, RPC across machines, SYCL and
OpenVINO, embeddings and speech, sharing over a tailnet or with TLS (LAN access is plain HTTP with the key). `endpoint add` (external
endpoints) from the design is not in phase 1.
