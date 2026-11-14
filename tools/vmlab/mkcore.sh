#!/bin/bash
set -euo pipefail
IN=${1:?legacy shader}; OUT=${2:?core shader}
{
  echo '#version 140'
  sed -e '1{/KWIN_LEGACY/d}' -e 's/^varying vec2 texcoord0;/in vec2 texcoord0;\nout vec4 fragColor;/' -e 's/texture2D/texture/g' -e 's/gl_FragColor/fragColor/g' "$IN"
} > "$OUT"
