#!/usr/bin/env bash
# Live driver: real bin/fm-spawn.sh + real Claude Code into a throwaway fm-lab- Herdr
# session and a disposable fm-lab-home, then read Herdr's agent panel records.
set -u
ROOT=$PWD
LAB_HELPER=$ROOT/bin/fm-herdr-lab.sh
. "$ROOT/tests/herdr-test-safety.sh"; herdr_forget_inherited_pane
SESSION=$("$LAB_HELPER" name agent-naming) || exit 1
export HERDR_SESSION=$SESSION
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
WORKTREES=()
cleanup() {
  for wt in ${WORKTREES[@]+"${WORKTREES[@]}"}; do treehouse return --force "$wt" >/dev/null 2>&1; done
  "$LAB_HELPER" teardown "$SESSION"; echo "teardown rc=$?"
  find "$LAB" -type d -exec chmod u+rwx {} + 2>/dev/null; rm -rf "$LAB"
}
trap cleanup EXIT
bin/fm-lab-home.sh create "$LAB" >/dev/null || exit 1
printf 'off\n' > "$LAB/config/herdr-presentation-spaces"
"$LAB_HELPER" provision "$SESSION" || exit 1
lab() { "$LAB_HELPER" run "$SESSION" "$@"; }
echo "herdr session: $SESSION   herdr $(herdr --version)   claude $(claude --version 2>/dev/null)"

PROJ=$LAB/scratch; mkdir -p "$PROJ"; git -C "$PROJ" init -q
echo x > "$PROJ/README.md"; git -C "$PROJ" add .; git -C "$PROJ" -c user.name=t -c user.email=t@e.invalid commit -qm init
git clone -q --bare "$PROJ" "$PROJ.origin.git"; git -C "$PROJ" remote add origin "file://$PROJ.origin.git"

spawn() { # <id> <launch>
  local id=$1
  mkdir -p "$LAB/data/$id"
  printf '# Task\n## Captain'"'"'s intent\nIdle; do nothing for %s.\n\n## Firstmate spec\nDo nothing.\n' "$id" > "$LAB/data/$id/brief.md"
  local t0=$(date +%s)
  env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE \
      -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_SOCKET_PATH \
      FM_SPAWN_NO_GUARD=1 FM_HOME="$LAB" HERDR_SESSION="$SESSION" \
      "$ROOT/bin/fm-spawn.sh" "$id" "$PROJ" "$2" --mode local-only --yolo off --backend herdr \
      >"$LAB/$id.out" 2>"$LAB/$id.err"
  local rc=$? 
  echo "--- spawn $id ($2): rc=$rc" >&2; echo "    elapsed in $(( $(date +%s) - t0 ))s"
  [ $rc -eq 0 ] || { tail -20 "$LAB/$id.err" >&2; }
  local wt; wt=$(grep '^worktree=' "$LAB/state/$id.meta" 2>/dev/null | cut -d= -f2-); [ -n "$wt" ] && WORKTREES+=("$wt")
  grep '^herdr_pane_id=' "$LAB/state/$id.meta" 2>/dev/null | cut -d= -f2-
}
agent_of() { lab agent get "$1" 2>&1 | jq -c '.result.agent // .error | {pane_id, agent, name, code, agent_status}' 2>/dev/null || lab agent get "$1"; }

A=$(spawn Herdr-Naming-Alpha-Worker.With.Dots claude | tail -1)
B=$(spawn Herdr-Naming-Alpha-Worker.With.Dashes claude | tail -1)
C=$(spawn plainshell-worker "sh -c 'sleep 600'" | tail -1)
sleep 2
# A supervisor-shaped Claude in its own pane, NOT launched by fm-spawn.
SUP=$(lab tab create --workspace "$(lab pane get "$A" | jq -r .result.pane.workspace_id)" --cwd "$PROJ" --label supervisor --no-focus | jq -r .result.root_pane.pane_id)
lab pane run "$SUP" "claude" >/dev/null 2>&1 || lab pane send-text "$SUP" "claude"$'\r' >/dev/null 2>&1
sleep 6
echo "supervisor pane $SUP -> $(agent_of "$SUP")"
for p in "$A" "$B" "$C"; do echo "pane $p -> $(agent_of "$p")"; done
echo "--- herdr agent list (the agent panel's data):"
lab agent list 2>/dev/null | jq -c '.result.agents[]? | {pane_id, agent, name}' 2>/dev/null || lab agent list
echo "--- fm-peek on worker A (control path still reads the renamed worker):"
env -u NO_MISTAKES_GATE FM_HOME="$LAB" HERDR_SESSION="$SESSION" "$ROOT/bin/fm-peek.sh" Herdr-Naming-Alpha-Worker.With.Dots 2>&1 | tail -8; echo "fm-peek rc=${PIPESTATUS[0]}"
echo "--- spawn stderr (A):"; cat "$LAB/Herdr-Naming-Alpha-Worker.With.Dots.err" | tail -5
