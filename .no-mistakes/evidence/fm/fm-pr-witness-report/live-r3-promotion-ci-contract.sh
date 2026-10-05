#!/usr/bin/env bash
ROOT=$PWD; LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); trap 'rm -rf "$LAB"' EXIT
bash bin/fm-lab-home.sh create "$LAB" >/dev/null
E() { env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME="$LAB" "$@"; }
echo "### code under test: $(git rev-parse HEAD)"
for spec in "fork https://github.com/kunchenguid/firstmate.git https://github.com/andrewkimcanidium/firstmate.git" "hello https://github.com/andrewkimcanidium/hello-world.git https://github.com/andrewkimcanidium/hello-world.git" "nm https://github.com/kunchenguid/no-mistakes.git https://github.com/kunchenguid/no-mistakes.git"; do
  set -- $spec; p=$LAB/projects/$1; mkdir -p "$p"; git -C "$p" init -q; git -C "$p" remote add origin "$2"; git -C "$p" remote set-url --push origin "$3"
  printf -- '- %s [no-mistakes] - lab\n' "$1" >> "$LAB/data/projects.md"
  id=ci-promo-$1
  printf 'window=fm-%s\nkind=scout\nworktree=/tmp/wt\nproject=%s\n' "$id" "$p" > "$LAB/state/$id.meta"
  E bash bin/fm-brief.sh "$id" scaffold-name --scout >/dev/null 2>&1 || echo "brief failed"
  f=$LAB/data/$id/brief.md; c=$(cat "$f"); c=${c//'{TASK}'/Ship this contribution.}; c=${c//'{FIRSTMATE_SPEC}'/Use the resolved project.}; printf '%s\n' "$c" > "$f"
  echo; echo "### $1: origin fetch=$2 push=$3"
  echo "brief.md (scaffold) CI witness contract sections: $(grep -c '^# Current CI witness contract$' "$f")"
  out=$(E bash bin/fm-promote.sh "$id" --mode no-mistakes --yolo off 2>&1); echo "promote exit=$?"; [ $? = 0 ] || printf '%s\n' "$out" | tail -3
  si=$LAB/data/$id/ship-instructions.md
  echo "ship-instructions.md CI witness contract sections: $(grep -c '^# Current CI witness contract$' "$si"); class lines: $(grep '^CI destination class:' "$si" | tr '\n' ';')"
  echo "task metadata: $(grep '^ci_destination=' "$LAB/state/$id.meta")"
done
