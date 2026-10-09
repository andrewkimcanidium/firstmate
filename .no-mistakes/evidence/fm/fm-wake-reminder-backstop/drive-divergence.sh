#!/usr/bin/env bash
# Live driver: lab FM_HOME with a real tasks-axi backlog, a captain hold registered
# through bin/fm-captain-hold.sh, a status log resolving the key, then the real drain.
set -u
ROOT=$PWD
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
bin/fm-lab-home.sh create "$LAB" >/dev/null
: > "$LAB/config/supervision-host-off"
cp "$ROOT/.tasks.toml" "$LAB/.tasks.toml"
printf '## In flight\n\n## Queued\n\n## Done\n' > "$LAB/data/backlog.md"
run() { env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME="$LAB" "$@"; }
id=sample-route-review
(cd "$LAB" && tasks-axi add "$id" "Investigate sample routing" --kind scout --repo sample --start >/dev/null)
printf '%s\n' "window=firstmate:fm-$id" "worktree=$LAB/projects/missing-$id" "project=$LAB/projects/sample" harness=codex kind=scout mode=scout "spawn_gen=fixture-$id" > "$LAB/state/$id.meta"
run "$ROOT/bin/fm-captain-hold.sh" hold sample-route-call --title "Choose route: north or south" \
  --reason "captain route choice pending" --repo sample --origin "$id" >/dev/null; echo "hold exit=$?"
cat > "$LAB/state/$id.status" <<'EOF'
needs-decision [key=sample-route-call]: north or south
resolved [key=sample-route-call]: answered: north
EOF
echo "=== fm-captain-hold.sh diverged ==="; run "$ROOT/bin/fm-captain-hold.sh" diverged
echo "=== fm-wake-drain.sh RECORD DIVERGENCE section ==="
run "$ROOT/bin/fm-wake-drain.sh" 2>/dev/null | grep -A4 '^RECORD DIVERGENCE'
echo "=== agreeing records: no divergence, no hint ==="
cat > "$LAB/state/$id.status" <<'EOF'
needs-decision [key=sample-route-call]: north or south
EOF
run "$ROOT/bin/fm-wake-drain.sh" 2>/dev/null | grep -c 'captain-hold-lifecycle'
rm -rf "$LAB"; echo "lab removed: $([ -e "$LAB" ] && echo no || echo yes)"
