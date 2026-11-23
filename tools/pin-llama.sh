#!/bin/sh
set -eu
BUILD=${1:-}
case $BUILD in
  b[0-9]*) ;;
  *) echo "usage: tools/pin-llama.sh BUILD [CATALOG]   (BUILD is a llama.cpp release tag such as b12648)" >&2; exit 2 ;;
esac
HERE=$(cd "$(dirname "$0")" && pwd)
CAT=${2:-$HERE/../desktop/agents/rootfs/usr/lib/kwick/agents/catalog.json}
command -v python3 >/dev/null || { echo "pin-llama.sh needs python3" >&2; exit 1; }
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
if [ -n "${GITHUB_TOKEN:-}" ]; then
  curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -o "$TMP" "https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/$BUILD"
else
  curl -fsSL -o "$TMP" "https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/$BUILD"
fi
python3 -I - "$TMP" "$CAT" "$BUILD" <<'EOF'
import datetime
import json
import re
import sys

rel_path, cat_path, build = sys.argv[1:4]
rel = json.load(open(rel_path, encoding="utf-8"))
if rel.get("tag_name") != build:
    sys.exit("release tag mismatch: %r" % rel.get("tag_name"))
assets = {a["name"]: a for a in rel["assets"]}
b = re.escape(build)
plan = {
    "cpu": {"amd64": (r"llama-%s-bin-ubuntu-x64\.tar\.gz" % b, None),
            "arm64": (r"llama-%s-bin-ubuntu-arm64\.tar\.gz" % b, None)},
    "vulkan": {"amd64": (r"llama-%s-bin-ubuntu-vulkan-x64\.tar\.gz" % b, None),
               "arm64": (r"llama-%s-bin-ubuntu-vulkan-arm64\.tar\.gz" % b, None)},
    "cuda12": {"amd64": (r"llama-%s-bin-ubuntu-cuda-12\.[0-9]+-x64\.tar\.gz" % b, r"cudart-llama-%s-bin-ubuntu-cuda-12\.[0-9]+-x64\.tar\.gz" % b),
               "arm64": (r"llama-%s-bin-ubuntu-cuda-12\.[0-9]+-arm64\.tar\.gz" % b, r"cudart-llama-%s-bin-ubuntu-cuda-12\.[0-9]+-arm64\.tar\.gz" % b)},
    "cuda13": {"amd64": (r"llama-%s-bin-ubuntu-cuda-13\.[0-9]+-x64\.tar\.gz" % b, r"cudart-llama-%s-bin-ubuntu-cuda-13\.[0-9]+-x64\.tar\.gz" % b),
               "arm64": (r"llama-%s-bin-ubuntu-cuda-13\.[0-9]+-arm64\.tar\.gz" % b, r"cudart-llama-%s-bin-ubuntu-cuda-13\.[0-9]+-arm64\.tar\.gz" % b)},
    "rocm": {"amd64": (r"llama-%s-bin-ubuntu-rocm-[0-9.]+-x64\.tar\.gz" % b, None)},
}


def pick(pattern):
    hits = sorted(n for n in assets if re.fullmatch(pattern, n))
    if not hits:
        return None
    a = assets[hits[-1]]
    digest = a.get("digest") or ""
    if not digest.startswith("sha256:") or len(digest) != 71:
        sys.exit("%s has no sha256 digest in the release API" % a["name"])
    return {"url": a["browser_download_url"], "sha256": digest[7:], "size": a["size"], "format": "tar.gz", "strip": 1}


backends = {}
for name, arches in plan.items():
    for arch, (main, runtime) in arches.items():
        m = pick(main)
        if m is None:
            continue
        if runtime:
            r = pick(runtime)
            if r is None:
                sys.stderr.write("warning: %s %s has no runtime pack, skipped\n" % (name, arch))
                continue
            m["runtime"] = r
        backends.setdefault(name, {})[arch] = m
        sys.stderr.write("%-7s %-5s %s\n" % (name, arch, m["url"].rsplit("/", 1)[1]))
for need in ("cpu",):
    if need not in backends:
        sys.exit("no %s build in %s" % (need, build))

entry = {
    "name": "inference",
    "title": "Local models (llama.cpp)",
    "kind": "local-models",
    "vendor": "ggml-org; packaged by KwickOS",
    "description": "Local AI models on one OpenAI- and Anthropic-compatible endpoint (127.0.0.1:11435) for every agent: llama.cpp for CUDA, ROCm, Vulkan or CPU, curated models that fit this machine",
    "homepage": "https://github.com/ggml-org/llama.cpp",
    "source": "https://github.com/ggml-org/llama.cpp",
    "license": "MIT",
    "version": build,
    "released": rel["published_at"][:10],
    "method": "inference",
    "arch": ["amd64", "arm64"],
    "backends": backends,
    "gpu": True,
    "network": False,
    "mcp": "none",
    "ports": [11435],
    "unsupported": {"riscv64": "llama.cpp publishes no riscv64 build; build it from source"},
    "verify": "sha256 pinned by KwickOS for each backend archive and CUDA runtime pack; equal to the GitHub release asset digests (tools/pin-llama.sh)",
    "upstream_install": "download a release archive from GitHub; no install script",
    "first_run": "kwick-agents inference use best, then kwick-agents inference service start",
    "notes": "Only the backend this machine needs is downloaded: CUDA 13 or 12 for NVIDIA (with NVIDIA's cudart and cuBLAS runtime pack), Vulkan for AMD and Intel, CPU otherwise; ROCm (needs the ROCm 7 runtime) is opt-in. Managed with kwick-agents inference.",
}

text = open(cat_path, encoding="utf-8").read()
key = '"name": "inference"'
at = text.find(key)
if at < 0:
    sys.exit("no inference entry in %s" % cat_path)
start = text.rfind("{", 0, at)
dec = json.JSONDecoder()
old, end = dec.raw_decode(text, start)
line_start = text.rfind("\n", 0, start) + 1
indent = text[line_start:start]
body = json.dumps(entry, indent=2, ensure_ascii=False)
body = body.replace("\n", "\n" + indent)
text = text[:start] + body + text[end:]
today = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
text = re.sub(r'("updated":\s*")[0-9-]+(")', lambda m: m.group(1) + today + m.group(2), text, count=1)
json.loads(text)
with open(cat_path, "w", encoding="utf-8", newline="\n") as f:
    f.write(text)
sys.stderr.write("pinned llama.cpp %s in %s\n" % (build, cat_path))
EOF
