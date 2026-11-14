inference_arch() { echo "amd64 arm64 riscv64"; }
inference_desc() { echo "KwickOS multi-GPU inference engine (coming later)"; }
inference_state() { echo na; }
inference_why() { echo "not available yet"; }

inference_install() {
  say "inference: not available yet"
  return 1
}

inference_remove() {
  say "inference: not available yet"
  return 0
}
