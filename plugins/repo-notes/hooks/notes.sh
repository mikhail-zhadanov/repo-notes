#!/usr/bin/env bash
# repo-notes: entity-keyed knowledge capture for Claude Code.
#
# This file is the MECHANISM and is identical in every repo. Everything
# repo-specific lives in the consuming repo's .claude/notes.conf.sh, which must
# define the contract documented in examples/. See DESIGN.md for why the
# boundary is here.
#
# Subcommands: session-start | suggest | post | stop | session-end | audit | check-new
#
# Rules this file obeys:
#  - Every path exits 0 unless deliberately emitting decision JSON. A broken
#    hook degrades to "no capture" and never blocks work.
#  - Never reads the transcript or tool output. Only paths and tool names.
#  - CLAUDE_PROJECT_DIR points at the MAIN checkout, not a worktree, so the repo
#    root comes from the stdin cwd first. Notes belong to the tree being edited.
set -u

MODE="${1:?subcommand required}"
INPUT="$(cat 2>/dev/null || true)"
j() { printf '%s' "$INPUT" | jq -r "$1" 2>/dev/null; }

# --- repo root: worktree-correct ---------------------------------------------
CWD="$(j '.cwd // ""')"
if [ -n "$CWD" ] && [ "$CWD" != "null" ]; then
  ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$CWD")"
else
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "${CLAUDE_PROJECT_DIR:-$PWD}")"
fi
cd "$ROOT" 2>/dev/null || exit 0

# --- config contract ---------------------------------------------------------
CONF="$ROOT/.claude/notes.conf.sh"
[ -f "$CONF" ] || exit 0          # not a repo-notes repo; stay silent
# shellcheck source=/dev/null
. "$CONF" 2>/dev/null || exit 0

for fn in notes_entities notes_detect notes_file notes_dirs; do
  command -v "$fn" >/dev/null 2>&1 || exit 0
done
NOTES_DIR="${NOTES_DIR:-notes}"
NOTES_TEMPLATE="${NOTES_TEMPLATE:-$NOTES_DIR/_TEMPLATE.md}"
NOTES_RULES_DIR="${NOTES_RULES_DIR:-.claude/rules}"
NOTES_MUT_RE="${NOTES_MUT_RE:-(^|[^a-zA-Z_-])(mv|cp|rm|sed -i)([^a-zA-Z_-]|\$)}"
NOTES_STATE_NS="${NOTES_STATE_NS:-$(basename "$ROOT")}"

# --- subagents never gate or inject ------------------------------------------
AGENT_ID="$(j '.agent_id // ""')"
[ -n "$AGENT_ID" ] && [ "$AGENT_ID" != "null" ] && exit 0

SID="$(j '.session_id // "nosession"')"
STATE="${TMPDIR:-/tmp}/repo-notes/$NOTES_STATE_NS/$SID"
mkdir -p "$STATE" 2>/dev/null || exit 0

# --- helpers -----------------------------------------------------------------
exists()  { [ -n "$(notes_dirs "${1%%|*}" "${1#*|}" 2>/dev/null)" ]; }
nfile()   { notes_file "${1%%|*}" "${1#*|}" 2>/dev/null; }
seen()    { grep -qxF "$1" "$STATE/$2" 2>/dev/null; }
mark()    { grep -qxF "$1" "$STATE/$2" 2>/dev/null || echo "$1" >> "$STATE/$2"; }

create_stub() {
  local f kind name tick
  kind="${1%%|*}"; name="${1#*|}"
  exists "$1" || return 0
  f="$(nfile "$1")"; [ -z "$f" ] && return 0
  [ -f "$f" ] && return 0
  [ -f "$NOTES_TEMPLATE" ] || return 0
  mkdir -p "$(dirname "$f")" 2>/dev/null || return 0
  tick="$(git -C "$ROOT" branch --show-current 2>/dev/null \
          | grep -oE '[A-Z]+-[0-9]+' | head -1)"
  sed -e "s|{{ENTITY}}|$name|g" -e "s|{{KIND}}|$kind|g" \
      -e "s|{{DATE}}|$(date +%F)|g" -e "s|{{TICKET}}|${tick:-}|g" \
      "$NOTES_TEMPLATE" > "$f" 2>/dev/null
  # Optional: let the repo fill placeholders only it can resolve. A stable
  # identifier that survives a rename is the case that motivated this — the
  # Power BI example stamps each report's and model's logicalId, which is what
  # lets its audit tell "renamed" apart from "deleted".
  command -v notes_stub_fill >/dev/null 2>&1 && notes_stub_fill "$f" "$kind" "$name" 2>/dev/null
  return 0
}

# Anchors are `path :: literal string`. Report only what has gone stale.
check_anchors_in() {
  local f p s a
  while IFS= read -r a; do
    [ -z "$a" ] && continue
    case "$a" in *" :: "*) ;; *) continue ;; esac
    p="${a%% :: *}"; s="${a#* :: }"
    if [ ! -e "$p" ]; then
      echo "[repo-notes] STALE PATH: $1 cites '$p', which does not exist."
    elif [ -f "$p" ] && ! grep -qF -- "$s" "$p"; then
      echo "[repo-notes] STALE ANCHOR: $1 cites '$s' in $p, which no longer contains it."
    fi
  done < <(sed -n '/^## Code anchors/,/^## Figures quoted externally/p' "$1" \
           | grep -oE '^- `[^`]+`' | sed 's/^- `//;s/`$//')
}

case "$MODE" in

  suggest)
    # UserPromptSubmit: route by INTENT, before any file is opened. Path-scoped
    # loading and `post` injection both need a file to exist in the turn; the
    # most expensive knowledge is often needed while merely reasoning. Optional
    # — a config that does not define notes_suggest simply stays silent.
    command -v notes_suggest >/dev/null 2>&1 || exit 0
    # Field name has varied across versions (prompt / user_prompt), and some
    # builds pass raw text rather than JSON. Try each, then fall back to the
    # whole payload — keyword matching works either way.
    PROMPT="$(printf '%s' "$INPUT" | jq -r '.user_prompt // .prompt // empty' 2>/dev/null)"
    [ -z "$PROMPT" ] && PROMPT="$INPUT"
    notes_suggest "$PROMPT" 2>/dev/null || true
    exit 0 ;;

  post)
    TOOL="$(j .tool_name)"; TEXT="$(j '.tool_input|tostring')"
    CTX=""
    while IFS= read -r it; do
      [ -z "$it" ] && continue
      f="$(nfile "$it")"; [ -z "$f" ] && continue
      rel="${f#"$ROOT"/}"
      if ! seen "$it" injected; then
        mark "$it" injected
        if [ -f "$f" ]; then
          CTX+="[repo-notes] $rel -- WHY this ${it%%|*} is built the way it is. Read before changing it; do not undo anything under 'Read this before changing anything'."$'\n'
          CTX+="$(head -c 12000 "$f")"$'\n\n'
        else
          CTX+="[repo-notes] No notes yet for ${it#*|}. One will be created when you change it. Recent history:"$'\n'
          CTX+="$(git -C "$ROOT" log --format='%h %ad %s' --date=short \
                  -- $(notes_dirs "${it%%|*}" "${it#*|}") 2>/dev/null | head -5)"$'\n\n'
        fi
      fi
      case "$TOOL" in
        Edit|Write|MultiEdit|NotebookEdit) mark "$it" mutated ;;
        Bash) printf '%s' "$TEXT" | grep -qE "$NOTES_MUT_RE" && mark "$it" mutated ;;
      esac
    done <<< "$(notes_detect "$TEXT" 2>/dev/null)"
    [ -n "$CTX" ] && jq -n --arg c "$CTX" \
      '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}}'
    exit 0 ;;

  stop)
    [ "$(j '.stop_hook_active // false')" = "true" ] && exit 0
    [ -s "$STATE/mutated" ] || exit 0

    PENDING=""
    while IFS= read -r it; do
      [ -z "$it" ] && continue
      exists "$it" || continue
      seen "$it" gated && continue          # asked once per entity per session
      create_stub "$it"
      PENDING+="$(nfile "$it")"$'\n'
      mark "$it" gated
    done <<< "$(cat "$STATE/mutated" 2>/dev/null)"

    [ -z "${PENDING//[$'\n' ]/}" ] && exit 0
    PENDING="$(printf '%s' "$PENDING" | sed "s|^$ROOT/||" | grep -v '^$' | paste -sd, -)"

    # Blocking Stop, belt and braces. The documented JSON shape is
    # hookSpecificOutput.block/blockReason (NOT decision/reason, NOT
    # permissionDecision, NOT ok:false — all three are explicitly invalid for
    # Stop), and exit 2 blocks on its own per the exit-code table.
    #
    # OBSERVED 2026-09-04, first live firing: exit 2 blocked the stop, but the
    # harness surfaced only "No stderr output" — it reads **stderr** for the
    # exit-2 path and never showed blockReason from stdout. So the gate fired
    # with an empty prompt, which is worse than not firing: the turn is
    # interrupted and the model is told nothing.
    # Therefore write the reason to BOTH stdout JSON and stderr.
    # https://code.claude.com/docs/en/hooks
    REASON="Record what this session decided before finishing. Update: $PENDING

(1) Add to '## Decisions' anything settled this session: what, WHY, what was
    REJECTED and why, and who asked BY ROLE (\"asked by the data owner\",
    \"engineering call\") — never by name, see (4). The rejected half is what
    stops a future session re-proposing a dead end.
(2) Add anything that looks like a bug but is not to '## Intentional oddities',
    and a one-line warning to '## Read this before changing anything' if a
    future session might undo it.
(3) A platform or tool trap does NOT go here; it goes to $NOTES_RULES_DIR.
(4) Never write a person's name, a salary, or any per-person figure.
(5) An anchor is \`path :: literal string\` and the string must exist in that
    file today. Verify before writing it.
(6) If you quoted a figure to anyone outside this session, put it in
    '## Figures quoted externally' with the state it was computed under (date,
    filters, scope). That is what lets a later session tell a changed number
    from a wrong one.
(7) If nothing decision-worthy happened, just bump 'last_touched'.

Asked once per entity per session. Then give your normal reply."
    jq -n --arg r "$REASON" \
      '{hookSpecificOutput:{hookEventName:"Stop",block:true,blockReason:$r}}'
    printf '%s\n' "$REASON" >&2
    exit 2 ;;

  check-new)
    # PreToolUse on git commit: an entity added in THIS commit ships with notes.
    CMD="$(j '.tool_input.command // ""')"
    # Allow global flags between `git` and `commit`: `git -c user.name=x commit`,
    # `git --no-verify commit`, `git -C dir commit` all count.
    printf '%s' "$CMD" \
      | grep -qE '(^|[^a-zA-Z-])git( +-[^ ]+( +[^ -][^ ]*)?)* +commit' || exit 0
    MISSING=""
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      while IFS= read -r it; do
        [ -z "$it" ] && continue
        f="$(nfile "$it")"; [ -z "$f" ] && continue
        [ -f "$f" ] && continue
        grep -qxF "$f" <<< "$MISSING" 2>/dev/null || MISSING="$MISSING$f"$'\n'
      done <<< "$(notes_detect "$p" 2>/dev/null)"
    done <<< "$(git diff --cached --name-only --diff-filter=A 2>/dev/null)"

    MISSING="$(printf '%s' "$MISSING" | grep -v '^$' || true)"
    [ -z "$MISSING" ] && exit 0
    {
      echo "Blocked: this commit adds a new entity with no notes file."
      echo
      printf '%s\n' "$MISSING" | sed 's/^/  missing: /'
      echo
      echo "Every entity must have one. Create it from $NOTES_TEMPLATE, record why"
      echo "the entity exists and any decision a cold session could undo, then commit"
      echo "again. If there is genuinely nothing yet, say so in one line under"
      echo "Decisions rather than leaving it blank."
    } >&2
    exit 2 ;;

  session-start)
    find "${TMPDIR:-/tmp}/repo-notes/$NOTES_STATE_NS" -mindepth 1 -maxdepth 1 \
      -type d -mtime +2 -exec rm -rf {} + 2>/dev/null
    "$0" audit </dev/null
    exit 0 ;;

  session-end)
    rm -rf "$STATE" 2>/dev/null
    exit 0 ;;

  audit)  # prints only anomalies; safe to run by hand
    # 1. coverage
    #
    # Summarised, not enumerated. One line per uncovered entity meant a repo
    # with 40 gaps printed 40 lines at every single session start, forever,
    # until someone backfilled — and noise that appears unconditionally stops
    # being read, which defeats the point of reporting it at all.
    MISS_N=0; MISS_NAMES=""
    while IFS= read -r it; do
      [ -z "$it" ] && continue
      f="$(nfile "$it")"; [ -z "$f" ] && continue
      [ -f "$f" ] && continue
      MISS_N=$((MISS_N + 1))
      [ "$MISS_N" -le 5 ] && MISS_NAMES="$MISS_NAMES ${it#*|}"
    done <<< "$(notes_entities 2>/dev/null)"
    if [ "$MISS_N" -gt 0 ]; then
      if [ "$MISS_N" -le 5 ]; then
        echo "[repo-notes] $MISS_N entit$([ "$MISS_N" = 1 ] && echo y || echo ies) with no notes file:${MISS_NAMES}. Run /notes backfill."
      else
        echo "[repo-notes] $MISS_N entities with no notes file, e.g.${MISS_NAMES}. Run /notes backfill for the full list."
      fi
    fi

    # 2. orphans and stale anchors in notes
    #
    # Orphan detection compares against the set of files the CONFIG expects,
    # rather than inferring a kind from the directory name. The directory is
    # named by the config's notes_file and need not equal the kind ("mart" ->
    # notes/marts/), so inferring it produced a false orphan for every file.
    EXPECTED="$(while IFS= read -r it; do
                  [ -z "$it" ] && continue
                  f="$(nfile "$it")"; [ -n "$f" ] && printf '%s\n' "${f#"$ROOT"/}"
                done <<< "$(notes_entities 2>/dev/null)")"

    for f in "$NOTES_DIR"/*.md "$NOTES_DIR"/*/*.md; do
      [ -f "$f" ] || continue
      case "$f" in *_TEMPLATE.md|*/_archive/*) continue ;; esac
      if ! grep -qxF "$f" <<< "$EXPECTED"; then
        # A repo that can tell "renamed" from "deleted" (via a stable id in the
        # frontmatter) says so more precisely in its own notes_audit, so let it
        # suppress this coarser line rather than print both.
        [ "${NOTES_SKIP_ORPHAN:-0}" = "1" ] && continue
        echo "[repo-notes] ORPHAN: $f matches no current entity. Renamed, or removed? Move it to $NOTES_DIR/_archive/."
        continue
      fi
      check_anchors_in "$f"
      # Owned paths come from the entity whose notes file this is.
      owned=""
      while IFS= read -r it; do
        [ -z "$it" ] && continue
        [ "$(nfile "$it")" = "$ROOT/$f" ] || continue
        owned="$(notes_dirs "${it%%|*}" "${it#*|}" 2>/dev/null)"
        break
      done <<< "$(notes_entities 2>/dev/null)"
      [ -z "$owned" ] && continue
      # Read into an array: entity paths legitimately contain spaces (a report
      # named "Ad hoc: Sales Pipeline" is a real case), and an unquoted
      # expansion word-splits, silently disabling this check.
      owned_arr=()
      while IFS= read -r d; do [ -n "$d" ] && owned_arr+=("$d"); done <<< "$owned"
      [ "${#owned_arr[@]}" -eq 0 ] && continue
      lt="$(sed -n 's/^last_touched: *\([0-9-]*\).*/\1/p' "$f" | head -1)"
      last="$(git log -1 --format='%cs' -- "${owned_arr[@]}" 2>/dev/null)"
      if [ -n "$lt" ] && [ -n "$last" ] && [ "$last" \> "$lt" ]; then
        echo "[repo-notes] BEHIND: $f last_touched $lt, but its entity changed on $last. Whoever is next in these files should confirm the notes still hold."
      fi
    done

    # 3. paths cited in the rule files must exist too
    for r in "$NOTES_RULES_DIR"/*.md; do
      [ -f "$r" ] || continue
      while IFS= read -r tok; do
        [ -z "$tok" ] && continue
        case "$tok" in */*) ;; *) continue ;; esac
        # Not paths: glob/placeholder patterns, URLs, and slash commands
        # (`/notes` is a command, not a directory).
        # Placeholders come in several notations: <angle>, {brace}, * glob, and
        # an ellipsis. `notes/{ws}/` in a rule file is documentation, not a path.
        case "$tok" in *"<"*|*">"*|*"{"*|*"}"*|*"…"*|*"*"*|http*) continue ;; esac
        case "$tok" in /*) case "${tok#/}" in */*) ;; *) continue ;; esac ;; esac
        if [ "${tok#* :: }" != "$tok" ]; then
          p="${tok%% :: *}"; s="${tok#* :: }"
          if [ ! -e "$p" ]; then
            echo "[repo-notes] STALE PATH: $r cites '$p', which does not exist."
          elif [ -f "$p" ] && ! grep -qF -- "$s" "$p"; then
            echo "[repo-notes] STALE ANCHOR: $r cites '$s' in $p, which no longer contains it."
          fi
        else
          [ -e "${tok%,}" ] || [ ! -d "$(dirname "${tok%,}")" ] \
            || echo "[repo-notes] STALE PATH: $r cites '${tok%,}', which does not exist."
        fi
      done < <(grep -oE '`[^`]+`' "$r" | tr -d '`')
    done

    # 4. OPTIONAL: checks only this repo can make. Print anomalies, nothing else.
    command -v notes_audit >/dev/null 2>&1 && notes_audit 2>/dev/null
    exit 0 ;;
esac
exit 0
