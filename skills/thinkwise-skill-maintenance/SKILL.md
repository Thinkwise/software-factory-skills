---
name: thinkwise-skill-maintenance
description: Mine this conversation's errors, corrected assumptions, and workarounds to propose generic, connector-agnostic improvements to Thinkwise skill files — or run a structural/context-window-efficiency pass over the skill files themselves. Presents proposed changes and asks for confirmation before editing anything. Use for "review this session for skill-improvement opportunities", "update the skills based on what went wrong", or a skills context-efficiency review. Not for code review or unrelated one-off bug fixes.
---

# Thinkwise Software Factory — Skill Improvement Suggestor

Turns friction that already happened in *this* conversation into durable improvements to the
`thinkwise_*` skill files (or any other skill file whose subject matter the friction touched), so the
same mistake doesn't have to be rediscovered in a future session. This is a **process** skill, not a
reference skill: it has no domain knowledge of its own, it mines the conversation transcript already
in context and edits other skills' `SKILL.md` files.

**Runs inline in the main conversation, never as a delegated subagent.** The whole premise is
analyzing *this* conversation's actual tool calls and errors — a fresh subagent has none of that
history and would have nothing to analyze.

## When to use

- The user explicitly asks for this ("suggest skill improvements from this session", "what should we
  update in the skills after today", "capture what we learned").
- The user asks for a structural/context-window-efficiency pass over one or more skill files ("make
  this skill more efficient", "trim the descriptions", "split this into references") — this doesn't
  require mining conversation errors, it's a direct structural audit; go straight to "Context-efficiency
  tactics" below instead of step 1's error-mining.
- Don't self-trigger this proactively at the end of every session — it's a deliberate, user-invoked
  review step, not an automatic wrap-up action.

## Process

### 1. Mine the conversation for candidate findings

Re-read the conversation's actual tool calls and results (already in context — no extra tool needed
for this step) looking for:

- **Tool/API errors** that weren't simply invalid requests on the first try for an obvious reason —
  especially ones where the fix wasn't discoverable from the error message alone (wrong error class,
  misleading status code, silent failure with no error at all).
- **Places where a documented skill step didn't work as written** and a workaround was needed —
  e.g. a skill says a field can be left blank and the API rejected that; a skill says one call
  regenerates something and it didn't.
- **Places where the user corrected an approach** that a skill had recommended, or corrected a
  factual claim a skill made.
- **Repeated patterns** — the same failure shape recurring across two or more unrelated entities/
  calls is a much stronger candidate than a single isolated failure (it indicates a systemic quirk of
  the API/platform rather than a one-off).
- **Context-efficiency friction** — evidence that a skill's *structure*, not its content, cost
  unnecessary tokens this session: a skill's description was long enough to visibly truncate in the
  skill listing; a skill's entire body loaded for a narrow sub-task and most of it turned out
  irrelevant; near-identical explanatory boilerplate was restated across two or more skills touched in
  this session. These findings are drafted differently from content lessons — see "Context-efficiency
  tactics" below rather than step 4.

### 2. Filter candidates — not everything belongs in a skill

Drop or set aside (don't propose an edit for):
- **Environment-, account-, or permission-specific failures** that a skill rewrite can't fix — e.g. a
  write blocked by a licensing/authorization gap specific to one connection, a stale OAuth token, a
  network error. These are real, but the fix is "reconnect/request access," not "change the
  documentation." If genuinely useful to flag, list them separately under "not a skill issue" in the
  proposal rather than mixing them into the edit list.
- **Findings already documented** in the target skill — grep the candidate skill file for the same
  behavior before proposing anything; don't produce a duplicate or near-duplicate of existing content.
- **One-off mistakes with an obvious cause already visible in the error message** (a typo'd field
  name, a genuinely malformed request) — these don't generalize into a durable lesson.
- **Anything that's really a data-modeling/business-logic mistake**, not a tooling/API/skill-content
  problem — e.g. picking the wrong primary key for a view is a modeling error to fix in the model, not
  a skill gap (unless the skill's guidance actively led to the wrong choice).

### 3. Map each surviving finding to a target skill file

For each finding, identify which existing skill file is the natural home — usually the one whose
subject matter the failing call was about (a view-generation quirk goes in the view-creation skill; a
column/domain quirk goes in the data-modeling guidelines skill). If a finding applies broadly across
many entity types rather than one specific workflow, prefer the most general/foundational skill in the
family over a narrow workflow-specific one. If no existing skill is a good fit, say so in the proposal
instead of forcing it into an unrelated file — creating a *new* skill is a separate, larger decision
the user should make explicitly, not something to bundle into this process silently.

For a **context-efficiency finding**, the target is normally the skill exhibiting the bloat itself
(its own SKILL.md and, where relevant, its own `references/` folder) — not a different skill chosen by
subject matter.

### 4. Draft each suggested addition — generic and connector-agnostic, always

This step covers **content-lesson findings** (errors, corrected assumptions, workarounds). For
**context-efficiency findings**, draft the change using "Context-efficiency tactics" below instead —
those produce a structural edit (split/trim/merge/dedupe), not an inserted lesson bullet, but still go
through the same propose-then-confirm flow (steps 5-7).

**This is the part most likely to get sloppy under time pressure — don't let it.** Every suggested
skill addition must read identically regardless of which MCP connector, tool-name prefix, or vendor
integration was actually used to surface the finding in this session. A future session may be using a
differently-named connector against the same kind of Software Factory backend; wording tied to one
connector's specific tool names silently stops applying the moment the connector changes.

**Concretely, when drafting the addition text:**
- **Never name the specific MCP server/connector instance** used in this session (no literal
  connector names like the user's own config names). Refer to it generically: "the write API in use",
  "a metadata-driven modeling API", "the connector", "this kind of staging/commit API".
- **But do scope a fact that depends on the environment.** First decide whether the behaviour would
  differ under another connector profile, Indicium domain layout, surface or meta-model version
  (`thinkwise-sf-base`'s `references/connector_profiles.md`). If the session only saw one environment
  and the fact plausibly depends on it (a route, a domain name, a refused add, a question tool), add the
  matching profile tag — `(Indicium · single-domain)`, `(Indicium · split-domain)`, `(legacy
  sf-mcp-server)`, `(Claude Code)`, `(claude.ai/ThinkIT)`, `(older meta-model)` — and, where known, the
  alternative for the other environment. A fact about the Software Factory meta-model itself (field
  names, enums, what a field does) gets no tag. If a new difference between layouts turns up, also add
  it to the table in `connector_profiles.md`.
- **Never hard-code a specific tool-call function name** that's an artifact of one connector's tool
  surface (e.g. a particular `stage_x`/`patch_x`/`commit_x`-style function name), *unless* the skill
  being edited already establishes that naming as its own convention throughout the rest of the file —
  in that case, match the file's existing convention instead of introducing a second one. When in
  doubt, describe the *behavior* ("adding a record and setting its fields before committing it") rather
  than a specific function call.
- **Do** name the Software Factory **entity/field names** involved (e.g. `template_code`,
  `primary_key`, `tab_id`) — those are properties of the Thinkwise model/metadata itself, not of the
  connector, and are exactly what makes the finding useful to a future reader.
- **Do** describe the failure mode precisely enough to be recognizable (status-code class if relevant
  and not connector-specific, e.g. "rejected with a validation-style error" vs. "returned no error at
  all but didn't persist" — these are different symptoms needing different responses).
- **Never refer to the product as "Studio" or similar phrasing** (e.g. "the Studio", "Modeler Studio").
  Always call it the **Software Factory**. This applies to every drafted addition, regardless of which
  term the transcript being mined actually used.
- Write each addition in the same voice/format as the surrounding skill content (verified-live framing,
  terse, imperative where it's an instruction) — match the target file's existing style rather than
  introducing a new tone.
- Prefer **small, targeted insertions** at the most relevant existing point in the file (inline
  callouts, a new checklist bullet, a new numbered sub-step) over a big bolted-on new section, unless
  several findings share a theme general enough to warrant one new consolidated section — mirror
  whatever structure the target file already uses for similar asides.

### 5. Present the full proposal and stop — do not edit anything yet

Show the user, before touching any file:
- A short summary table or list: **finding → root cause → target skill file → one-line description of
  the proposed addition** (not the full inserted text yet, just enough to evaluate each one).
- Anything filtered out under step 2 as "not a skill issue," listed separately and briefly, so the
  user knows it was considered and deliberately excluded.
- Any finding with no good target skill, flagged as such.

Then explicitly ask for confirmation before making changes — via the surface's structured question
tool (`AskUserQuestion` in Claude Code, `ask_user_input_v0` in claude.ai/ThinkIT) if the shape fits
(e.g. apply all / pick specific ones / apply none), or a direct question in text if it doesn't. Do not
proceed to edit any file until the user has responded. A list of proposed changes is not itself
permission to apply them.

### 6. Apply only what was confirmed

- Edit exactly the confirmed items, using the smallest targeted edit that fits the finding (see step 4)
  — don't rewrite unrelated parts of the file, don't restructure sections that weren't asked about.
- If the user confirmed a subset, apply only that subset — don't silently include the rest.
- Preserve each target file's existing frontmatter, heading structure, and formatting conventions.

### 7. Report back

After applying, give a short per-file summary of what actually changed (file → section → one-line
description), matching the granularity of the original proposal so the user can verify what happened
against what they approved.

## House style — binding on every edit, not just efficiency passes

The tactics below fire only when someone explicitly runs an efficiency pass. These rules govern
*every* addition, which is what stops a corpus from re-inflating between passes. Apply them when
drafting any suggested addition in step 4, and treat a violation in existing text as a finding.

1. **Write the rule, not its discovery.** No "verified live", "confirmed live", "an earlier version
   of this doc got it wrong", "a real session hit this three times". A reader cannot act differently
   on a stamped rule than an unstamped one, and the narration is usually 5-10x the length of the
   imperative it wraps. State the fact and the instruction; drop the provenance.
   **A scope tag is not provenance.** `(Indicium · single-domain)` changes what the reader does — it
   tells them whether the rule applies to their setup — so keep it; "verified live on 2026-08-06" doesn't,
   so drop it.
   *Before (118 words):* "`template_code` is specifically prone to the general 'last field can
   silently drop' quirk — reproduced repeatedly across separate control procedures in one session
   … Re-tested and fixed, verified live: the drop was an ordering artifact…"
   *After (10 words):* "Set `template_description` before `template_code` in the same write."
2. **Never restate the MCP server's own instructions.** The connector's canonical discovery→act flow
   ("search_capabilities → get_entity_definition → stage/patch/commit", "never guess entity or
   property names") is in context on every turn already. A skill carries only its own domain key.
3. **Never hardcode what `get_entity_definition` returns.** It returns every field name, type, enum
   value *with its integer*, description, key role, navigation property, bound task, and
   `allow_add`/`allow_update`/`allow_delete` — from a call that is required before writing anyway.
   Carry only the **API-invisible delta**:

   | The API already gives you | The skill must carry |
   |---|---|
   | names, types, enum values + integers, descriptions | write-**order** constraints |
   | keys, navigation properties, bound tasks | fields silently rejected despite reading as editable |
   | `allow_add` / `allow_update` / `allow_delete` | *when* to set a field, and the anti-patterns |
   | | multi-entity recipes and routing quirks |

   A small illustrative subset is acceptable only when labelled non-exhaustive with the live-fetch
   instruction stated first and more prominently.
4. **One pre-flight checklist per skill, at most 8 bullets, genuine gates only.** A gate qualifies
   only if it is *not* already stated in the body and *not* owned by another skill. Delete any bullet
   ending in "see X above", restating mcp_base's conventions, or repeating the icons/translation/
   `branch_rdbms_type` rules. Never add a second summary section ("Known pitfalls") alongside it
   unless its content is genuinely absent from the body.
5. **New sub-topics go to `references/`, not into `SKILL.md`.** Use the house router shape:
   `# <N>. <Topic>` then one sentence — *"For <topic> (<manifest naming the fields, the named gotcha,
   step-by-step, pitfalls>), read `references/<file>.md`."* The parenthetical is a **contents
   manifest, not a summary**: it names artifacts without explaining them, so a reader can decide
   whether to open the file without guessing. `thinkwise-sf-subject-components` is the
   reference implementation.
6. **A `SKILL.md` over ~250 lines is a defect to split, not a file to append to.**
7. **Never duplicate across skills.** One canonical home per fact, a one-line pointer everywhere else
   — never the full explanation twice. `mcp_base` owns the shared conventions and write hazards;
   `conditional_layouts` owns the "should this object get one?" test; `tasks` owns task creation
   order; `translation_objects` owns the translation gate; `icons` owns icon assignment.
8. **When a SKILL.md points at its own reference file, it must not also summarize it.** They load
   together, so the duplication costs twice.
9. **Name a new skill to the established scheme — never invent a prefix.** Exactly three tiers exist:

   | Prefix | For |
   |---|---|
   | `thinkwise-sf-` | Software Factory modeling |
   | `thinkwise-mcp-` | MCP connector tooling |
   | `thinkwise-` | everything else Thinkwise (also used by the externally-synced skills) |

   The topic part is a **noun phrase, never a verb phrase** (`views`, not `create-view`), **plural for
   entity families** and singular for a single concept or process (`tasks`/`cubes`/`menus` vs.
   `deployment`/`base`), and carries **no decorative suffix** (`-component`, `-objects`,
   `-guidelines`, `-suggestor`). Use one word form per concept — `data-model`, never
   `datamodel`/`datamodeling`.

   The directory name and the frontmatter `name:` **must be identical**, and skills cross-reference
   each other by that **exact hyphenated name** (`thinkwise-sf-tasks`), as the Skill tool lists it —
   never an underscore variant. When renaming, replace longest-name-first
   with a guard (`(?![A-Za-z0-9_-])`) so a memory slug that merely *starts with* a skill name —
   `thinkwise_software_factory_cubes_skill_added` — is never rewritten, and watch for skill names
   wrapped across two lines.

## Context-efficiency tactics (reference checklist for structural findings)

Claude Code Skills cost tokens in two places: the frontmatter `name` + `description` load into
**every** conversation regardless of whether the skill is ever used (always-on tax), and the full
`SKILL.md` body loads in one shot the moment the skill is invoked — unless it points to separate files
under a `references/` subdirectory that only get read on demand for a specific sub-topic. A skill that
is one giant monolithic file pays the full cost on every invocation even when the task only touches a
narrow corner of it. These tactics were validated end-to-end restructuring eight `thinkwise_*` skills
(see the `thinkwise-sf-data-model` and `thinkwise-sf-*` skills for worked
examples of every tactic below already applied).

**When to consider a skill a candidate**: its `SKILL.md` exceeds roughly 15-20KB / 300 lines, its
`description` runs longer than 2-3 sentences, or a specific section is long (roughly 30+ lines) and
only relevant to a narrow, occasional sub-task rather than the skill's core workflow.

1. **Split occasional-use, self-contained sections into `references/<topic>.md`.** Good candidates:
   large lookup tables, advanced or rare sub-workflows, full verbose code/SQL examples, migration
   guides — anything not needed on a typical invocation of the skill's core workflow. Create a
   `references/` folder inside the skill's own directory, move the section there **verbatim** (this is
   a cut-and-paste-and-point operation, not a summarization — the reference file must contain the full
   original technical detail), and replace it in `SKILL.md` with a short pointer in the same location
   in the document flow (e.g. "For X, read `references/topic.md` before doing Y"). Keep the core
   decision framework / always-needed workflow front-loaded in `SKILL.md` itself — don't move that out.

2. **Trim the frontmatter `description` to roughly 2-3 sentences / 50-70 words.** State the domain
   (the key entities/concepts) and the trigger condition (when to use it) only. Drop exhaustive
   sub-feature enumeration that's already discoverable via headings in the body — that enumeration is
   pure always-on tax paid in every conversation, used or not. A description long enough to visibly
   truncate in the skill listing is a hard signal to trim.

3. **Deduplicate near-verbatim boilerplate restated across multiple skills** — e.g. the same
   tool-routing flow, dialect-check explanation, or code-generation walkthrough copy-pasted into
   several files. Identify the one skill that's the natural canonical home, keep the full explanation
   there, and replace the restatements in the other skills with a short pointer (by skill name/topic,
   not by guessing the other skill's internal file paths) plus a one-line restatement of the essential
   rule — not the full explanation again.

4. **Merge internal duplication within one file** — two sections that re-walk the same ground (e.g. a
   general-case workflow and a specific-scenario variant that repeats most of the same steps). Collapse
   into the shared core plus a short delta section naming only what's actually different ("follow steps
   1-N above, with these additions: ..."). Don't lose any genuinely distinct guidance in the merge.

5. **Fix self-contradicting hardcoded reference data.** If a skill instructs "always fetch X live via
   the API" but also hardcodes a full copy of X inline, the hardcoded copy is dead weight that can
   silently drift stale and contradicts the skill's own advice. Delete it, or keep only a small
   (5-10 row) illustrative subset explicitly labeled non-exhaustive/possibly-stale, with the live-fetch
   instruction stated first and more prominently.

6. **Compress narrative "verified live" transcripts and war-stories into a few bullet facts** that
   preserve the lesson learned without the full formatted transcript/dialogue — the lesson is
   load-bearing, the narration of how it was discovered usually isn't.

7. **Don't trim foundational/high-frequency skills that other skills point to** (e.g. a shared
   data-modeling-conventions skill) — keeping that source dense and authoritative is correct; the
   savings should come from the *other* skills stopping their duplication of it (tactic 3), not from
   thinning the canonical source itself.

When presenting these in step 5's proposal, include a rough size estimate per change where easy to
state (e.g. "split ~230-line section into `references/x.md`") so the user can judge impact alongside
the list.

## Quality bar for a good finding

A finding is worth writing up if a future session, hitting the same situation with a *different*
MCP connector against a *different* Thinkwise model, would still benefit from having read it first.
If the lesson only makes sense in terms of this specific session's connector, model, or one-off
account state, it's not ready to become skill content — either generalize it further or leave it out.
