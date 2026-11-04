#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="${PAPERREVIEW_MODEL_HOME:-$ROOT/.local-models}"
mkdir -p "$HOME_DIR/weights" "$HOME_DIR/run"
source "$SCRIPT_DIR/download_file.sh"
pids=()
while IFS=$'\t' read -r id label relative suffix expected url; do
  [[ "$id" != runtime ]] || continue
  download_file "$id" "$label" "$relative" "$suffix" "$expected" "$url" & pids+=("$!")
done < "$SCRIPT_DIR/model_downloads.tsv"
failed=0
for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
[[ "$failed" == 0 ]] || exit 1
PAPERREVIEW_MODEL_HOME="$HOME_DIR" /bin/bash "$SCRIPT_DIR/install_runtime.sh"
printf 'OCR F16 + Jev Q4 + MiniCPM5-2B Q4 + llama.cpp b11960\n' > "$HOME_DIR/models-ready"
printf 'MiniCPM-OCR-1_0-F16.gguf\n' > "$HOME_DIR/ocr-model"
echo 'Local models ready (unquantized OCR F16).'
