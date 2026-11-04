#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="${PAPERREVIEW_MODEL_HOME:-$ROOT/.local-models}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/download_file.sh"
mkdir -p "$HOME_DIR/runtime"
if [[ -f "$HOME_DIR/runtime.path" ]] && [[ -x "$(cat "$HOME_DIR/runtime.path")" ]]; then
  download_event runtime complete 0 '已有运行时'; exit 0
fi
while IFS=$'\t' read -r id label relative suffix expected url; do
  [[ "$id" == runtime ]] || continue
  download_file "$id" "$label" "$relative" "$suffix" "$expected" "$url"
  ARCHIVE="$HOME_DIR/$relative"
done < "$SCRIPT_DIR/model_downloads.tsv"
download_event runtime installing 0 '正在安装运行时'
tar -xzf "$ARCHIVE" -C "$HOME_DIR/runtime"
SERVER="$(find "$HOME_DIR/runtime" -type f -name llama-server -print -quit)"
[[ -n "$SERVER" ]] || { echo 'llama-server not found' >&2; exit 1; }
printf '%s\n' "$SERVER" > "$HOME_DIR/runtime.path"
echo 'Installed official llama.cpp b11960 runtime.'
download_event runtime complete 0 ''
