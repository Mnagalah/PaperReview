#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp/}PaperReview-portable-setup.XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/Resources" "$FIXTURE/models/weights" "$FIXTURE/bin"
cp "$ROOT/script/setup_models_modelscope.sh" "$ROOT/script/install_runtime.sh" "$FIXTURE/Resources/"
printf '#!/bin/sh\nexit 0\n' > "$FIXTURE/server"
chmod +x "$FIXTURE/server"
printf '%s\n' "$FIXTURE/server" > "$FIXTURE/models/runtime.path"
printf '#!/bin/sh\necho "Unexpected network request" >&2\nexit 99\n' > "$FIXTURE/bin/curl"
chmod +x "$FIXTURE/bin/curl"
while read -r name size; do mkfile -n "$size" "$FIXTURE/models/weights/$name"; done <<'FILES'
MiniCPM-OCR-1_0-F16.gguf 1516288352
ocr-mmproj-f16-4x.gguf 901017536
MiniCPM-OCR-Jev-Q4_K_M.gguf 1274405248
jev-mmproj-f16.gguf 671372416
MiniCPM5-2B-Q4_K_M.gguf 1561318368
FILES
PATH="$FIXTURE/bin:$PATH" PAPERREVIEW_MODEL_HOME="$FIXTURE/models" /bin/bash "$FIXTURE/Resources/setup_models_modelscope.sh"
[[ -f "$FIXTURE/models/models-ready" ]]
[[ "$(cat "$FIXTURE/models/ocr-model")" == 'MiniCPM-OCR-1_0-F16.gguf' ]]
echo 'PASS: bundled companion scripts and cached-file setup work without a checkout or network'
