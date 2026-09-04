# repo-notes

Entity-keyed knowledge capture for [Claude Code](https://claude.com/claude-code).

Records **why** a repository is built the way it is — decisions, rejected
alternatives, and which apparent bugs are deliberate — and surfaces it at the
moment of need instead of hoping someone opens a document.

The code is the truth for *what*. These notes are the truth for *why*.

## The problem it solves

Long agent sessions produce durable insight that survives only in someone's head
or in a commit message nobody re-reads. The next session rebuilds the reasoning,
or "fixes" something that was a decision.

Most existing answers are ADR logs keyed by decision or date, read by dumping the
last N entries at session start. That answers *"what did we decide lately"*. The
question at the moment of need is *"I am about to change this file, what will
bite me"* — and a chronological log cannot answer it.

**repo-notes keys on the entity instead, so the right note arrives when you touch
the right files.** See [DESIGN.md](DESIGN.md) for the reasoning and the evidence.

## How it behaves

| moment | behaviour |
|---|---|
| you read or edit an entity's files | that entity's notes are injected into context, once per session |
| you change something and the turn ends | asked once per entity to record what was decided and what was rejected |
| a new entity is committed without notes | `git commit` is blocked, naming the missing file |
| session start | an audit reports missing notes, orphaned notes, and stale anchors |
| `/notes` | manual read/write, for investigations that changed no file |
| `/notes` backfill | bootstrap a repo: mines docstrings, comments, git log and the agent's personal memory into notes files, then gates the result |

Every hook fails open. A broken or unconfigured hook degrades to "no capture" and
never blocks work. **No hook ever reads the transcript or tool output** — only
paths and tool names.

## Install

```
/plugin marketplace add mikhail-zhadanov/repo-notes
/plugin install repo-notes@repo-notes
```

Pick the scope deliberately. **User** scope covers every repo you work in and
stays inert in any repo without a `.claude/notes.conf.sh`. **Project** scope
pins the plugin to one repo, which is not what you want if you use it in
several.

To develop the plugin itself, add your clone as the marketplace instead
(`/plugin marketplace add ~/dev/repo-notes`) — then your edits are live, with no
push-and-update cycle.

### Giving it to a whole team

Declare it in the repo's checked-in `.claude/settings.json`, and a clone needs
no manual install at all:

```json
{
  "extraKnownMarketplaces": {
    "repo-notes": { "source": { "source": "github", "repo": "mikhail-zhadanov/repo-notes" } }
  },
  "enabledPlugins": { "repo-notes@repo-notes": true }
}
```

Both keys apply from a repository file, but `extraKnownMarketplaces` is gated on
each person **trusting the folder** — nothing is fetched or run from a repo they
have not accepted. Until then they get no automation, and the notes still read
fine by hand. Anyone can opt out for themselves with
`{"enabledPlugins": {"repo-notes@repo-notes": false}}` in the gitignored
`.claude/settings.local.json`.

Two things to weigh before doing this in a repo you do not own:

- **`.claude/notes.conf.sh` is executed** (see Security below), so committing
  enablement means committing "this repo runs that file in everyone's session".
  It deserves the review a CI script gets.
- **A marketplace tracks its default branch**, with no version pin. A push to
  the marketplace repo changes every consumer's hooks. If that matters, host the
  marketplace where the same people who own the consuming repos own it.

Then in each repository that should use it:

```bash
mkdir -p notes .claude/rules
cp ~/dev/repo-notes/examples/<closest>.notes.conf.sh .claude/notes.conf.sh
cp ~/dev/repo-notes/plugins/repo-notes/templates/_TEMPLATE.md notes/_TEMPLATE.md
$EDITOR .claude/notes.conf.sh          # define your entities
```

Commit `notes/`, `.claude/notes.conf.sh` and `.claude/rules/` — they are
team-visible knowledge, reviewable in the same PR as the code they describe.

Then bootstrap an existing repo with `/notes backfill`. It mines what is already
there — docstrings, inline comments, `git log`, and the agent's personal memory
directory — into one notes file per entity, and gates the result on coverage,
anchors resolving and a confidentiality scan.

Personal memory is the richest seam, because it is where knowledge went while
the repo had nowhere to put it. It is also the least reliable: it records what
was true when written. Treat it as a lead and verify every borrowed fact against
the code, which is exactly what the anchor check enforces.

## The contract

The mechanism is identical in every repo. Only entity resolution differs, and it
lives in `.claude/notes.conf.sh`:

| function | answers |
|---|---|
| `notes_entities()` | which entities exist — emits `kind\|name` per line |
| `notes_detect "$text"` | which entities does this text refer to |
| `notes_file <kind> <name>` | where that entity's notes file lives |
| `notes_dirs <kind> <name>` | which paths the entity owns |

Plus `NOTES_MUT_RE`, the shell verbs that count as a change so a read-only
command does not arm the gate.

Optionally `notes_suggest "$prompt"`, which routes by **intent** rather than by
path. Path-scoped rules and note injection both need a file to be open in the
turn, but the most expensive knowledge is often needed while merely reasoning —
before anything is opened. Match keywords, print a pointer, stay silent
otherwise. Omit the function and nothing happens.

Three more optional hooks, for repos that know something the mechanism cannot:

| knob | what it is for |
|---|---|
| `notes_stub_fill <file> <kind> <name>` | stamp a new notes file with something only this repo can resolve |
| `notes_audit` | extra audit checks; print anomalies, nothing else |
| `NOTES_SKIP_ORPHAN=1` | suppress the generic orphan line when `notes_audit` reports it better |

The case that motivated them: a Power BI report is renamed in the Fabric
service, and the service commits the rename itself. Keyed on the path, that
looks exactly like "the notes file describes something that no longer exists".
Keyed on the report's `logicalId` — stamped into the frontmatter at creation by
`notes_stub_fill`, checked by `notes_audit` — it is correctly reported as a
rename, with the `git mv` to fix it. See `examples/reports.notes.conf.sh`.

Worked examples in [`examples/`](examples/):

| example | entity |
|---|---|
| `dbt-airflow.notes.conf.sh` | source pipeline, mart domain |
| `terraform.notes.conf.sh` | provider module |
| `reports.notes.conf.sh` | BI report |

## Anti-rot

A note may cite `path :: literal string`. The audit greps for it, so a rename or
deletion surfaces as a stale anchor rather than quietly becoming a lie.

This is the check that pays for itself. On its first real use it caught three
errors in freshly written notes: a directory renamed months earlier and still
cited, a mapping copied from a stale document, and cross-links broken by a rename
in the same commit.

## Where a fact belongs

First match wins, so one fact has exactly one home:

1. about a person, a preference, or ticket status → personal memory, **not** the repo
2. a formatting or naming rule checkable without knowing the data → your style guide
3. a procedure every session needs → the agent's instruction file
4. a platform or tool trap → `.claude/rules/`, auto-loaded by path glob
5. **already true in the code, or fixable in a docstring → fix the code, write nothing**
6. long-form spec, field mapping, runbook → `docs/`, linked from the notes file
7. otherwise, the why behind one entity → `notes/`

Rule 5 does the most work. A stale docstring is worse than a missing note,
because it actively misleads.

## Confidentiality

These files are committed. The template has typed fields and no free narrative
slot; the template, the rules and the stop prompt all forbid a name, a salary or
any per-person figure. The absence of a free-text field does more work than any
warning.

## Security: the config is executed

`.claude/notes.conf.sh` is **sourced**, so it runs as shell with your
permissions whenever a hook fires. Anyone who can land a commit in a branch you
check out can run code on your machine through it.

Judge that against the baseline rather than in isolation: Claude Code already
executes repo-controlled code by design — `.claude/settings.json` hooks, test
runners, build scripts, task definitions. A repo you check out and work in is
already trusted to that degree, and this adds one more file to that set rather
than opening a new class of exposure.

It is still worth knowing:

- **Review `.claude/notes.conf.sh` in PRs like any other executable file.** A
  change to it deserves the scrutiny a change to a CI script gets.
- **Do not enable this plugin while working in untrusted forks.** The hooks fire
  on ordinary tool calls, so there is no moment where you consciously opt in.
- The mechanism never sources anything else, never reads the transcript, and
  never executes note content.

A declarative config would remove this, and was considered. It was rejected
because the two features that have actually caught bugs — the DAG alias map and
intent-based routing — are conditional logic, and expressing them declaratively
means inventing a small language and an interpreter for it. That trade may be
worth revisiting if the plugin is ever used on repos you do not control.

## Tests

```bash
bash tests/test_notes.sh
```

Builds a throwaway repo in a temp directory and exercises injection, the gate,
the once-per-entity guard, the loop guard, subagent suppression, anchor checking,
orphan detection, the commit gate and unconfigured silence. No dependency on any
real project.

## Status

Early. The mechanism is tested; the design is young. Feedback and issues welcome.

MIT.

## Testing the skill, not just the code

`tests/test_notes.sh` covers the hook mechanism. The skill is instructions for a
model, so it gets an eval instead:

```bash
FIX=$(mktemp -d)/eval
bash tests/fixture_skill_eval.sh "$FIX"     # repo with four planted traps
# ...have an agent backfill notes in $FIX, following the skill...
bash tests/grade_skill_eval.sh "$FIX"       # deterministic grading
```

The fixture plants four traps whose correct handling is known, so the result is
graded rather than admired:

| trap | correct handling |
|---|---|
| a docstring giving the **wrong** reason, with the real one only in git history | correct the record, carry the warning |
| a person's name and a salary inside the sentence that carries the fact | keep the fact, drop the person |
| a platform error code in a comment | write it to the rules dir, not notes |
| a docstring that is already correct and complete | one honest line, no paraphrase |

The last two rows are the point: both entities are "documented", but only one is
documented *correctly*, and only the other should be left alone.

Four runs on a deliberately weak model took it from 6/9 to 11/11. Every failure
changed either the skill or the test:

- trap routing was a destination with no action → made "create or append the
  rule file", with both observed failure modes named
- the no-duplication rule was a principle in another section → made a
  pre-drafting gate that names why it gets skipped
- **two failures were the test's fault, not the skill's**: an unanchored `doe`
  matched "does" in boilerplate, and the routing check counted a legitimate
  anchor as misfiling. A grader that cries wolf is worse than no grader.
- one run scored *worse* and exposed a contradiction in the fixture itself: it
  demanded notes for an entity whose docstring was accurate, which is the
  duplication another entity was penalised for
