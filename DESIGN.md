# Design

## The problem

Reasoning produced while working with an AI coding agent is lost when the session
closes. The code records *what*. Nothing records *why*, what was rejected, or
which apparent bug is deliberate. The next session — or the next person — rebuilds
the reasoning from scratch, or worse, "fixes" something that was a decision.

## The observation the whole design rests on

**A knowledge store survives in exact proportion to how reliably it is read.**

Measured in one real repository over the same three months:

| store | read by | outcome |
|---|---|---|
| a `docs/` folder of ticket-named files | nothing — no reference from the agent's instructions, no hook | **abandoned**, 12 files, last touched 3 months prior |
| the agent's own auto-memory directory | every session, automatically | **128 files**, actively growing |

Same author, same period, opposite outcomes. The difference was retrieval — not
discipline, not capture tooling, not templates.

So: **wire retrieval first, capture second.** Every choice below follows.

## Why entity-keyed, not decision-keyed

Most prior art — ADR logs, MADR, and the decision-log plugins built on them —
keys knowledge by **decision or date**, and retrieves it by reading the last N
entries at session start.

That answers "what did we decide lately". The question at the moment of need is
"I am about to change X, what will bite me". A chronological log cannot answer
it. Nothing in a dated list surfaces when you open one file, and reading the
whole log at session start is the load-everything-always approach that overloads
the agent's instruction file in the first place. At a few hundred facts it either
misses most of them or eats the context window.

**The key must be something the reader already has in hand.** Usually that is a
path.

| moment of need | in hand | so the key is |
|---|---|---|
| editing a file | the path | path glob |
| performing an operation | the operation | platform / tool |
| an output looks wrong | the object name | entity |
| resuming your own ticket | the ticket id | ticket — the only case an ADR log fits |

That last row is why ticket-named files die: they serve the one need already met
by personal memory.

## Three tiers, by trigger

| tier | trigger | mechanism |
|---|---|---|
| platform trap | performing an operation | rule file auto-loaded by path glob, plus prompt-keyword routing |
| entity WHY | touching that entity's files | `notes/<kind>/<name>.md`, injected on first touch |
| one object | reading that object | its own docstring or description — **not** a separate file |

Tier three is a rule, not an omission: **if a fact is already true in the code,
or a docstring can carry it, fix the code and write nothing.** A stale docstring
is worse than a missing note, because it actively misleads.

Observed cost of ignoring this: two data models opened with the identical line
"Append-only audit log for …" while being opposite shapes. Treating one as the
other would have destroyed roughly nine months of history held nowhere else.
The docstrings were the trap; a separate notes file would not have been read in
time.

## Why the entity differs per repo and the mechanism does not

The same design was applied to three repositories with three different entities:

| repo shape | entity | derived from |
|---|---|---|
| Airflow + dbt | source pipeline, mart domain | model directory prefixes |
| BI reports | report | one directory per report |
| Terraform | provider module | `modules/<provider>` |

Entity resolution is irreducibly repo-specific. Everything else — session state,
once-per-entity gating, injection, the stop gate, the audit, the commit gate — is
not.

**That boundary is the contract.** The plugin owns the mechanism. The consuming
repo supplies `.claude/notes.conf.sh`, which answers four questions: what
entities exist, which entity does this text refer to, where does its notes file
live, and which paths does it own.

## Anti-rot: anchors

An entry may cite `path :: literal string`. The audit greps for it. If the string
is gone, it reports a stale anchor.

This is the check that earns its keep. In the first session that used it, it
caught three errors in freshly written notes: a directory renamed months earlier
and still cited, a role mapping copied from a stale document, and several
cross-links broken by a rename in the same commit. Decision-log tooling detects
none of these, because none of it binds a claim to a string in a file.

## Coverage as a rule

An entity with no notes file is a gap, not a default. Enforced at two moments:

- **commit** — adding a file under a *new* entity with no notes file blocks the
  commit. Only added paths are inspected, so it fires on new entities and never
  nags about pre-existing gaps.
- **session start** — the audit lists entities missing a file.

With the escape hatch that keeps it honest: an entity with nothing worth
recording says so in one line. Eight empty sections dilute the files that carry
real warnings, which is exactly how the abandoned folder died.

## Confidentiality is structural

These files are committed and team-visible, and the repositories that motivated
this carry salary rows, HR absence data and named individuals. So:

- no hook reads the transcript or tool output — only paths and tool names
- the template has typed fields and no free narrative slot
- the template, the rule file and the stop prompt all forbid a name, a salary or
  any per-person figure

The absence of a free-text field does more work than any warning.

## Fail open, always

Every hook path exits 0 unless it is deliberately emitting decision JSON. A
broken hook degrades to "no capture" and never blocks work. Subagents are ignored
entirely — they inherit no obligation to write notes, and their findings reach
the main session anyway.

## What is deliberately not solved

- **Forward planning.** This captures retrospectively. Spec-driven workflows
  cover the prospective half and compose with this rather than competing.
- **Per-object notes.** See tier three.
- **Cross-repo facts.** A fact about repo B belongs in repo B.
