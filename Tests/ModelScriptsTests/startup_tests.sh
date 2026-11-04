#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/script/start_models.sh"
LOG="$(mktemp "${TMPDIR:-/tmp/}PaperReview-startup.XXXXXX")"
trap 'rm -f "$LOG"' EXIT
printf 'runtime diagnostic\n' > "$LOG"

# These doubles exercise the real startup decision, without touching live
# models, ports, or student work. Health HTTP/body handling is checked separately.
is_owned() { return 0; }
process_alive() { return 0; }
sleep() { :; }
model_healthy() { return 0; }
output="$(wait_ready ocr 18499 123 "$LOG")"
[[ "$output" == *'已就绪'* ]]

model_healthy() { checks=$((checks + 1)); [[ "$checks" -ge 2 ]]; }
checks=0
output="$(wait_ready ocr 18499 123 "$LOG")"
[[ "$output" == *'已就绪'* ]]

model_healthy() { return 1; }
if output="$(wait_ready ocr 18499 123 "$LOG" 2>&1)"; then
  echo 'FAIL: a running but unready process was accepted' >&2; exit 1
fi
[[ "$output" == *'等待超时'* && "$output" == *'runtime diagnostic'* && "$output" != *'已就绪'* ]]

process_alive() { return 1; }
model_healthy() { echo 'FAIL: health must not be queried after process exit' >&2; exit 9; }
if output="$(wait_ready ocr 18499 123 "$LOG" 2>&1)"; then
  echo 'FAIL: an exited process was accepted' >&2; exit 1
fi
[[ "$output" == *'启动后已退出'* && "$output" == *'runtime diagnostic'* && "$output" != *'已就绪'* ]]

# Re-source the actual health function after the process-state doubles.
source "$ROOT/script/start_models.sh"
curl() { printf '{"status":"ok"}'; }
model_healthy 18499
curl() { printf '{ "status" : "loading" }'; }
if model_healthy 18499; then echo 'FAIL: loading was accepted' >&2; exit 1; fi
curl() { printf '{"status":"error"}'; return 22; }
if model_healthy 18499; then echo 'FAIL: HTTP failure was accepted' >&2; exit 1; fi
curl() { printf '<html>not a model</html>'; }
if model_healthy 18499; then echo 'FAIL: unrelated HTTP 200 was accepted' >&2; exit 1; fi

# Exercise the new-process branch as well as the already-running branch. In
# Bash, an unbraced variable next to Chinese punctuation can become another name.
(
  HOME_DIR="$(mktemp -d "${TMPDIR:-/tmp/}PaperReview-cold-start.XXXXXX")"
  mkdir "$HOME_DIR/run"
  trap 'rm -f "$HOME_DIR/run/cold.pid" "$HOME_DIR/run/cold.log"; rmdir "$HOME_DIR/run" "$HOME_DIR"' EXIT
  SERVER='/fixture/llama-server'
  lsof() { return 1; }
  nohup() { :; }
  wait_ready() { echo 'readiness checked'; }
  output="$(start cold 18377)"
  [[ "$output" == *'正在加载 cold；日志'* && "$output" == *'readiness checked'* ]]
)
echo 'PASS: ready, loading timeout, process exit, health body, HTTP failure, and cold-start branch'
