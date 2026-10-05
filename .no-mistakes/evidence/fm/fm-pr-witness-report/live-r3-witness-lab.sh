#!/usr/bin/env bash
set -u
ROOT=$PWD
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-witness-r3.XXXXXX")
trap 'rm -rf "$LAB"' EXIT
. "$ROOT/bin/fm-dod-lib.sh"
mkrepo() { # name fetch push
  local d=$LAB/repos/$1; mkdir -p "$d"; git -C "$d" init -q; git -C "$d" remote add origin "$2"; git -C "$d" remote set-url --push origin "$3"; echo "$d"; }
echo "### code under test: $(git -C "$ROOT" rev-parse HEAD); gh-axi $(gh-axi --version)"
echo; echo "### S1 dispatch classification of explicit task projects (real GitHub API)"
for spec in "fork https://github.com/kunchenguid/firstmate.git https://github.com/andrewkimcanidium/firstmate.git" \
            "owned-ci https://github.com/kunchenguid/no-mistakes.git https://github.com/kunchenguid/no-mistakes.git" \
            "hello-world https://github.com/andrewkimcanidium/hello-world.git https://github.com/andrewkimcanidium/hello-world.git" \
            "sap-cpq-axi https://github.com/CanidiumLLC/sap-cpq-axi.git https://github.com/CanidiumLLC/sap-cpq-axi.git" \
            "wow-parser git@github.com:kunchenguid/wow-combat-log-parser.git git@github.com:kunchenguid/wow-combat-log-parser.git" \
            "gitlab https://gitlab.com/x/y.git https://gitlab.com/x/y.git"; do
  set -- $spec; d=$(mkrepo "$1" "$2" "$3")
  printf '%-12s -> %s\n' "$1" "$(fm_dod_destination_class "$d" 2>&1 | tr '\n' ' ')"
done
printf '%-12s -> %s\n' "(none)" "$(fm_dod_destination_class "" 2>&1 | tr '\n' ' ')"
echo; echo "### S2 default-branch check history (POST graphql, real cursors)"
for r in andrewkimcanidium/hello-world kunchenguid/wow-combat-log-parser kunchenguid/firstmate; do
  printf '%-36s %s rc=%s\n' "$r" "$(fm_dod_default_branch_checks "$r")" "$?"; done
HEAD6432=$(fm_dod_api_json repos/kunchenguid/firstmate/pulls/6432 | jq -r .head.sha)
FORK=$LAB/repos/fork; OWNEDFORK=$(mkrepo ownedshape https://github.com/kunchenguid/firstmate.git https://github.com/kunchenguid/firstmate.git)
echo; echo "### S3 structural witness, kunchenguid/firstmate#6432 head=$HEAD6432"
echo "upstream workflow runs: $(fm_dod_api_json "repos/kunchenguid/firstmate/actions/runs?head_sha=$HEAD6432" | jq -r '[.workflow_runs[]|"\(.name):\(.status)/\(.conclusion)"]|join(", ")')"
echo "upstream check-runs:    $(fm_dod_api_json "repos/kunchenguid/firstmate/commits/$HEAD6432/check-runs" | jq -r '[.check_runs[]|"\(.name):\(.status)/\(.conclusion)"]|join(", ")')"
fm_dod_pr_ci_green https://github.com/kunchenguid/firstmate/pull/6432 "$HEAD6432"; echo "adversarial: green 3rd-party check beside action_required runs -> pr_ci_green rc=$? (non-zero = not green)"
printf 'fork witness at published head: %s rc=%s\n' "$(fm_dod_ci_not_witnessed "$FORK" https://github.com/kunchenguid/firstmate/pull/6432 "$HEAD6432")" "$?"
fm_dod_ci_not_witnessed "$FORK" https://github.com/kunchenguid/firstmate/pull/6432 0000000000000000000000000000000000000000 >/dev/null; echo "adversarial: stale head -> rc=$?"
fm_dod_ci_not_witnessed "$OWNEDFORK" https://github.com/kunchenguid/firstmate/pull/6432 "$HEAD6432" >/dev/null; echo "adversarial: same PR assessed as owned (fetch=push) -> rc=$? (must not be absent)"
NMPR=$(fm_dod_api_json 'repos/kunchenguid/no-mistakes/pulls?state=all&per_page=1' | jq -r '.[0]|"\(.number) \(.head.sha) \(.state)"')
set -- $NMPR
fm_dod_ci_not_witnessed "$LAB/repos/owned-ci" "https://github.com/kunchenguid/no-mistakes/pull/$1" "$2" >/dev/null; echo "adversarial: owned repo with configured CI (no-mistakes PR $1, $3) -> ci_not_witnessed rc=$? (must refuse)"
echo; echo "### S4 fm-ci-witness.sh --record on a running CI monitor (lab home; real GitHub; no-mistakes axi stubbed at the CLI boundary)"
H=$LAB/home; bash "$ROOT/bin/fm-lab-home.sh" create "$H" >/dev/null; mkdir -p "$H/state" "$H/data" "$H/config" "$H/fakebin"
WT=$H/wt; git init -q "$WT"; git -C "$WT" remote add origin https://github.com/kunchenguid/firstmate.git; git -C "$WT" remote set-url --push origin https://github.com/andrewkimcanidium/firstmate.git
git -C "$WT" fetch -q --depth 1 https://github.com/kunchenguid/firstmate.git "pull/6432/head" && git -C "$WT" checkout -q -b fm/usage FETCH_HEAD
echo "lab worker head: $(git -C "$WT" rev-parse HEAD)"
cat > "$H/fakebin/no-mistakes" <<'FAKE'
#!/usr/bin/env bash
[ "$#" = 1 ] && [ "$1" = axi ] && { cat "$LABH/run.toon"; exit 0; }
case "$1 $2" in
  'axi status') cat "$LABH/run.toon" ;;
  'axi logs') echo 'no CI checks reported yet' ;;
  'axi abort') printf '%s\n' "$*" >> "$LABH/aborted" ;;
  'axi respond') printf '%s\n' "$*" >> "$LABH/responded" ;;
  *) exit 1 ;;
esac
FAKE
chmod +x "$H/fakebin/no-mistakes"
run() { # ci outcome [skipstep] [head]
  local h=${4:-$(git -C "$WT" rev-parse HEAD)}
  { printf 'current_branch: fm/usage\nrun:\n  id: 01LIVEFORKRUN\n  branch: fm/usage\n  head_sha: %s\n  pr: https://github.com/kunchenguid/firstmate/pull/6432\n' "$h"
    printf 'steps[9]{step,status,findings,duration_ms}:\n'
    for s in intent rebase review test document lint push pr; do [ "$s" = "${3:-}" ] && st=skipped || st=completed; printf '  %s,%s,0,1\n' "$s" "$st"; done
    printf '  ci,%s,0,1\noutcome: %s\n' "$1" "$2"; } > "$H/run.toon"; }
printf 'kind=ship\nmode=no-mistakes\nworktree=%s\nproject=%s\n' "$WT" "$WT" > "$H/state/usage.meta"; chmod 600 "$H/state/usage.meta"
printf 'backend = "markdown"\n[markdown]\npath = "data/backlog.md"\n' > "$H/.tasks.toml"
tasks-axi add usage 'usage capture hooks' --start --file "$H/data/backlog.md" >/dev/null
W() { LABH=$H PATH="$H/fakebin:$PATH" FM_HOME=$H bash "$ROOT/bin/fm-ci-witness.sh" usage "$1" "$2" 2>&1; echo "exit=$?"; }
run running '' review; echo "-- adversarial A1: review gate skipped"; W https://github.com/kunchenguid/firstmate/pull/6432 --record
run failed failed; echo "-- adversarial A2: CI step red/failed"; W https://github.com/kunchenguid/firstmate/pull/6432 --record
run running ''; echo "-- adversarial A3: --skip on running monitor"; W https://github.com/kunchenguid/firstmate/pull/6432 --skip
echo "-- adversarial A4: unrelated PR named"; W https://github.com/kunchenguid/firstmate/pull/1 --record
echo "-- adversarial A5: worker head moved past published head"; git -C "$WT" -c user.email=x@y -c user.name=x commit -q --allow-empty -m moved; run running ''; W https://github.com/kunchenguid/firstmate/pull/6432 --record; git -C "$WT" reset -q --hard HEAD~1
echo "aborted so far: $(cat "$H/aborted" 2>/dev/null || echo none)"
run running ''; echo "-- MAIN: gates green, CI monitor running, upstream workflows action_required"; W https://github.com/kunchenguid/firstmate/pull/6432 --record
echo "-- metadata:"; cat "$H/state/usage.meta"
echo "-- backlog row:"; tasks-axi show usage --file "$H/data/backlog.md"
echo "-- pipeline calls: aborted=[$(cat "$H/aborted" 2>/dev/null)] responded=[$(cat "$H/responded" 2>/dev/null || echo none)]"
echo; echo "### S5 resolved state after the witness abort (fm-crew-state.sh)"
cs() { LABH=$H PATH="$H/fakebin:$PATH" FM_HOME=$H bash "$ROOT/bin/fm-crew-state.sh" usage 2>&1 | head -3; }
H2=$(git -C "$WT" rev-parse HEAD)
cancelled_run() { # id
  { printf 'run:\n  id: "%s"\n  branch: fm/usage\n  status: cancelled\n  head: "%s"\n  pr: "https://github.com/kunchenguid/firstmate/pull/6432"\n  findings: none\noutcome: cancelled\nsteps[9]{step,status,findings,duration_ms}:\n' "$1" "$H2"
    for s in intent rebase review test document lint push pr; do printf '  %s,completed,0,0\n' "$s"; done
    printf '  ci,cancelled,0,1000\n'; } > "$H/run.toon"; }
cancelled_run 01LIVEFORKRUN
printf 'done: PR https://github.com/kunchenguid/firstmate/pull/6432 published, waiting on upstream\n' > "$H/state/usage.status"
echo "status log: $(cat "$H/state/usage.status")"
echo "-- exact recorded witness run:"; cs
cancelled_run 02OTHERRUN; echo "-- adversarial: a different cancelled run id:"; cs
cancelled_run 01LIVEFORKRUN; mv "$H/state/usage.status" "$H/state/usage.status.bak"; echo "-- adversarial: no worker done report:"; cs; mv "$H/state/usage.status.bak" "$H/state/usage.status"
git -C "$WT" -c user.email=x@y -c user.name=x commit -q --allow-empty -m moved; H2=$(git -C "$WT" rev-parse HEAD); cancelled_run 01LIVEFORKRUN; echo "-- adversarial: worker copy moved past the witnessed head:"; cs
echo; echo "### S6 teardown of the published contribution (fm-teardown.sh, lab home)"
git -C "$WT" reset -q --hard HEAD~1
git -C "$WT" update-ref refs/remotes/origin/fm/usage HEAD; echo "head reachable from remote-tracking origin/fm/usage (fork push): $(git -C "$WT" branch -r --contains HEAD | tr -d ' ')"
env -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE LABH=$H PATH="$H/fakebin:$PATH" FM_HOME=$H bash "$ROOT/bin/fm-teardown.sh" usage 2>&1 | tail -4; echo "exit=${PIPESTATUS[0]}"
echo "worktree still present: $([ -d "$WT/.git" ] && echo yes || echo no); meta still present: $([ -f "$H/state/usage.meta" ] && echo yes || echo no)"

