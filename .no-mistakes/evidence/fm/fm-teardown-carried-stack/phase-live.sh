#!/usr/bin/env bash
set -euo pipefail
ROOT=$PWD
LAB=$ROOT/.phase-live-lab
mkdir -p "$LAB"
"$ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
SOCKDIR=$("$ROOT/bin/fm-lab-home.sh" tmux-dir "$LAB")
cleanup() { TMUX_TMPDIR="$SOCKDIR" tmux -L fm-lab kill-server 2>/dev/null || true; "$ROOT/bin/fm-lab-home.sh" teardown "$LAB"; rm -rf "$LAB"; }
trap cleanup EXIT
mkdir -p "$LAB/tmux" "$LAB/code"
cp -R bin "$LAB/code/bin"
git -C "$LAB/code" init -q -b main
git -C "$LAB/code" -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m baseline
base=$(git -C "$LAB/code" rev-parse HEAD)
export TREEHOUSE_ROOT="$LAB/pool"
WT=$(cd "$LAB/code" && treehouse get --lease --no-fetch --base main -b fm/carried)
printf 'original\n' > "$WT/carried.txt"
git -C "$WT" add carried.txt
git -C "$WT" -c user.name=Test -c user.email=test@example.invalid commit -q -m original
original=$(git -C "$WT" rev-parse HEAD)
printf 'original\n' > "$LAB/code/carried.txt"
git -C "$LAB/code" add carried.txt
git -C "$LAB/code" -c user.name=Test -c user.email=test@example.invalid commit -q -m replay
printf 'fm/carried %s\n' "$base" > "$LAB/config/fork-stack"
printf 'manual\n' > "$LAB/config/backlog-backend"
TMUX_TMPDIR="$SOCKDIR" tmux -L fm-lab new-session -d -s firstmate -n fm-task-x1 -x 100 -y 30 'sleep 600'
export TMUX="$(TMUX_TMPDIR="$SOCKDIR" tmux -L fm-lab display-message -p '#{socket_path}'),0,0"
cat > "$LAB/state/task-x1.meta" <<EOF
window=firstmate:fm-task-x1
backend=tmux
endpoint_task_id=task-x1
worktree=$WT
project=$LAB/code
kind=ship
mode=local-only
spawn_gen=live-test
EOF
run_cleanup() { env -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME="$LAB" TMUX_TMPDIR="$SOCKDIR" "${CLEANUP_CODE:-$LAB/code}/bin/fm-teardown.sh" task-x1; }
printf 'dirty\n' >> "$WT/carried.txt"
if run_cleanup; then echo 'ERROR dirty cleanup accepted'; exit 1; else echo 'Dirty refusal observed; branch and record retained'; fi
test -f "$LAB/state/task-x1.meta"
test "$(git -C "$WT" symbolic-ref --short HEAD)" = fm/carried
git -C "$WT" restore carried.txt
printf 'gone %s\n' "$base" > "$LAB/config/fork-stack"
if run_cleanup > "$LAB/undeclared.log" 2>&1; then exit 1; fi
cat "$LAB/undeclared.log"
! grep -q 'carried-stack proof failed' "$LAB/undeclared.log"
echo 'LIVE PASS: invalid unrelated declaration does not blame carried proof'
printf 'fm/carried %s extra\n' "$base" > "$LAB/config/fork-stack"
if run_cleanup > "$LAB/invalid.log" 2>&1; then exit 1; fi
cat "$LAB/invalid.log"
grep -q 'carried-stack proof failed' "$LAB/invalid.log"
echo 'LIVE PASS: malformed selected declaration refuses and explains failure'
printf 'fm/carried %s\n' "$base" > "$LAB/config/fork-stack"
printf 'unlanded\n' > "$WT/extra.txt"
git -C "$WT" add extra.txt
git -C "$WT" -c user.name=Test -c user.email=test@example.invalid commit -q -m extra
if run_cleanup; then exit 1; fi
test -f "$LAB/state/task-x1.meta"
git -C "$WT" reset -q --hard "$original"
echo 'LIVE PASS: extra unlanded commit refused and preserved'
if CLEANUP_CODE="$ROOT" run_cleanup; then exit 1; fi
echo 'LIVE PASS: declaration does not authorize cleanup for a different repository'
replay=$(git -C "$LAB/code" rev-parse main)
git init -q --bare "$LAB/remote.git"
git -C "$LAB/code" remote add origin "$LAB/remote.git"
git -C "$LAB/code" push -q origin main
git -C "$LAB/code" update-ref refs/heads/main "$base"
if run_cleanup; then exit 1; fi
echo 'LIVE PASS: content only on remote main is insufficient'
git -C "$LAB/code" update-ref refs/heads/main "$replay"
POOL_STATE="$(dirname "$(dirname "$WT")")/treehouse-state.json"
chmod 000 "${POOL_STATE%.json}.lock"
if run_cleanup; then echo 'ERROR expected pool failure'; exit 1; fi
test -f "$LAB/state/task-x1.meta"
! git -C "$WT" symbolic-ref -q HEAD
chmod 644 "${POOL_STATE%.json}.lock"
echo 'LIVE: failed return left detached HEAD; restored disposable pool metadata; retrying in new process'

run_cleanup
test ! -f "$LAB/state/task-x1.meta"
test "$(git -C "$LAB/code" rev-parse fm/carried)" = "$original"
echo 'LIVE PASS: replay accepted; original declared branch preserved; task record removed'
