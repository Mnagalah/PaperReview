#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME_DIR="${PAPERREVIEW_MODEL_HOME:-$ROOT/.local-models}"
[[ -f "$HOME_DIR/runtime.path" ]] || exit 0
SERVER="$(cat "$HOME_DIR/runtime.path")"
for name in ocr jev review; do
  case "$name" in ocr) port=18499;; jev) port=18500;; review) port=18501;; esac
  pidfile="$HOME_DIR/run/$name.pid"
  [[ -f "$pidfile" ]] || continue
  pid="$(cat "$pidfile")"
  if [[ "$pid" =~ ^[0-9]+$ ]] && ps -p "$pid" -o command= | grep -F -- "$SERVER" | grep -Fq -- "--port $port"; then
    kill -TERM "$pid"
    echo "已停止 $name (PID $pid)"
  else
    echo "$name 的 PID 已失效或属于其他进程；未发送信号。"
  fi
done
