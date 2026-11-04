#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="${PAPERREVIEW_MODEL_HOME:-$ROOT/.local-models}"
mkdir -p "$HOME_DIR/weights" "$HOME_DIR/run"
fetch() {
  local repo="$1" remote="$2" name="$3" expected="$4" dest="$HOME_DIR/weights/$3"
  if [[ -f "$dest" ]] && [[ "$(wc -c < "$dest" | tr -d ' ')" == "$expected" ]]; then echo "Already present: $name"; return; fi
  # Different source gets its own partial; never append bytes to a Hugging Face partial.
  local partial="$dest.modelscope.part"
  for attempt in 1 2 3 4 5 6; do
    echo "ModelScope: $name (attempt $attempt)"
    if curl --fail --silent --show-error --http1.1 --location --connect-timeout 30 --speed-time 120 --speed-limit 8192 --continue-at - --output "$partial" "https://modelscope.cn/models/OpenBMB/$repo/resolve/master/$remote"; then
      actual="$(wc -c < "$partial" | tr -d ' ')"
      if [[ "$actual" == "$expected" ]]; then mv "$partial" "$dest"; echo "Complete: $name"; return; fi
      echo "Unexpected size $actual for $name (expected $expected)" >&2; return 1
    fi
    sleep "$attempt"
  done
  echo "Download incomplete: $name; partial retained." >&2; return 1
}
fetch MiniCPM-OCR-1.0-gguf MiniCPM-OCR-1_0-F16.gguf MiniCPM-OCR-1_0-F16.gguf 1516288352 & p1=$!
fetch MiniCPM-OCR-1.0-gguf mmproj-model-f16-4x.gguf ocr-mmproj-f16-4x.gguf 901017536 & p2=$!
fetch MiniCPM-OCR-Jev-gguf MiniCPM-OCR-Jev-Q4_K_M.gguf MiniCPM-OCR-Jev-Q4_K_M.gguf 1274405248 & p3=$!
fetch MiniCPM-OCR-Jev-gguf mmproj-model-f16.gguf jev-mmproj-f16.gguf 671372416 & p4=$!
fetch MiniCPM5-2B-GGUF MiniCPM5-2B-Q4_K_M.gguf MiniCPM5-2B-Q4_K_M.gguf 1561318368 & p5=$!
failed=0
for pid in "$p1" "$p2" "$p3" "$p4" "$p5"; do wait "$pid" || failed=1; done
[[ "$failed" == 0 ]] || exit 1
"$ROOT/script/install_runtime.sh"
printf 'OCR F16 + Jev Q4 + MiniCPM5-2B Q4 + llama.cpp b11960\n' > "$HOME_DIR/models-ready"
printf 'MiniCPM-OCR-1_0-F16.gguf\n' > "$HOME_DIR/ocr-model"
echo 'Local models ready (unquantized OCR F16).'
