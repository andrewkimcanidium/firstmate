#!/usr/bin/env bash
# Live driver: a disposable marked lab FM_HOME, wakes queued through the production
# fm_wake_append (same key shapes the watcher / fm-contributions.sh / stale scan write),
# then the real bin/fm-wake-drain.sh run as the supervisor runs it.
set -u
ROOT=$PWD
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
bin/fm-lab-home.sh create "$LAB" >/dev/null
: > "$LAB/config/supervision-host-off"
run() { env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME="$LAB" "$@"; }
q() { run bash -c '. "$1/bin/fm-wake-lib.sh" && fm_wake_append "$2" "$3" "$4"' _ "$ROOT" "$@"; }
S=$LAB/state
# statuses
echo 'done: PR https://github.com/o/r/pull/9 checks green' > $S/shipa.status
echo 'done: ready in branch fm/shipb' > $S/shipb.status
echo 'done: report written to data/scouty/report.md' > $S/scouty.status; echo 'kind=scout' > $S/scouty.meta
echo 'needs-decision [key=nm-1-review]: ask-user findings=f1 file=/x/f.txt' > $S/valc.status
echo 'working: setup complete' > $S/plain.status
echo 'done: implemented and committed' > $S/preship.status
q stale fm:stuckd 'stale: fm:stuckd'
q check procevent:board:7 'check: procevent lavish board 7'
q check "$S/x-watch.check.sh" "check: $S/x-watch.check.sh: x-mention r1"
q check contribution-0a1b2c3d 'check: contributions taskq 0a1b2c3d'
q check "$S/other.check.sh" "check: $S/other.check.sh: merged"
q heartbeat heartbeat heartbeat
for t in shipa shipb scouty valc plain preship; do q signal $t.status "signal: $t.status"; done
echo "=== fm-wake-drain.sh (lab FM_HOME) ==="
run "$ROOT/bin/fm-wake-drain.sh"; echo "exit=$?"
echo "=== second drain (queue consumed) ==="
run "$ROOT/bin/fm-wake-drain.sh" | grep -c '^load:' ; true
rm -rf "$LAB"; echo "lab removed: $([ -e "$LAB" ] && echo no || echo yes)"
