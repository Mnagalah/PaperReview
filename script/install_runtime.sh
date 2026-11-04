#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="${PAPERREVIEW_MODEL_HOME:-$ROOT/.local-models}"
mkdir -p "$HOME_DIR/runtime"
if [[ -f "$HOME_DIR/runtime.path" ]] && [[ -x "$(cat "$HOME_DIR/runtime.path")" ]]; then exit 0; fi
ARCHIVE="$HOME_DIR/runtime/llama-b11960-bin-macos-arm64.tar.gz"
curl --fail --silent --show-error --http1.1 --location --retry 5 --retry-all-errors --connect-timeout 30 --output "$ARCHIVE.part" 'https://github.com/ggml-org/llama.cpp/releases/download/b11960/llama-b11960-bin-macos-arm64.tar.gz'
mv "$ARCHIVE.part" "$ARCHIVE"
tar -xzf "$ARCHIVE" -C "$HOME_DIR/runtime"
SERVER="$(find "$HOME_DIR/runtime" -type f -name llama-server -print -quit)"
[[ -n "$SERVER" ]] || { echo 'llama-server not found' >&2; exit 1; }
printf '%s\n' "$SERVER" > "$HOME_DIR/runtime.path"
echo 'Installed official llama.cpp b11960 runtime.'
