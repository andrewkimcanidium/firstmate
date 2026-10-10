#!/usr/bin/env bash
# Live: real codex-cli app-server, disposable CODEX_HOME, real git worktrees.
set -u
ROOT=$1; T=$(mktemp -d "${TMPDIR:-/tmp}/fm-codex-race.XXXXXX"); trap 'rm -rf "$T"' EXIT
export CODEX_HOME="$T/codex"; mkdir -p "$CODEX_HOME"
printf '# operator comment\nmodel = "gpt-5"\n' > "$CODEX_HOME/config.toml"
git init -q "$T/proj"; git -C "$T/proj" commit -q --allow-empty -m init
N=4
echo "== warm the store: one app-server initializes sqlite state first =="
( printf "%s\n" "{\"id\":0,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"warm\",\"version\":\"1\"},\"capabilities\":null}}"; sleep 2 ) | (cd "$CODEX_HOME"; codex app-server --listen stdio:// >/dev/null 2>&1)
for i in $(seq 1 $N); do git -C "$T/proj" worktree add -q "$T/treehouse/wt$i" -b b$i; done
echo "== scenario: $N concurrent spawns registering into one shared store =="
for i in $(seq 1 $N); do ( "$ROOT/bin/fm-codex-trust.sh" "$T/treehouse/wt$i" "$T/proj" > "$T/out$i" 2>&1; echo "wt$i exit=$?" >> "$T/out$i" ) & done; wait
cat "$T"/out*
echo "== persisted trust entries =="; grep -c 'trust_level = "trusted"' "$CODEX_HOME/config.toml"; cat "$CODEX_HOME/config.toml"
echo "== scenario: primary checkout refused =="
"$ROOT/bin/fm-codex-trust.sh" "$T/proj" "$T/proj"; echo "exit=$?"
echo "== scenario: treehouse root (ancestor) refused =="
"$ROOT/bin/fm-codex-trust.sh" "$T/treehouse" "$T/proj"; echo "exit=$?"
echo "== scenario: explicit untrusted entry is not overridden =="
git -C "$T/proj" worktree add -q "$T/treehouse/wtx" -b bx
R=$(cd "$T/treehouse/wtx" && pwd -P)
printf '[projects."%s"]\ntrust_level = "untrusted"\n' "$R" >> "$CODEX_HOME/config.toml"
"$ROOT/bin/fm-codex-trust.sh" "$T/treehouse/wtx" "$T/proj"; echo "exit=$?"
grep -A1 "$R" "$CODEX_HOME/config.toml"
