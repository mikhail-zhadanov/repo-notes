# repo-notes config for an Airflow + dbt repository.
# Copy to .claude/notes.conf.sh and adjust the paths.
#
# Entities here are the SOURCE PIPELINE (a source's snapshot and staging models,
# its DAG and its helper modules) and the MART DOMAIN. Both are derivable from
# directory prefixes, which is what makes them usable as a key.

NOTES_DIR="notes"
NOTES_TEMPLATE="notes/_TEMPLATE.md"
NOTES_RULES_DIR=".claude/rules"

# Shell verbs that change something. Read-only calls must not arm the stop gate.
NOTES_MUT_RE='(^|[^a-zA-Z_-])(dbt (run|build|seed|snapshot)|git (commit|mv|rm)|sed -i|mv|cp|rm)([^a-zA-Z_-]|$)'

# --- 1. every entity that exists ---------------------------------------------
notes_entities() {
  { ls -d dbt/models/snap_*/     2>/dev/null | sed -E 's#.*/snap_([^/]+)/#source|\1#'
    ls -d dbt/models/staging/*/  2>/dev/null | sed -E 's#.*/staging/([^/]+)/#source|\1#'
    ls -d dbt/snapshots/*/       2>/dev/null | sed -E 's#.*/snapshots/([^/]+)/#source|\1#'
    ls -d dbt/models/mart_*/     2>/dev/null | sed -E 's#.*/mart_([^/]+)/#mart|\1#'
  } 2>/dev/null | sort -u
}

# --- 2. DAG names that do not contain their entity name ----------------------
# Without these, editing dags/google_import.py surfaces nothing because the
# source directory is called google_analytics. Aliases are additive.
notes_aliases() {
  case "$1" in
    google_import)                echo "source|google_analytics" ;;
    product_downloads_pipeline)   echo "source|s3_product_downloads" ;;
    # ... one line per DAG whose filename hides its entity
  esac
}

# --- 3. which entities does this text refer to? ------------------------------
notes_detect() {
  local text="$1" srcs marts
  srcs="$(notes_entities | grep '^source|' | cut -d'|' -f2)"
  marts="$(notes_entities | grep '^mart|'  | cut -d'|' -f2)"
  {
    printf '%s' "$text" | grep -oE 'dbt/models/snap_[A-Za-z0-9_]+'    | sed -E 's#.*snap_#source|#'
    printf '%s' "$text" | grep -oE 'dbt/models/staging/[A-Za-z0-9_]+' | sed -E 's#.*staging/#source|#'
    printf '%s' "$text" | grep -oE 'dbt/snapshots/[A-Za-z0-9_]+'      | sed -E 's#.*snapshots/#source|#'
    printf '%s' "$text" | grep -oE 'dbt/models/mart_[A-Za-z0-9_]+'    | sed -E 's#.*mart_#mart|#'
    printf '%s' "$text" | grep -oE 'stg_[A-Za-z0-9]+__'               | sed -E 's#^stg_#source|#; s#__$##'
    while IFS= read -r s; do
      [ -z "$s" ] && continue
      printf '%s' "$text" | grep -qE "(dags|include)/[A-Za-z0-9_]*${s}[A-Za-z0-9_]*\.py" \
        && printf 'source|%s\n' "$s"
    done <<< "$srcs"
    while IFS= read -r b; do
      [ -z "$b" ] && continue
      notes_aliases "$b"
    done <<< "$(printf '%s' "$text" | grep -oE 'dags/[A-Za-z0-9_]+\.py' | sed 's#dags/##; s#\.py$##' | sort -u)"
  } 2>/dev/null | sort -u | while IFS= read -r it; do
      # Validate against reality: text that merely MENTIONS a name must not
      # arm the gate unless it is a real entity.
      case "${it%%|*}" in
        source) grep -qxF "${it#*|}" <<< "$srcs"  && printf '%s\n' "$it" ;;
        mart)   grep -qxF "${it#*|}" <<< "$marts" && printf '%s\n' "$it" ;;
      esac
    done | sort -u
}

# --- 4. where the notes file lives -------------------------------------------
notes_file() {
  case "$1" in
    source) printf '%s/notes/sources/%s.md' "$PWD" "$2" ;;
    mart)   printf '%s/notes/marts/%s.md'   "$PWD" "$2" ;;
  esac
}

# --- 5. what the entity owns (for history, anchors, orphan detection) --------
notes_dirs() {
  case "$1" in
    source) ls -d "dbt/models/snap_$2" "dbt/models/staging/$2" "dbt/snapshots/$2" 2>/dev/null
            ls dags/*"$2"*.py include/*"$2"*.py 2>/dev/null ;;
    mart)   ls -d "dbt/models/mart_$2" 2>/dev/null ;;
  esac
}
