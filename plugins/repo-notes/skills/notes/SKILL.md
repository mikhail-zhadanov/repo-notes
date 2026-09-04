---
description: Record, read or backfill the WHY behind an entity in notes/. Use when the user says /notes, asks to write up or record what was decided, asks why something is built the way it is, asks to backfill or bootstrap notes for entities that have none, or when a session produced a decision the stop gate did not catch (a pure investigation with no file edit).
---

# Notes

Manual entry point for the knowledge store. The hooks cover the common path
automatically — an entity's notes are injected the first time a session touches
it, and the stop gate asks once per entity per session after a change. This
skill is for what the hooks cannot see:

- a **pure investigation** that changed no file, so the gate never armed. This is
  where the most expensive knowledge is lost.
- a decision spanning several entities
- reading up before starting work
- the hook being skipped or failing open

## First, learn this repo's entities

`.claude/notes.conf.sh` defines them. Read it. It answers: what entities exist,
how a path maps to one, where the notes file lives, and which paths the entity
owns. Do not guess the layout — repos differ, the mechanism does not.

List them: `bash .claude/notes.conf.sh` is not runnable on its own; instead run
the audit, which reports any entity missing a file.

## Read mode

Resolve the entity from whatever the user gave you (a path, an object name, a
DAG, a module), then read that notes file **in full** before answering.

Never undo anything under "Read this before changing anything" without checking
the decision it points at.

## Write mode

1. **Route first.** One fact, one home. Most importantly: if the fact is already
   true in the code, or a docstring can carry it, **fix the code and write
   nothing.** A stale docstring is worse than a missing note because it actively
   misleads.
2. **Append, do not rewrite.** Add to the relevant section, newest first. Leave
   existing entries alone unless they are now wrong, in which case correct them
   and say so.
3. **Every decision names what was rejected** and why. That is the half that
   stops a future session re-proposing a dead end.
4. **Anchors must resolve.** `path :: literal string`, and the string must appear
   in that file today. Verify with grep before writing it — the audit greps them,
   and a wrong anchor is worse than none.
5. **Bump `last_touched`.**
6. **Never write a person's name, a salary, or any per-person figure.** These
   files are committed and team-visible. Aggregates are fine; a row that
   identifies someone is not.

## Backfill mode

For bootstrapping a repo, or filling entities the audit reports as `MISSING`.

### 1. Find the gaps

Run the audit (below). Every `MISSING:` line is an entity to write.

### 2. Mine four sources, in this order

For each entity, read everything that already exists about it before writing a
word. Ranked by how much genuine WHY they carry:

1. **Docstrings and description fields** in the entity's own files — the header
   comment of each source file, and every description in its schema/config
   files. Usually the richest source, and the place where a *wrong* explanation
   does the most damage.
2. **Comments in the orchestration and helper code** the entity owns. Inline
   comments explaining a workaround are pure WHY.
3. **`git log --format='%s' -- <the entity's paths>`** — commit subjects name the
   decisions and their tickets.
4. **Personal agent memory**, if present. See below.

### 3. Personal memory: how to read it, and what not to take

The agent's own memory directory usually lives at
`~/.claude/projects/<repo-path-with-slashes-as-dashes>/memory/`, with a
`MEMORY.md` index. Glob for it if the derived name does not match.

It is a rich seam — it is where knowledge went while the repo had nowhere to put
it — but most of it must **not** be copied into the repo. Route by the file's own
type or prefix:

| memory kind | destination |
|---|---|
| a user preference, a person, how to work with them | **stays personal.** Never the repo. |
| ticket or project status, what is in flight | **stays personal.** It expires. |
| a platform, tool or CLI trap | the rules directory, not a notes file |
| why one entity is shaped the way it is | the entity's notes file |

**Memory is a lead, not a source.** It records what was true when written and it
goes stale silently. In one real backfill, three separate facts copied from
memory and from an old document were wrong: a directory renamed months earlier
and still cited, a role-to-permission mapping missing three roles added since,
and a set of cross-links broken by a rename in the same commit. All three were
caught only because the anchor check greps against real code.

So: **verify every borrowed fact against the code before writing it.** If you
cannot confirm it, either leave it out or write it as an open question. Prefer
pointing at the authoritative file over duplicating a list that will drift —
"`<macro>` is the authoritative mapping, check it rather than trusting this
copy" beats a copied table.

### 4. Write

Follow Write mode below. Two additions specific to backfill:

- **Never pad.** An entity with nothing non-obvious gets **one honest line**
  under Decisions saying exactly that. Eight empty sections dilute the files
  that carry real warnings, and a folder of placeholders is how the previous
  attempt at this died.
- **Prefer WHY over WHAT, ruthlessly.** "Syncs via the vendor connector" is
  worthless — the code says so. "Filter all three deletion flags because the
  vendor soft-deletes separately from the connector's hard-deletes" is the whole
  point.

### 5. Many entities at once

Group them by domain affinity and fan out one agent per group, so each builds
context once. Give every agent: the entity list, the four sources above, the
routing table, the anti-padding rule, the anchor-verification requirement, and
the confidentiality rule. Have each report per file what it found, plus anything
that belongs in the rules directory instead, plus anything that looked like a
real bug.

Then gate the result deterministically — coverage, anchors resolving, template
conformance, a confidentiality scan, and stub detection — rather than trusting
the reports. In one real backfill this gate caught errors in the reviewer's own
earlier files, not just the agents'.

## Verify

```bash
printf '{"cwd":"%s"}' "$PWD" | bash "$CLAUDE_PLUGIN_ROOT/hooks/notes.sh" audit
```

Silence means: every entity has a file, every anchor resolves, no cited path has
gone stale, and no notes file describes something that no longer exists. It
prints only anomalies.

## Do not put here

Platform and tool traps → the rules directory, auto-loaded by path glob.
Long-form specs, field mappings, runbooks → `docs/<subject>.md`, linked from the
notes file. User preferences and ticket status → personal memory, not the repo.
