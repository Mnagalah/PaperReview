#!/bin/bash
# A fresh non-interactive worker inherits its own job group. Closing the app's
# stdin pipe stops only that group, including every curl and runtime installer.
set -uo pipefail
set -m
worker=''
watcher=''
stop_worker() {
  [[ -n "$worker" ]] || return 0
  kill -TERM -- "-$worker" 2>/dev/null || return 0
  for _ in {1..40}; do
    kill -0 -- "-$worker" 2>/dev/null || return 0
    sleep 0.05
  done
  kill -KILL -- "-$worker" 2>/dev/null || true
}
stop_watcher() {
  if [[ -n "$watcher" ]]; then
    kill -TERM -- "-$watcher" 2>/dev/null || true
    wait "$watcher" 2>/dev/null || true
  fi
}
trap 'stop_worker; stop_watcher; exit 143' TERM INT HUP
/bin/bash "$1" < /dev/null &
worker=$!
printf 'PR_DOWNLOAD_SESSION\t%s\n' "$worker"
{
  IFS= read -r _ || true
  stop_worker
} <&0 &
watcher=$!
wait "$worker"
result=$?
stop_worker
stop_watcher
exit "$result"
