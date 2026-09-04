#!/usr/bin/env bash
# Exercise the mechanism against a throwaway repo built in a temp dir.
# No dependency on any real project. Run: bash tests/test_notes.sh
set -u

HOOK="$(cd "$(dirname "$0")/.." && pwd)/plugins/repo-notes/hooks/notes.sh"
TPL="$(cd "$(dirname "$0")/.." && pwd)/plugins/repo-notes/templates/_TEMPLATE.md"
pass=0; fail=0
ok()   { printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }
chk()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
cd "$FIX" || exit 1

# --- a minimal repo: entities are widgets/<name> ------------------------------
git init -q .
mkdir -p widgets/alpha widgets/beta notes/widgets .claude/rules
echo "the alpha widget SENTINEL_STRING" > widgets/alpha/main.txt
echo "beta" > widgets/beta/main.txt
cp "$TPL" notes/_TEMPLATE.md

cat > .claude/notes.conf.sh <<'CONF'
NOTES_DIR="notes"
NOTES_TEMPLATE="notes/_TEMPLATE.md"
NOTES_RULES_DIR=".claude/rules"
NOTES_MUT_RE='(^|[^a-zA-Z_-])(rm|mv|sed -i)([^a-zA-Z_-]|$)'
notes_entities() { ls -d widgets/*/ 2>/dev/null | sed -E 's#widgets/([^/]+)/#widget|\1#' | sort -u; }
notes_detect() {
  local all; all="$(notes_entities | cut -d'|' -f2)"
  printf '%s' "$1" | grep -oE 'widgets/[A-Za-z0-9_-]+' | sed -E 's#widgets/#widget|#' \
    | sort -u | while IFS= read -r it; do grep -qxF "${it#*|}" <<< "$all" && echo "$it"; done
}
notes_file() { printf '%s/notes/widgets/%s.md' "$PWD" "$2"; }
notes_dirs() { ls -d "widgets/$2" 2>/dev/null; }
CONF

git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1

run() { printf '%s' "$2" | bash "$HOOK" "$1"; }
ev()  { printf '{"cwd":"%s","session_id":"%s","tool_name":"%s","tool_input":{"file_path":"%s"}}' "$FIX" "$1" "$2" "$3"; }

echo "== audit reports missing coverage =="
out="$(run audit "$(printf '{"cwd":"%s"}' "$FIX")")"
case "$out" in *"MISSING: widget 'alpha'"*) ok "flags alpha" ;; *) bad "should flag alpha" ;; esac
case "$out" in *"MISSING: widget 'beta'"*)  ok "flags beta"  ;; *) bad "should flag beta"  ;; esac

echo "== post injects for a real entity, ignores a fake one =="
out="$(run post "$(ev s1 Read widgets/alpha/main.txt)")"
case "$out" in *"No notes yet for alpha"*) ok "injects alpha" ;; *) bad "should inject alpha" ;; esac
out="$(run post "$(ev s2 Read widgets/nonexistent/x.txt)")"
chk "ignores unknown entity" "${out:-<empty>}" "<empty>"

echo "== subagent is ignored =="
out="$(printf '{"cwd":"%s","session_id":"s3","agent_id":"a1","tool_name":"Edit","tool_input":{"file_path":"widgets/alpha/main.txt"}}' "$FIX" | bash "$HOOK" post)"
chk "subagent silent" "${out:-<empty>}" "<empty>"

echo "== a read does not arm the gate; an edit does =="
run post "$(ev s4 Read widgets/alpha/main.txt)" >/dev/null
out="$(run stop "$(printf '{"cwd":"%s","session_id":"s4","stop_hook_active":false}' "$FIX")")"
chk "read does not arm" "${out:-<empty>}" "<empty>"

run post "$(ev s5 Edit widgets/alpha/main.txt)" >/dev/null
out="$(run stop "$(printf '{"cwd":"%s","session_id":"s5","stop_hook_active":false}' "$FIX")")"
# Parse rather than string-match: jq pretty-prints, so "decision": "block" has a space.
chk "edit arms the gate" "$(printf '%s' "$out" | jq -r '.decision // "none"')" "block"
case "$out" in *"notes/widgets/alpha.md"*) ok "gate names the file" ;; *) bad "gate should name the file" ;; esac
[ -f notes/widgets/alpha.md ] && ok "stub created from template" || bad "stub not created"

echo "== gate asks once per entity per session =="
out="$(run stop "$(printf '{"cwd":"%s","session_id":"s5","stop_hook_active":false}' "$FIX")")"
chk "second stop silent" "${out:-<empty>}" "<empty>"

echo "== loop guard honoured =="
run post "$(ev s6 Edit widgets/beta/main.txt)" >/dev/null
out="$(run stop "$(printf '{"cwd":"%s","session_id":"s6","stop_hook_active":true}' "$FIX")")"
chk "stop_hook_active respected" "${out:-<empty>}" "<empty>"

echo "== anchors: good passes, bad is reported =="
python3 - "$FIX/notes/widgets/alpha.md" <<'PY'
import sys,re
p=sys.argv[1]; t=open(p).read()
t=t.replace("## Code anchors","## Code anchors\nX-MARK",1)
t=t.replace("X-MARK","- `widgets/alpha/main.txt :: SENTINEL_STRING`\n- `widgets/alpha/main.txt :: GONE_AWAY`",1)
open(p,"w").write(t)
PY
out="$(run audit "$(printf '{"cwd":"%s"}' "$FIX")")"
case "$out" in *"GONE_AWAY"*) ok "stale anchor reported" ;; *) bad "should report stale anchor" ;; esac
case "$out" in *"SENTINEL_STRING"*) bad "valid anchor wrongly reported" ;; *) ok "valid anchor silent" ;; esac

echo "== orphan detection =="
cp notes/widgets/alpha.md notes/widgets/ghost.md
out="$(run audit "$(printf '{"cwd":"%s"}' "$FIX")")"
case "$out" in *"ORPHAN"*) ok "orphan reported" ;; *) bad "should report orphan" ;; esac
rm -f notes/widgets/ghost.md

echo "== commit gate blocks a new entity with no notes =="
mkdir -p widgets/gamma; echo g > widgets/gamma/main.txt; git add -A >/dev/null 2>&1
out="$(printf '{"cwd":"%s","session_id":"s7","tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' "$FIX" | bash "$HOOK" check-new 2>&1)"
rc=$?
case "$out" in *"notes/widgets/gamma.md"*) ok "names the missing file" ;; *) bad "should name gamma" ;; esac
chk "exit code 2" "$rc" "2"

echo "== commit gate ignores a non-commit command =="
out="$(printf '{"cwd":"%s","session_id":"s8","tool_name":"Bash","tool_input":{"command":"git status"}}' "$FIX" | bash "$HOOK" check-new 2>&1)"; rc=$?
chk "non-commit passes" "$rc" "0"

echo "== no config means total silence =="
mv .claude/notes.conf.sh .claude/off.sh
out="$(run post "$(ev s9 Edit widgets/alpha/main.txt)")"
chk "unconfigured repo silent" "${out:-<empty>}" "<empty>"
mv .claude/off.sh .claude/notes.conf.sh

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ] || exit 1
