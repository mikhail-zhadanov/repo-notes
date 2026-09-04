# repo-notes config for a Terraform / Terragrunt repository.
# Copy to .claude/notes.conf.sh and adjust the paths.
#
# The entity is the PROVIDER MODULE: modules/<provider>. One notes file per
# provider records why the resources are shaped that way, which manual steps
# exist outside Terraform, and what must not be "tidied up".

NOTES_DIR="notes"
NOTES_TEMPLATE="notes/_TEMPLATE.md"
NOTES_RULES_DIR=".claude/rules"

NOTES_MUT_RE='(^|[^a-zA-Z_-])(terraform (apply|destroy|import|state)|terragrunt (apply|destroy)|git (commit|mv|rm)|sed -i|mv|cp|rm)([^a-zA-Z_-]|$)'

notes_entities() {
  ls -d modules/*/ 2>/dev/null | sed -E 's#modules/([^/]+)/#module|\1#' | sort -u
}

notes_detect() {
  local text="$1" mods
  mods="$(notes_entities | cut -d'|' -f2)"
  {
    printf '%s' "$text" | grep -oE 'modules/[A-Za-z0-9_-]+' | sed -E 's#modules/#module|#'
    # live/<env> stacks reference a module by name in their terragrunt config
    while IFS= read -r m; do
      [ -z "$m" ] && continue
      printf '%s' "$text" | grep -qE "live/[A-Za-z0-9_/-]*${m}" && printf 'module|%s\n' "$m"
    done <<< "$mods"
  } 2>/dev/null | sort -u | while IFS= read -r it; do
      grep -qxF "${it#*|}" <<< "$mods" && printf '%s\n' "$it"
    done | sort -u
}

notes_file() { printf '%s/notes/modules/%s.md' "$PWD" "$2"; }

notes_dirs() { ls -d "modules/$2" 2>/dev/null; }
