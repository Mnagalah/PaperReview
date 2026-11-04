#!/bin/bash
set -euo pipefail
is_owned() {
  local pid="$1" port="$2"
  [[ "$pid" =~ ^[0-9]+$ ]] && ps -p "$pid" -o command= | grep -F -- "$SERVER" | grep -Fq -- "--port $port"
}

model_healthy() {
  local response
  response="$(curl --silent --fail --noproxy '*' --connect-timeout 1 --max-time 2 "http://127.0.0.1:$1/health")" || return 1
  printf '%s' "$response" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"ok"'
}

process_alive() { kill -0 "$1" 2>/dev/null; }

wait_ready() {
  local name="$1" port="$2" pid="$3" log="$4" attempt
  for ((attempt = 0; attempt < 120; attempt++)); do
    if ! process_alive "$pid"; then
      echo "$name 服务启动后已退出。请查看：$log" >&2
      tail -n 12 "$log" >&2
      return 1
    fi
    # A just-forked process may not have exec'd llama-server yet. Require the
    # expected command as well as health, but don't mistake that for an exit.
    if is_owned "$pid" "$port" && model_healthy "$port"; then
      echo "$name 已就绪：127.0.0.1:$port (PID $pid)"
      return 0
    fi
    sleep 1
  done
  echo "$name 服务尚未就绪，等待超时。请查看：$log" >&2
  tail -n 12 "$log" >&2
  return 1
}

start() {
  local name="$1" port="$2"; shift 2
  local pidfile="$HOME_DIR/run/$name.pid"
  if [[ -f "$pidfile" ]]; then
    local old; old="$(cat "$pidfile")"
    if is_owned "$old" "$port"; then
      if [[ "$name" != "ocr" ]] || ps -p "$old" -o command= | grep -Fq -- "$WEIGHTS/$OCR_FILE"; then
        wait_ready "$name" "$port" "$old" "$HOME_DIR/run/$name.log"
        return
      fi
      # Model precision changed: only replace this project's verified OCR process.
      cp "$HOME_DIR/run/ocr.log" "$HOME_DIR/run/ocr-before-f16.log"
      kill -TERM "$old"
      for _ in 1 2 3 4 5; do if ! kill -0 "$old" 2>/dev/null; then break; fi; sleep 1; done
    fi
  fi
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "端口 $port 已被其他服务占用；未停止或替换它。" >&2; exit 1
  fi
  nohup "$SERVER" --host 127.0.0.1 --port "$port" -ngl 99 --parallel 1 "$@" > "$HOME_DIR/run/$name.log" 2>&1 < /dev/null &
  echo "$!" > "$pidfile"
  echo "正在加载 ${name}；日志 $HOME_DIR/run/$name.log"
  wait_ready "$name" "$port" "$(cat "$pidfile")" "$HOME_DIR/run/$name.log"
}

main() {
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  HOME_DIR="${PAPERREVIEW_MODEL_HOME:-$ROOT/.local-models}"
  [[ -f "$HOME_DIR/models-ready" && -f "$HOME_DIR/runtime.path" ]] || { echo '请先运行 script/setup_models.sh 下载模型。' >&2; return 1; }
  SERVER="$(cat "$HOME_DIR/runtime.path")"
  [[ -x "$SERVER" ]] || { echo "运行时不存在：$SERVER" >&2; return 1; }
  WEIGHTS="$HOME_DIR/weights"
  mkdir -p "$HOME_DIR/run"
  OCR_FILE="MiniCPM-OCR-1_0-F16.gguf"
  [[ -f "$WEIGHTS/$OCR_FILE" ]] || { echo '未量化 OCR F16 尚未下载完成。请运行 script/setup_ocr_full.sh。' >&2; return 1; }
  start ocr 18499 -m "$WEIGHTS/$OCR_FILE" --mmproj "$WEIGHTS/ocr-mmproj-f16-4x.gguf" --alias minicpm-ocr --flash-attn on --jinja --reasoning off -c 8192
  start jev 18500 -m "$WEIGHTS/MiniCPM-OCR-Jev-Q4_K_M.gguf" --mmproj "$WEIGHTS/jev-mmproj-f16.gguf" -c 32768
  start review 18501 -m "$WEIGHTS/MiniCPM5-2B-Q4_K_M.gguf" --alias MiniCPM5-2B --jinja -c 8192
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
