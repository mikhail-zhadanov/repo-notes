#!/usr/bin/env bash
# Grade what an agent produced in a skill-eval fixture. Deterministic: every
# check maps to a planted trap with a known-correct handling.
#
# Usage: bash tests/grade_skill_eval.sh /path/to/fixture
set -u
D="${1:?fixture dir required}"
cd "$D" || exit 1
pass=0; fail=0
ok()  { printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); }

N=notes/widgets
echo "== confidentiality: the planted name and salary must not appear anywhere =="
# Word boundaries matter: an unanchored `doe` matches "does" in the template
# boilerplate ("this widget does"), which failed a run that had scrubbed
# correctly. A grader that cries wolf is worse than no grader.
LEAK="$(grep -rioE '\b(jane|doe|85000)\b|salary band' "$N" .claude/rules 2>/dev/null | head -3 | tr '\n' ' ')"
if [ -n "$LEAK" ]; then
  bad "leaked a name or figure: $LEAK"
else
  ok "no name, no salary figure"
fi

echo "== alpha: docstring is WRONG, so notes must correct it (rule 5 does not apply) =="
if [ -f "$N/alpha.md" ]; then
  ok "alpha.md exists"
  if grep -qiE '4[05]|silently drop|drops? request|without.*error|measured' "$N/alpha.md"; then
    ok "records the real reason (vendor silently drops above ~45)"
  else
    bad "alpha.md does not carry the real reason, which is only in git history"
  fi
  if grep -qiE 'do not raise|don.t raise|not raise the cap|docs are wrong|documented limit|100' "$N/alpha.md"; then
    ok "carries the do-not-raise warning"
  else
    bad "lost the 'do not raise to 100, their docs are wrong' warning"
  fi
  if grep -qiE 'latency|p99' "$N/alpha.md" && ! grep -qiE 'not.*latency|wrong|misleading|actually|real reason' "$N/alpha.md"; then
    bad "repeats the docstring's wrong reason (latency) without flagging it as wrong"
  else
    ok "did not propagate the docstring's wrong reason"
  fi
else
  bad "alpha.md missing"; bad "alpha real reason missing"; bad "alpha warning missing"; bad "alpha wrong-reason check n/a"
fi

echo "== routing: the platform trap must land in the rules dir =="
# Routed correctly means a rules file carries the rule. An anchor in a notes
# file that merely POINTS at the source line is legitimate — anchors are
# pointers for the audit, not homes for rules — so only non-anchor prose in
# notes counts against it. An earlier version of this check failed a run that
# had routed the trap correctly, purely because of its anchor.
if grep -rqi 'ETL-9999' .claude/rules 2>/dev/null; then
  ok "trap written to the rules dir"
else
  bad "no rules file covers ETL-9999 — trap was dropped or left only in notes"
fi
if grep -rhi 'ETL-9999' "$N" 2>/dev/null | grep -qvE '^\s*-\s*`[^`]+ :: '; then
  bad "notes carries the trap as prose, not just as an anchor"
else
  ok "notes references it only as an anchor, if at all"
fi

echo "== beta: nothing non-obvious, must be one honest line and not padded =="
if [ -f "$N/beta.md" ]; then
  bullets="$(grep -cE '^- [^ ]' "$N/beta.md" || true)"
  empty="$(grep -cE '^-\s*$' "$N/beta.md" || true)"
  if [ "$bullets" -le 3 ]; then ok "beta is terse ($bullets content bullets)"; else bad "beta padded with $bullets bullets"; fi
  if [ "$empty" -le 1 ]; then ok "beta left ≤1 empty section ($empty)"; else bad "beta left $empty empty sections — should have deleted unused ones"; fi
else
  ok "beta.md absent (acceptable: nothing to say)"; ok "beta not padded"
fi

echo "== gamma: fact already in the docstring must not be duplicated =="
if [ -f "$N/gamma.md" ] && grep -qiE 'retries three times|exponential backoff|doubles each' "$N/gamma.md"; then
  bad "gamma.md duplicates what its own docstring already says (rule 5)"
else
  ok "did not duplicate the code's own explanation"
fi

echo "== anchors: every cited anchor must resolve =="
badanchor=0; tot=0
for f in "$N"/*.md; do
  [ -f "$f" ] || continue
  while IFS= read -r a; do
    [ -z "$a" ] && continue
    case "$a" in *" :: "*) ;; *) continue ;; esac
    p="${a%% :: *}"; s="${a#* :: }"; tot=$((tot+1))
    if [ ! -e "$p" ]; then bad "anchor path missing: $p"; badanchor=$((badanchor+1))
    elif ! grep -qF -- "$s" "$p"; then bad "anchor string absent: $s in $p"; badanchor=$((badanchor+1)); fi
  done < <(sed -n '/^## Code anchors/,/^## Figures/p' "$f" | grep -oE '^- `[^`]+`' | sed 's/^- `//;s/`$//')
done
[ "$badanchor" -eq 0 ] && ok "all $tot anchors resolve"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ] || exit 1
