#!/bin/bash

# One newline-delimited event per write, also when downloads run in parallel.
download_event() {
  local message="${4:-}"
  message="${message//$'\n'/ }"; message="${message//$'\t'/ }"; message="${message//$'\r'/ }"
  printf 'PR_DOWNLOAD\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$message"
}

download_file() {
  local id="$1" label="$2" relative="$3" suffix="$4" expected="$5" url="$6"
  local dest="$HOME_DIR/$relative" partial="$HOME_DIR/$relative$suffix" actual attempt code message http_status
  mkdir -p "$(dirname "$dest")" "$HOME_DIR/run"
  if [[ -f "$dest" && "$(wc -c < "$dest" | tr -d ' ')" == "$expected" ]]; then
    download_event "$id" complete 0 '已有完整文件'; return
  fi
  # A previous process may have finished the transfer before renaming the file.
  if [[ -f "$partial" && "$(wc -c < "$partial" | tr -d ' ')" == "$expected" ]]; then
    mv "$partial" "$dest"; download_event "$id" complete 0 '已续传完成'; return
  fi
  if [[ -f "$partial" && "$(wc -c < "$partial" | tr -d ' ')" -gt "$expected" ]]; then
    mv "$partial" "$partial.invalid-$(date +%Y%m%d-%H%M%S)-$$"
  fi
  for attempt in 1 2 3 4 5 6; do
    download_event "$id" downloading "$attempt" ''
    code=0
    http_status="$(curl --fail --silent --show-error --http1.1 --location --connect-timeout 30 \
      --speed-time 30 --speed-limit 1 --continue-at - --output "$partial" "$url" \
      --write-out '%{http_code}' 2> "$HOME_DIR/run/download-$id.error")" || code=$?
    if [[ "$code" == 0 ]]; then
      actual="$(wc -c < "$partial" | tr -d ' ')"
      if [[ "$actual" == "$expected" ]]; then
        mv "$partial" "$dest"; download_event "$id" complete "$attempt" ''; return
      fi
      message="文件不完整（$actual / $expected 字节）"
    else
      case "$code" in
        6) message='无法解析下载地址';;
        7) message='无法连接下载服务器';;
        18) message='下载连接中断';;
        22) message="服务器返回 HTTP $http_status";;
        28) message='下载连接超时';;
        33) message='服务器未接受续传请求';;
        35|60) message="安全连接失败（$code）";;
        *) message="网络请求失败（$code）：$(cat "$HOME_DIR/run/download-$id.error")";;
      esac
    fi
    if [[ "$attempt" != 6 ]]; then
      download_event "$id" retrying "$attempt" "$message"
      sleep "$attempt"
    fi
  done
  download_event "$id" failed "$attempt" "$message"
  return 1
}
