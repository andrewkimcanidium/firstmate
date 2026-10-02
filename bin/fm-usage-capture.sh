#!/usr/bin/env bash
# Usage: fm-usage-capture.sh <hook> <home> <task> <stop|teardown> [store]
# USAGE_AXI_HOOK is an opt-in executable path, like the fleet ledger's file gate.
# Call only beside existing turn-ended signals or cleaned_up ledger calls.
# No wait, no propagated status, no capture-owned Firstmate lock: the background
# child closes inherited descriptors before running the hook with nohup and all
# stdio redirected. Even a broken/slow hook cannot hold the caller open.
# Hook startup/output failures go to <home>/state/usage-capture.err; usage-axi
# owns capture-failures.log and capture-hook.err in its store.
set +e
hook=${1:-}
[ -x "$hook" ] || exit 0
home=$2 task=$3 trigger=$4
(
  trap '' HUP
  # /dev/fd is available on both supported macOS and Linux platforms.
  for path in /dev/fd/*; do
    fd=${path##*/}
    case "$fd" in ''|*[!0-9]*|0|1|2) continue ;; esac
    eval "exec $fd>&-" 2>/dev/null
  done
  if [ -n "${5:-}" ]; then export USAGE_AXI_STORE=$5; fi
  nohup "$hook" "$home" "$task" "$trigger"
  result=$?
  [ "$result" -eq 0 ] || printf 'usage capture task=%s trigger=%s hook=%s exit=%s\n' "$task" "$trigger" "$hook" "$result" >&2
) </dev/null >>"$home/state/usage-capture.err" 2>&1 &
exit 0
