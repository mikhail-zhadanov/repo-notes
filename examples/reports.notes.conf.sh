# repo-notes config for a BI report repository (one directory per report).
# Copy to .claude/notes.conf.sh and adjust the paths.
#
# The entity is the REPORT. Report names contain spaces, so every loop here
# reads line by line and never word-splits.

NOTES_DIR="notes"
NOTES_TEMPLATE="notes/_TEMPLATE.md"
NOTES_RULES_DIR=".claude/rules"

NOTES_MUT_RE='(^|[^a-zA-Z_-])(set|add|mv|cp|rm|new|batch|restore|replace|rename|delete|publish|sed -i)([^a-zA-Z_-]|$)'

notes_entities() {
  find workspaces -maxdepth 2 -type d -name '*.Report' 2>/dev/null \
    | sed -E 's#workspaces/([^/]+)/(.+)\.Report#report|\1/\2#' | sort -u
}

notes_detect() {
  local text="$1" all
  all="$(notes_entities | cut -d'|' -f2)"
  {
    printf '%s' "$text" \
      | grep -oE 'workspaces/[^/"'"'"']+/[^/"'"'"']+\.(Report|SemanticModel)' \
      | sed -E 's#workspaces/([^/]+)/(.+)\.(Report|SemanticModel)#report|\1/\2#'
  } 2>/dev/null | sort -u | while IFS= read -r it; do
      grep -qxF "${it#*|}" <<< "$all" && printf '%s\n' "$it"
    done | sort -u
}

# "$2" is "<workspace>/<report>", so the notes file nests the same way.
notes_file() { printf '%s/notes/reports/%s.md' "$PWD" "$2"; }

notes_dirs() {
  ls -d "workspaces/$2.Report" "workspaces/$2.SemanticModel" 2>/dev/null
}
