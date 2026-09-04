# repo-notes config for a Power BI / Fabric git-synced repo (PBIR + TMDL).
# This is the file in production use in one such repo, not a sketch.
#
# It is also the worked example for the two optional extension points:
# notes_stub_fill (stamp an identity the audit can rely on) and notes_audit
# (checks only this repo can make), plus NOTES_SKIP_ORPHAN to replace the
# generic orphan line with a better one.
#
# Entity = one report. A report and its semantic model are one unit of knowledge:
# a measure moves between them, and a decision about either is a decision about
# the report, so they share a notes file.
#
# Identity is the report's logicalId, not its path. Report names are renamed
# often and freely in the Fabric service, and the service commits the rename
# itself; keying on the name alone would turn every rename into a lost notes
# file. See notes_audit below.

NOTES_DIR="notes"
NOTES_TEMPLATE="notes/_TEMPLATE.md"
NOTES_RULES_DIR=".claude/rules"

# The coarse path-based ORPHAN line is replaced by the logicalId check in
# notes_audit, which can tell a rename from a deletion.
NOTES_SKIP_ORPHAN=1

# pbir/shell verbs that change a report. A read-only call must not arm the gate.
NOTES_MUT_RE='(^|[^a-zA-Z_-])(set|add|mv|cp|rm|new|batch|restore|replace|rename|delete|remove|publish|sed -i)([^a-zA-Z_-]|$)'

# --- the contract ------------------------------------------------------------

notes_entities() {
  local d ws name
  for d in workspaces/*/*.Report; do
    [ -d "$d" ] || continue
    name="$(basename "$d" .Report)"
    ws="$(basename "$(dirname "$d")")"
    printf '%s|%s\n' "$ws" "$name"
  done
}

# Emit "workspace|ReportName" for every report the text actually refers to.
# Both branches are validated against the filesystem: a command that merely
# MENTIONS a "X.Report"-shaped string (a script writing paths, a doc, a log
# line) must not count as touching a report, or it would arm the Stop gate.
notes_detect() {
  {
    printf '%s' "$1" | grep -oE 'workspaces/[^/"'"'"']+/[^/"'"'"']+\.(Report|SemanticModel)' \
      | sed -E 's#^workspaces/([^/]+)/(.+)\.(Report|SemanticModel)$#\1|\2#'
    printf '%s' "$1" | grep -oE '[^/"'"'"'=]+\.(Report|SemanticModel)' \
      | sed -E 's/\.(Report|SemanticModel)$//' \
      | while IFS= read -r n; do
          n="${n#"${n%%[![:space:]]*}"}"
          [ -z "$n" ] && continue
          for d in workspaces/*/"$n".Report; do
            [ -d "$d" ] && printf '%s|%s\n' "$(basename "$(dirname "$d")")" "$n"
          done
        done
  } 2>/dev/null | sort -u | while IFS= read -r it; do
      [ -z "$it" ] && continue
      [ -d "workspaces/${it%%|*}/${it#*|}.Report" ] && printf '%s\n' "$it"
    done
}

notes_file() { printf '%s/notes/%s/%s.md' "$PWD" "$1" "$2"; }

notes_dirs() {
  ls -d "workspaces/$1/$2.Report" "workspaces/$1/$2.SemanticModel" 2>/dev/null
}

# --- optional: stamp the identity the audit relies on ------------------------

_notes_logical_id() {
  python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["config"]["logicalId"])' \
    "$1/.platform" 2>/dev/null
}

# The template keeps its own names ({{NAME}}, {{WS}}) rather than the plugin's
# generic {{ENTITY}}/{{KIND}}: "workspace: {{KIND}}" would read as nonsense in
# the frontmatter of a file a person has to edit by hand.
notes_stub_fill() {
  local f="$1" ws="$2" name="$3" rid mid
  rid="$(_notes_logical_id "workspaces/$ws/$name.Report")"
  mid="$(_notes_logical_id "workspaces/$ws/$name.SemanticModel")"
  _sub() {
    sed -e "s|{{NAME}}|$name|g" -e "s|{{WS}}|$ws|g" \
        -e "s|{{REPORT_LOGICAL_ID}}|$rid|g" -e "s|{{MODEL_LOGICAL_ID}}|$mid|g" "$1"
  }
  _sub "$f" > "$f.tmp" 2>/dev/null && mv "$f.tmp" "$f" 2>/dev/null
  rm -f "$f.tmp" 2>/dev/null
  return 0
}

# --- optional: checks only this repo can make --------------------------------

notes_audit() {
  local f stem ws rid hit p cur curws dirs lt last d s
  for f in notes/*/*.md; do
    [ -f "$f" ] || continue
    case "$f" in *_TEMPLATE.md|*/_archive/*) continue ;; esac
    stem="$(basename "$f" .md)"; ws="$(basename "$(dirname "$f")")"
    rid="$(sed -n 's/^report_logicalId: *//p' "$f" | head -1)"
    [ -z "$rid" ] && continue

    hit=""
    for p in workspaces/*/*.Report/.platform; do
      grep -qF "$rid" "$p" 2>/dev/null && { hit="$p"; break; }
    done
    if [ -z "$hit" ]; then
      echo "[repo-notes] ORPHAN: $f references logicalId $rid, which no report has. Renamed outside git, or deleted? Move it to notes/_archive/."
      continue
    fi

    cur="$(basename "$(dirname "$hit")" .Report)"
    curws="$(basename "$(dirname "$(dirname "$hit")")")"
    if [ "$cur" != "$stem" ] || [ "$curws" != "$ws" ]; then
      echo "[repo-notes] RENAMED: '$stem' is now '$curws/$cur'. Run: git mv \"$f\" \"notes/$curws/$cur.md\""
      continue
    fi

    # A save made in the Power BI service, not by an agent. The plugin's BEHIND
    # line covers "the entity moved on"; this one says the change arrived from
    # outside the repo, so the diff has to be read before the notes are trusted.
    # Report names contain spaces, so collect dirs into an array; never word-split.
    dirs=()
    [ -d "workspaces/$curws/$cur.Report" ]        && dirs+=("workspaces/$curws/$cur.Report")
    [ -d "workspaces/$curws/$cur.SemanticModel" ] && dirs+=("workspaces/$curws/$cur.SemanticModel")
    [ ${#dirs[@]} -eq 0 ] && continue
    lt="$(sed -n 's/^last_touched: *\([0-9-]*\).*/\1/p' "$f" | head -1)"
    last="$(git log -1 --format='%cs|%s' -- "${dirs[@]}" 2>/dev/null)"
    if [ -n "$lt" ] && [ -n "$last" ]; then
      d="${last%%|*}"; s="${last#*|}"
      case "$s" in Auto-commit*|Committing*)
        [ "$d" \> "$lt" ] && echo "[repo-notes] SERVICE EDIT since the notes ($lt): '$s' on $cur ($d). Someone saved in the Fabric service; diff that commit before trusting these notes." ;;
      esac
    fi
  done
}
