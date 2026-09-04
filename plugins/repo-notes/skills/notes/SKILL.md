---
description: Record or read the WHY behind an entity in notes/. Use when the user says /notes, asks to write up or record what was decided, asks why something is built the way it is, or when a session produced a decision the stop gate did not catch (a pure investigation with no file edit).
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
