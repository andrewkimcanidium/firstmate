#!/usr/bin/env bash
# Round 4: real fm-ci-witness.sh / fm-crew-state.sh / fm-teardown.sh / tasks-axi in a
# disposable lab home; GitHub is a local fake gh-axi (same TOON envelope), no-mistakes axi stubbed.
set -u
ROOT=$PWD
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-witness-r4b.XXXXXX")
trap 'rm -rf "$LAB"' EXIT
echo "### code under test: $(git -C "$ROOT" rev-parse HEAD)"
mkcase() { # name owned|fork
  local H=$LAB/$1 push=owner/repo head
  bash "$ROOT/bin/fm-lab-home.sh" create "$H" >/dev/null; mkdir -p "$H/state" "$H/data" "$H/config" "$H/fakebin"
  git init -q -b main "$H/wt"; git -C "$H/wt" -c user.email=x@y -c user.name=x commit -q --allow-empty -m init
  git -C "$H/wt" checkout -q -b fm/witness
  git -C "$H/wt" remote add origin https://github.com/owner/repo.git
  [ "$2" = fork ] && { push=contributor/repo; git -C "$H/wt" remote set-url --push origin git@github.com:contributor/repo.git; }
  head=$(git -C "$H/wt" rev-parse HEAD)
  python3 - "$H" "$head" "$push" <<'PY'
import json, pathlib, sys
p, head, push = sys.argv[1:]; p = pathlib.Path(p)
f = {
 'history': {'data':{'repository':{'defaultBranchRef':{'target':{'history':{'pageInfo':{'hasNextPage':False,'endCursor':None},'nodes':[{'statusCheckRollup':None}]}}}}}},
 'pr': {'state':'open','draft':False,'head':{'sha':head,'ref':'fm/witness','repo':{'full_name':push}},'base':{'ref':'main','repo':{'full_name':'owner/repo'}}},
 'workflows': {'total_count':0,'workflows':[]},
 'checks': {'total_count':0,'check_runs':[]},
 'statuses': {'total_count':0,'statuses':[]},
 'branch': {'protected':False}, 'rules': [],
 'runs': {'total_count':0,'workflow_runs':[]}}
for k,v in f.items(): (p/(k+'.json')).write_text(json.dumps(v))
PY
  cat > "$H/fakebin/gh-axi" <<'FAKE'
#!/usr/bin/env python3
import base64, os, pathlib, sys
p = pathlib.Path(os.environ['LABH']); args = sys.argv[2:]
with open(p/'gh-calls','a') as f: f.write(' '.join(args[:2])+'\n')
method = args.pop(0) if args and args[0]=='POST' else 'GET'
path = args[0] if args else ''
if path=='graphql' and method!='POST': sys.exit(1)
m = [('graphql','history'),('/pulls/','pr'),('/workflows?','workflows'),('/check-runs?','checks'),('/status?','statuses'),('/runs?','runs'),('/rules/branches/','rules'),('/branches/','branch')]
for key,name in m:
    if key in path: break
else: sys.exit(1)
print('api_response:\n  body: '+base64.b64encode((p/(name+'.json')).read_bytes()).decode()+'\n  truncated: false')
FAKE
  cat > "$H/fakebin/no-mistakes" <<'FAKE'
#!/usr/bin/env bash
case "$1 $2" in
  'axi status') cat "$LABH/run.toon" ;;
  'axi logs') echo 'no CI checks reported yet' ;;
  'axi abort') printf '%s\n' "$*" >> "$LABH/aborted" ;;
  'axi respond') printf '%s\n' "$*" >> "$LABH/responded" ;;
  *) [ "$1" = axi ] && cat "$LABH/run.toon" || exit 1 ;;
esac
FAKE
  chmod +x "$H/fakebin/"*
  printf 'kind=ship\nmode=no-mistakes\nworktree=%s\nproject=%s\nwindow=fm:fm-witness\n' "$H/wt" "$H/wt" > "$H/state/witness.meta"; chmod 600 "$H/state/witness.meta"
  printf 'backend = "markdown"\n[markdown]\npath = "data/backlog.md"\n' > "$H/.tasks.toml"
  tasks-axi add witness 'CI witness lab' --start --file "$H/data/backlog.md" >/dev/null
  echo "$H"; }
edit() { jq "$3" "$1/$2.json" > "$1/e.json" && mv "$1/e.json" "$1/$2.json"; }
running() { local h; h=$(git -C "$1/wt" rev-parse HEAD)
  { printf 'current_branch: fm/witness\nrun:\n  id: 01LABRUN\n  branch: fm/witness\n  head_sha: %s\n  pr: https://github.com/owner/repo/pull/1\nsteps[9]{step,status,findings,duration_ms}:\n' "$h"
    for s in intent rebase review test document lint push pr; do printf '  %s,completed,0,1\n' "$s"; done
    printf '  ci,%s,0,1\noutcome: %s\n' "${2:-running}" "${3:-}"; } > "$1/run.toon"; }
cancelled() { local h; h=$(git -C "$1/wt" rev-parse HEAD)
  { printf 'run:\n  id: "01LABRUN"\n  branch: fm/witness\n  status: cancelled\n  head: "%s"\n  pr: "https://github.com/owner/repo/pull/1"\n  findings: none\noutcome: cancelled\nsteps[9]{step,status,findings,duration_ms}:\n' "$h"
    for s in intent rebase review test document lint push pr; do printf '  %s,completed,0,0\n' "$s"; done
    printf '  ci,cancelled,0,1000\n'; } > "$1/run.toon"; }
W() { LABH=$1 PATH="$1/fakebin:$PATH" FM_HOME=$1 bash "$ROOT/bin/fm-ci-witness.sh" witness https://github.com/owner/repo/pull/1 "$2" 2>&1; echo "exit=$?"; }
CS() { printf 'done: PR https://github.com/owner/repo/pull/1 %s\n' "$2" > "$1/state/witness.status"
  LABH=$1 PATH="$1/fakebin:$PATH" FM_HOME=$1 bash "$ROOT/bin/fm-crew-state.sh" witness 2>&1 | head -2; }

echo; echo "### R4-1 ci-1: fork PR, only a third-party app check (Greptile Review: success), zero destination workflow runs"
A=$(mkcase appcheck fork)
edit "$A" checks '.total_count=1|.check_runs=[{name:"Greptile Review",status:"completed",conclusion:"success"}]'
edit "$A" workflows '.total_count=2|.workflows=[{id:1},{id:2}]'
running "$A"; echo "-- running CI monitor --record:"; W "$A" --record
running "$A" completed passed; echo "-- passed run, CI completed --record:"; W "$A" --record
echo "ci_witness in meta: [$(sed -n 's/^ci_witness=//p' "$A/state/witness.meta")]  aborted: [$(cat "$A/aborted" 2>/dev/null)]"
edit "$A" runs ".total_count=1|.workflow_runs=[{head_sha:\"$(git -C "$A/wt" rev-parse HEAD)\",status:\"completed\",conclusion:\"success\"}]"
echo "-- control: destination's own workflow run completed success:"; W "$A" --record | tail -2
echo "ci_witness in meta: [$(sed -n 's/^ci_witness=//p' "$A/state/witness.meta")]"

echo; echo "### R4-2 ci-2: fork destination with no CI at all -> absent + published + external hold + abort"
F=$(mkcase forkabsent fork); running "$F"; : > "$F/gh-calls"
W "$F" --record
grep -E '^(ci_witness|delivery_state|ci_witness_run)=' "$F/state/witness.meta"
echo "backlog: $(tasks-axi show witness --file "$F/data/backlog.md" | grep -E 'held:|hold_kind:' | tr -s ' ' | tr '\n' ' ')"
echo "aborted: [$(cat "$F/aborted")]"
echo "gh-axi calls made by --record (witness-redundant-classification fix: workflows/history read once):"; sort "$F/gh-calls" | uniq -c
echo "-- adversarial: fork whose default branch once carried a check run:"
F2=$(mkcase forkcarried fork); running "$F2"
edit "$F2" history '.data.repository.defaultBranchRef.target.history.nodes[0].statusCheckRollup={state:"SUCCESS"}'
W "$F2" --record; echo "ci_witness in meta: [$(sed -n 's/^ci_witness=//p' "$F2/state/witness.meta")] aborted: [$(cat "$F2/aborted" 2>/dev/null)]"

echo; echo "### R4-3 fork-absent done line resolves through the shared done gate (fm-crew-state.sh, cancelled witness run)"
cancelled "$F"; git -C "$F/wt" update-ref refs/remotes/origin/fm/witness HEAD
echo "-- worker reports 'published, waiting on upstream':"; CS "$F" 'published, waiting on upstream'
echo "-- adversarial: fork reports owned wording 'CI absent':"; CS "$F" 'CI absent'

echo; echo "### R4-4 owned repo without CI: phrase binding to delivery_state"
O=$(mkcase ownedabsent owned); running "$O"; W "$O" --record
grep -E '^(ci_witness|delivery_state|ci_witness_run)=' "$O/state/witness.meta"; echo "(no delivery_state line expected above)"
echo "backlog: $(tasks-axi show witness --file "$O/data/backlog.md" | grep -E 'held:' | tr -s ' ')"
cancelled "$O"; git -C "$O/wt" update-ref refs/remotes/origin/fm/witness HEAD
echo "-- worker reports 'CI absent':"; CS "$O" 'CI absent'
echo "-- adversarial: owned repo reports 'published, waiting on upstream':"; CS "$O" 'published, waiting on upstream'

echo; echo "### R4-5 teardown of a detached published fork worktree explains its refusal"
git -C "$F/wt" checkout -q --detach
sed -i '' '/^window=/d' "$F/state/witness.meta"
env -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE LABH=$F PATH="$F/fakebin:$PATH" FM_HOME=$F bash "$ROOT/bin/fm-teardown.sh" witness 2>&1 | grep -v '^●' | tail -3; echo "exit=${PIPESTATUS[0]}"
echo "-- control: same worktree back on its branch (fork push only, not landed upstream):"; git -C "$F/wt" checkout -q fm/witness
env -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE LABH=$F PATH="$F/fakebin:$PATH" FM_HOME=$F bash "$ROOT/bin/fm-teardown.sh" witness 2>&1 | grep -v '^●' | tail -2; echo "exit=${PIPESTATUS[0]}"
echo "worktree still present: $([ -d "$F/wt/.git" ] && echo yes || echo no); meta still present: $([ -f "$F/state/witness.meta" ] && echo yes || echo no)"
