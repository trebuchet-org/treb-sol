#!/usr/bin/env bash
set -euo pipefail

cmd="${1:?missing command}"
name="${2:?missing name}"
port="${3:?missing port}"
runtime_dir="${4:?missing runtime dir}"

mkdir -p "$runtime_dir"

pid_file="$runtime_dir/${name}-${port}.pid"
log_file="$runtime_dir/${name}-${port}.log"

stop_node() {
  if [[ -f "$pid_file" ]]; then
    pid="$(cat "$pid_file")"
    kill "$pid" 2>/dev/null || true
    rm -f "$pid_file"
  fi
}

case "$cmd" in
  start)
    fork_url="${5:?missing fork url}"
    chain_id="${6:-}"
    fork_block="${7:-}"

    stop_node

    args=(anvil --host 127.0.0.1 --port "$port" --fork-url "$fork_url")
    if [[ -n "$chain_id" && "$chain_id" != "0" ]]; then
      args+=(--chain-id "$chain_id")
    fi
    if [[ -n "$fork_block" && "$fork_block" != "0" ]]; then
      args+=(--fork-block-number "$fork_block")
    fi

    nohup "${args[@]}" >"$log_file" 2>&1 &
    pid=$!
    echo "$pid" >"$pid_file"
    parent_pid="$PPID"

    (
      while kill -0 "$parent_pid" 2>/dev/null && kill -0 "$pid" 2>/dev/null; do
        sleep 1
      done
      kill "$pid" 2>/dev/null || true
      rm -f "$pid_file"
    ) >/dev/null 2>&1 &

    for _ in $(seq 1 100); do
      if (echo >/dev/tcp/127.0.0.1/"$port") >/dev/null 2>&1; then
        echo "$pid"
        exit 0
      fi
      sleep 0.1
    done

    echo "failed to start anvil on port $port" >&2
    exit 1
    ;;
  stop)
    stop_node
    echo "stopped"
    ;;
  status)
    if [[ -f "$pid_file" ]]; then
      pid="$(cat "$pid_file")"
      if kill -0 "$pid" 2>/dev/null; then
        echo "$pid"
        exit 0
      fi
      rm -f "$pid_file"
    fi
    exit 1
    ;;
  *)
    echo "unknown command: $cmd" >&2
    exit 1
    ;;
esac
