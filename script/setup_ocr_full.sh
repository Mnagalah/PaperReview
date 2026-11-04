#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="${PAPERREVIEW_MODEL_HOME:-$ROOT/.local-models}"
DEST="$HOME_DIR/weights/MiniCPM-OCR-1_0-F16.gguf"
EXPECTED=1516288352
mkdir -p "$HOME_DIR/weights"
if [[ -f "$DEST" ]] && [[ "$(wc -c < "$DEST" | tr -d ' ')" == "$EXPECTED" ]]; then echo 'Full-precision OCR F16 already present.'; exit 0; fi
for attempt in 1 2 3 4 5; do
  echo "Downloading official unquantized OCR F16 (attempt $attempt)"
  if curl --fail --silent --show-error --http1.1 --location --connect-timeout 30 --speed-time 120 --speed-limit 8192 --continue-at - --output "$DEST.modelscope.part" 'https://modelscope.cn/models/OpenBMB/MiniCPM-OCR-1.0-gguf/resolve/master/MiniCPM-OCR-1_0-F16.gguf'; then
    actual="$(wc -c < "$DEST.modelscope.part" | tr -d ' ')"
    [[ "$actual" == "$EXPECTED" ]] || { echo "Unexpected size: $actual" >&2; exit 1; }
    mv "$DEST.modelscope.part" "$DEST"
    printf 'MiniCPM-OCR-1_0-F16.gguf\n' > "$HOME_DIR/ocr-model"
    echo 'Official full-precision OCR F16 ready.'; exit 0
  fi
  sleep "$attempt"
done
exit 1
