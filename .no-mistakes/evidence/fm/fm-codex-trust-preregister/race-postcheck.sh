#!/usr/bin/env bash
# Live: N concurrent real-codex registrations into one warm store; afterwards,
# every helper that reported success must still have its entry in the final store
# (otherwise that worker would launch believing it is trusted and wedge).
set -u
ROOT=$1 N=$2; T=$(mktemp -d "${TMPDIR:-/tmp}/fm-codex-race.XXXXXX"); trap 'rm -rf "$T"' EXIT
export CODEX_HOME="$T/codex"; mkdir -p "$CODEX_HOME"; printf 'model = "gpt-5"\n' > "$CODEX_HOME/config.toml"
( printf '%s\n' '{"id":0,"method":"initialize","params":{"clientInfo":{"name":"warm","version":"1"},"capabilities":null}}'; sleep 2 ) | (cd "$CODEX_HOME"; codex app-server --listen stdio:// >/dev/null 2>&1)
git init -q "$T/proj"; git -C "$T/proj" commit -q --allow-empty -m init
for i in $(seq 1 $N); do git -C "$T/proj" worktree add -q "$T/th/wt$i" -b b$i; done
for i in $(seq 1 $N); do ( "$ROOT/bin/fm-codex-trust.sh" "$T/th/wt$i" "$T/proj" >/dev/null 2>"$T/err$i"; echo $? > "$T/rc$i" ) & done; wait
line=""
for i in $(seq 1 $N); do
  rc=$(cat "$T/rc$i"); p=$(cd "$T/th/wt$i" && pwd -P)
  if grep -qF "[projects.\"$p\"]" "$CODEX_HOME/config.toml"; then kept=kept; else kept=LOST; fi
  [ "$rc" = 0 ] && [ "$kept" = LOST ] && kept="LOST-AFTER-SUCCESS"
  line="$line wt$i:rc=$rc,$kept"
  [ "$rc" != 0 ] && line="$line($(sed 's/.*trust: //' "$T/err$i"))"
done
echo "$line"
