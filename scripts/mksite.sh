#!/bin/bash
# Landing page for https://metaspartan.github.io/kwickos/ (the apt repo root).
set -euo pipefail
S=${1:?site dir}
cat > "$S/index.html" <<EOF
<!doctype html><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
<title>KwickOS</title>
<style>body{font:16px/1.5 system-ui;max-width:46rem;margin:3rem auto;padding:0 1rem;background:#0f1020;color:#e7e7f4}
pre{background:#1b1c33;padding:1rem;border-radius:8px;overflow:auto}a{color:#8ab4ff}</style>
<h1>KwickOS</h1>
<p>Tiny, fast, Debian-compatible Linux. This site is the signed apt repository for KwickOS kernels and the desktop edition.
Downloads and docs: <a href="https://github.com/metaspartan/kwickos">github.com/metaspartan/kwickos</a>.</p>
<p>Already running KwickOS? The repository is preconfigured. Upgrade to the desktop edition with:</p>
<pre>apt update && apt install kwick-desktop</pre>
<p>Manual setup:</p>
<pre>curl -fsSL https://metaspartan.github.io/kwickos/kwickos-archive-keyring.asc -o /usr/share/keyrings/kwickos-archive-keyring.asc
printf 'Types: deb\nURIs: https://metaspartan.github.io/kwickos\nSuites: stable\nComponents: main\nSigned-By: /usr/share/keyrings/kwickos-archive-keyring.asc\n' &gt; /etc/apt/sources.list.d/kwickos.sources</pre>
EOF
cp "$S/index.html" "$S/404.html"