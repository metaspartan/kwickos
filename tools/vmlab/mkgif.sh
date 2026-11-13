#!/bin/bash
set -euo pipefail
PREFIX=${1:?frame prefix}; OUT=${2:?out gif}; FPS=${3:-10}; WIDTH=${4:-800}; MAXMB=${5:-4}
F="fps=$FPS,scale=$WIDTH:-1:flags=lanczos"
for colors in 128 96 64 48 32; do
  ffmpeg -v error -y -framerate "$FPS" -i "${PREFIX}%04d.${EXT:-png}" -vf "$F,split[a][b];[a]palettegen=max_colors=$colors[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" "$OUT"
  SZ=$(stat -c %s "$OUT")
  [ "$SZ" -le $((MAXMB * 1024 * 1024)) ] && break
done
gifsicle -O3 --batch "$OUT" 2>/dev/null || true
ls -l "$OUT"
