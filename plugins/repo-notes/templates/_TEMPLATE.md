---
entity: {{ENTITY}}
kind: {{KIND}}
last_touched: {{DATE}} {{TICKET}}
---

# {{ENTITY}}

Code is the truth for WHAT this {{KIND}} does. This file is the truth for WHY.
If the two disagree and the note is marked intentional, ask before changing the
code. Otherwise correct the note.

Platform and tool traps do NOT belong here — they go to the rules directory.
Anything long-form (a spec, a field mapping, a runbook) goes to `docs/` and is
linked from here.

## Read this before changing anything
<!-- One line per thing a cold session would "fix" and break. Point at the
     decision. If there is nothing, leave the single dash. -->
-

## Decisions
<!-- Newest first. Each entry states, in this order:
       what was settled, WHY, what was REJECTED and why, and who asked BY
       ROLE ("asked by the data owner", "engineering call") — never by name,
       see the confidentiality rule below.
     The rejected half is what stops a future session re-proposing a dead end,
     so it is not optional. Inline is fine:
       - **2026-09-02 (ABC-123)** — filter before casting. Rejected: a
         defensive cast, which would mask input errors instead of surfacing
         them. Engineering call.
     If this entity genuinely has nothing non-obvious yet, say exactly that in
     one line. An honest "nothing non-obvious yet, the code is the whole story"
     is useful; eight empty sections are not. -->
-

## Options considered
<!-- OPTIONAL. Only for a decision big enough that the inline "Rejected:"
     clause cannot carry it — a fork with three or more live options, or one you
     expect to be revisited. Otherwise delete this section.

     | Option | Verdict |
     |---|---|
     | <chosen> | Chosen — <why> |
     | <other>  | Rejected — <why> | -->
-

## Intentional oddities
<!-- Looks like a bug, is not. Name the value or behaviour and why it stays. -->
-

## Code anchors
<!-- `path :: literal string` that a decision depends on. The audit greps these,
     so a rename or deletion surfaces as a stale anchor. Verify each one exists
     before writing it. -->
-

## Figures quoted externally
<!-- Numbers given to people outside the session, with the filter state they
     were computed under, so a later disagreement is resolvable. Never a
     per-person figure. -->
-

## Open questions
-
