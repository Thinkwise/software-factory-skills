---
name: thinkwise-sf-control-procedures
description: Reference guide for creating and assigning control procedures in a Thinkwise Software Factory model — code groups, business-logic variables, static/SQL assignment, dynamic model code, multi-RDBMS dialects, and SQL coding guidelines. Use whenever creating, assigning, reviewing, or troubleshooting a control procedure or its template SQL via an MCP connector with Software Factory access.
---

# Creating Control Procedures in the Thinkwise Software Factory

Reference for the full control-procedure lifecycle: control procedure → template → program object
item → program object (generated stored procedure/trigger/function/view/etc., deployed to the
database, executed by the GUI or Indicium). Apply this whenever an MCP connector with Software
Factory access (`sf_mcp`, `indicium`) is used to create, assign, or inspect control procedures Relevant entity sets: `control_proc`, `control_proc_template`, `code_grp`, `prog_object`,
`prog_object_code`, `prog_object_item`, `prog_object_item_parmtr`, `generate_object_code`,
`branch_rdbms_type`, and — for the Task code type specifically — `task`, `tab_task`, `task_parmtr`
(see "Creating a brand-new Task" below). Relevant tasks — two distinct ones, not interchangeable (see "Actually
generating code" below): `task_generate_code_grp` (bound to `control_proc` and to the Assigning
screen's `static_assignment_overview`) creates missing `prog_object` placeholders but does not itself
produce code; `task_add_job_to_generate_object_code` (bound to `prog_object_code`/
`prog_object_overview`) is what actually queues a generation job and writes
`prog_object_generated_code`. Domain keys observed in this environment: `manage_model`/`data_modeling`
(meta-model entities) and `manage_functionality` (Functionality screen tasks) — try these directly
first (e.g. a `get_entity_definition`/`search_domain_capabilities` call against the expected domain);
only fall back to `search_capabilities`/`get_available_domains` on an
`entity_set_not_found`/`domain_not_found`-style rejection, rather than re-discovering the domain
pre-emptively every time.

## Before writing anything: confirm the plan

This skill's confirm-before-mutate obligation (see `thinkwise_sf_base`'s "Shared
conventions") has a concrete shape here: before the first `stage_resource` call touching
`control_proc` (or any related entity), state the plan in plain language and get the user's
explicit confirmation. At minimum, name:

- **Logic concept** — which row of the "Choosing the right logic concept" table below (Default,
  Layout, Context, Process, Trigger/Event, Task, Badge, Change detection, Handler, Subroutine, …),
  and why that one.
- **Code group** — the specific `code_grp_id` that concept maps to.
- **Target object(s)** — the table/column/task/view this will be assigned to.
- **Static vs. SQL strategy** — which one, and why (see "Static vs. SQL-typed control procedures"
  below for the trade-off to lay out).

Only stage the `control_proc` row once the user has confirmed this plan — don't treat naming a
code group or picking an assignment type as a mechanical detail to decide silently on the way to
step 3 of "Creating and assigning a control procedure" below.

## Check `branch_rdbms_type` first — before writing a single line of SQL

**Do this before writing any template, every time, no exceptions.** Query which platform(s) the model
actually targets:

`execute_odata_query` → `/branch_rdbms_type?$filter=model_id eq '<model>' and branch_id eq '<branch>'`
→ one row per enabled platform: `rdbms_type` (byte enum: `0` SQL Server, `1` DB2 iSeries, `3` Oracle,
`4` PostgreSQL) + `rdbms_name`.

**Why this has to come first, not "whenever it seems relevant":** verified live — a model enabled for
PostgreSQL only (`branch_rdbms_type` returns a single `rdbms_type = 4` row) was handed a control
procedure template written from habit in T-SQL (`getdate`, `dateadd`/`datediff`, `select top n`).
Every `stage_resource`/`patch_resource`/`commit_resource` call along the way reported success —
**there is no dialect validation at write time.** The mistake only surfaced by explicitly reading the
generated `prog_object_generated_code` text afterward and noticing it wasn't valid PostgreSQL. Treat
"it committed" and "it generated" as proof of nothing about dialect correctness; only reading the
actual generated SQL (or checking `branch_rdbms_type` up front so the mistake can't happen) does that.

### Single row returned → single-dialect model
Write the one template in that platform's dialect — before writing any SQL, read
`references/sql_dialects.md` for the dialect/helper-function tables covering all four platforms.
`rdbms_type` is auto-filled consistently across `col`, `dom`, `prog_object`, `prog_object_code`, and
`template_prog_object_item` — no special handling needed beyond writing the right dialect in the
first place.

### More than one row returned → a multi-dialect model

More than one `branch_rdbms_type` row means every hand-written template must exist **once per
dialect**, and the work is shaped differently — not merely translated. Before writing any SQL on such
a branch, read `references/multi_dialect_models.md` (per-dialect template rows, what must be authored
twice, generating per `rdbms_type`, and the traps that only surface on the second platform).

## Static vs. SQL-typed control procedures

A **static** control procedure holds literal template SQL. A **SQL-typed** one generates its own
template text at generation time from a query — use it only when the code genuinely varies per
object/column; a static one is easier to read and review. `control_proc_type` separates your custom
logic from generated framework infrastructure; keep custom work out of the framework types.

For the generation strategies available to SQL-typed procedures and the full `control_proc_type`
breakdown, read `references/control_proc_types.md`.

## Choosing the right logic concept — before picking a code group

| Requirement | Concept |
|---|---|
| Fill or recalculate an entered value | Default |
| Show, hide, lock, or require fields/buttons | Layout |
| Enable tasks, reports, or detail tabs for the selected row | Context |
| Route the next step in a process flow | Process |
| Enforce integrity for all database writes | Trigger/Event, or a declarative constraint |
| Let a user or scheduler execute a command | Task |
| Show a numeric notification | Badge |
| Decide whether auto-refresh is needed | Change detection |
| Replace generated GUI/API insert/update/delete SQL | Handler |
| Reuse a database calculation or command from >1 caller | Subroutine |

For the full per-concept good-uses/avoid/best-practices, the Handler-vs-Trigger distinction, the
"choosing where a rule belongs" decision sequence, performance/security guidance, common failure
patterns, and a testing checklist by concept, read
`references/logic_concept_design_guide.md` before writing the actual business logic — the rest of
this file covers how to wire whatever concept you land on through the API, not which one to pick or
what it should contain.

## Code groups (the 24 "code types")

**Pull the live list from the `code_grp` entity set — don't assume which of the 24 groups exist or
what they're called.** This is the authoritative source; anything hardcoded here can drift stale.

Two broad families exist:
- **Business-logic groups** fire per-record/session and expose runtime `@`-prefixed variables (see
  next section).
- **Structural/generator groups** emit schema DDL or platform wrappers — just SQL text with
  `[PARMTR]` substitution, no business-logic variables.

A small illustrative subset — **non-exhaustive, and possibly stale; confirm against `code_grp`
before relying on any of these names**:

| `code_grp_id` | Family | Notes |
|---|---|---|
| `DEFAULTS` | Business-logic | Default concept |
| `HANDLERS` | Business-logic | Replaces generated insert/update/delete SQL |
| `TASKS` | Business-logic | Task code type |
| `PROCEDURES`/`FUNCTIONS`/`TABLE_VALUED_FUNCTIONS` | Business-logic | Subroutines, called "Other" in some docs |
| `VIEWS` | Structural | View SELECT code |
| `SMOKE_TESTS` | Structural | SQL Server/Oracle only; doesn't cover subroutines/handlers/tasks — those need real parameter values. A step timing out after 10 s marks a view/procedure to optimize |
| `UPGRADE` | Structural | Migration scripts |
| `MANUAL` | Structural | Catch-all for freeform SQL not tied to any generated program-object type — brings one-off scripts (seed data, ad hoc maintenance) under the normal development-status/review/deploy lifecycle instead of running them by hand outside the Software Factory. Easy to miss. |

**A script in `UPGRADE`/`MANUAL` runs as raw SQL directly against the tables — it does not go
through those tables' Handlers.** Handlers are separate generated stored procedures invoked by the
application/API layer on insert/update/delete, not database triggers, so a seed/migration script
inserting or updating rows bypasses them entirely, with no error or warning. Any derived/computed
state a Handler would normally maintain for those rows (a cascading rollup, a computed status, an
audit stamp) has to be replicated explicitly inside the seed/migration script itself if the seeded
data depends on it — don't assume seeding a table's base columns is enough just because a Handler
exists on it.

**Two separate enablement gates exist — a table-level one and a column-level one — and NEITHER is
auto-enabled by assigning a template.** Verified wrong in an earlier version of this doc: assigning a
template to `default_absence`/`default_lead` via `template_prog_object_item` and re-running
`generate_code_grp` did *not* turn on the table's Default concept — `tab.use_defaults` stayed `false`
even though the `prog_object` rows already existed and the assignment showed up correctly in
`prog_object_item`. The work looked complete (structural wiring verified, code regenerated) but the
logic would never have actually run. Check and set **both** gates below before considering an
assignment done.

### Enablement flags — two gates, neither auto-enabled

**Assigning a template does not turn the concept on.** There are two independent gates — a
table-level one (`tab.use_defaults`, `use_layouts`, …) and a per-column one — and **neither is set
for you** when a template is assigned and code regenerated. The work can look complete (wiring
correct, code generated, no error) while the logic never runs.

Verify both before declaring a Default/Layout/Context concept working. For which flag governs which
concept at each level, read `references/enablement_flags.md`.

## Variables — three different things, resolved at three different moments

1. **Template `[PARMTR]`** — plain text substitution at code-generation time, before compilation.
   Filled per static assignment or per SQL-assignment query row. Can substitute a column/table name,
   not just a value — a bare numeric literal works too (e.g. `dateadd(day,[days],@date_from)`).
2. **Business-logic variables** — real stored-procedure parameters (`@activated`, `@badge_value`,
   …), resolved at runtime. Set depends entirely on code type (below).
3. **Generated session variables** — session-scoped context available in *any* logic concept via
   `SESSION_CONTEXT(N'…')` (SQL Server) or `current_setting('…', true)` (PostgreSQL): `tsf_appl_id`,
   `tsf_appl_alias`, `tsf_appl_lang_id`, `tsf_global_lang_id`, `tsf_client_instance_id`, `tsf_ipv4`/
   `tsf_ipv6`, `tsf_is_public_request`, `tsf_original_login`, `tsf_use_log_session_id`, `tsf_guid`
   (deprecated).

### Business-logic variables by code type

Full per-code-type input/output variable table (Default, Layout, Context, Trigger/event, Handler,
Change detection, Badge, Process, Task), the Handler-Update PK-parameter gotcha (`@upd_[pk_col_id]`
vs. `@[pk_col_id]`), the `@cursor_from_col_id` initial-default-vs-reactive-recompute pattern, and the
dialect-dependent variable-name-prefix note (`@[col_id]` T-SQL vs. `p_[col_id]` PostgreSQL) all live in
`references/code_type_variables.md` — read it once the target code type is known, to get the exact
input/output variable names for that code type before writing the template body.

## Assignment types

A template reaches a generated object either by **static assignment** (an explicit
`template_prog_object_item` junction row) or **dynamically** from a SQL-typed procedure.

Three things to carry:

- **Generating code is two distinct tasks** — `task_generate_code_grp` (materializes the
  `prog_object` placeholder; produces *no* code) then `task_add_job_to_generate_object_code` (queues
  the real generation). A `successful` status is not proof your logic made it in — read the generated
  text.
- **Order the properties in a write** so a dependent field comes after what it depends on, and never
  give a custom `prog_object_item` the same `order_no` as a framework wrapper item — ties break
  alphabetically and fail at *deploy* time.
- **`prog_object.control_proc_id` does not tell you whose logic is in there** — read the generated
  code's header comments instead.

For the full reference (the junction entities and their keys, parameter substitution, the ordering
rules, the complete two-task sequence with its failure modes, and the known standalone-subroutine
gap), read `references/assignment_and_generation.md`. Before writing anything new, check the reuse
decision order and how generated code round-trips to its template in
`references/reuse_and_round_trip.md`.

## Creating and assigning a control procedure — step by step

1. **Query `branch_rdbms_type`** (see above) — know before anything else whether this is a
   single-dialect or multi-dialect model, and which platform(s) that means writing for.
2. Business Logic → Functionality (six tabs: Control procedures, Templates, Assigning, Deploy, Unit
   tests, Code review).
3. Create the control procedure: purpose-driven ID (see naming below), pick its code group, pick
   assignment type (Static to start; SQL if objects will clearly fan out). Multi-dialect: one
   `control_proc`/template set per platform (see step 1's section above) — decide this now, not after
   the first template is already written.
   **Staging mechanics**: `control_proc` is a dependent record of `branch` — a bare
   top-level `stage_resource` add returns `parent_context_required`; stage it with
   `parent_entity_set: "branch"` and `parent_key: {model_id, branch_id}`. At create time `strategy`,
   `gen_order_no`, and `active` come back `hidden`/`readonly` (their defaults apply — fine for an
   `UPGRADE` seed proc); set `control_proc_type` and `assign_type` in the stage call using their
   **numeric** enum values (e.g. `control_proc_type = 1`, `assign_type = 0`), not the string keys.
4. Add a template but **leave the code blank** — run **Generate code group** first so the Software
   Factory shows the real scaffold and exact parameter set for this code type, instead of guessing.
   **Caveat**: `template_code` can be enforced as a mandatory field by the write API in
   use, rejecting a true empty string. If a blank commit is rejected, use a short placeholder
   (e.g. `-- placeholder`) to get past the mandatory check, then overwrite it with the real SQL once
   the scaffold/parameter set has been seen. **`template_code` is specifically prone to the general
   "last field in a combined write can silently drop" quirk** (see
   `thinkwise_sf_data_model`) — reproduced repeatedly across separate control procedures in
   one session, always when set together with `template_description` or another field in the same
   write. **Re-tested and fixed**: the drop was an ordering artifact, not a genuine random
   bug. Setting `template_description` first and `template_code` last in the same combined
   `stage_resource`/`patch_resource` call (tested on both a fresh add and a later edit) landed both fields
   correctly every time, with no follow-up patch needed. Order the properties this way and re-read the
   result once — there's no need to isolate `template_code` into its own call.
5. Write the SQL against the generated scaffold, in the dialect(s) confirmed in step 1, save,
   regenerate to confirm valid program-object code — then actually read the generated
   `prog_object_generated_code` text, don't just trust that generation completed without error.
6. Assign it (static via Assigning tab, or SQL via staged insert against `#prog_object_item`/
   `_parmtr`). If the target object is new and missing, regenerate the code group first. Multi-dialect:
   one `template_prog_object_item` row per `(rdbms_type, prog_object_id)`.
7. Validate, optionally route through Code review, attach Unit tests.
8. Deploy: stale program objects (auto-flagged once template/assignment changed) get generated and
   pushed from the Deploy tab — all objects or just the touched ones. Multi-dialect: confirm every
   enabled `rdbms_type` generated and deployed, not just the first that succeeded.

### Worked example: an idempotent seed

For a full worked example of weaving idempotent demo/seed data into `ug_after_upgrade_always`
(including why a seed script bypasses Handlers and what that means for derived state), read
`references/worked_example_seed.md`.

## Authoring the SQL itself

Four things govern the SQL you write in a template: the dialect it must be written in, the Thinkwise
SQL style rules, the meta/dynamic-model-code form, and the 2026.2 `_query`-split for calculated
columns. **Read `references/sql_dialects.md` before writing any SQL, and
`references/sql_style_guide.md` before writing or reviewing a body.** Its "Write pushdown-safe
queries" section applies to every `VIEWS` template and table-valued function.

For naming guidelines, the generated code's comment-block header and how it round-trips back to the
owning template, dynamic model code, and the calculated-column `_query` split, read
`references/sql_authoring.md`. For meta/dynamic model code specifically, read
`references/dynamic_model_code.md`.

## Pre-flight checklist

- Before considering a control procedure finished, confirmed with the user whether to clear its
  "in development" status — a Software Factory validation flags any control procedure left flagged
  in-development, and it's easy to forget once the SQL itself is done.
- If the requirement didn't map to exactly one row of "Choosing the right logic concept," asked the
  user which concept(s) to cover rather than silently picking one — some requirements genuinely need
  two layers (e.g. Layout + Trigger/Handler); see `references/logic_concept_design_guide.md`'s
  "Choosing where a rule belongs."
- **Watched for silent truncation** reading back `template_code`/`prog_object_generated_code` — a long
  value can cut off with no error. Re-query in bounded chunks (multiple `substring(field,start,450) as
  cN` aliases per call; ~450 chars each, since even 500 can silently truncate) instead of trusting one
  read is complete.
- Requested `get_entity_definition` one entity at a time rather than batching several in one call —
  an entity with an `unlink_generated_object` bound task can balloon the response past the token
  limit. `control_proc` and `control_proc_template` are both in this category (verified live: a
  batched `get_entity_definition` for the pair overflowed at ~80KB). A `$top=1` sample read answers
  "what fields does this have" more cheaply when that's the only real question. Likewise, a plain
  `execute_odata_query` listing *all* `control_proc` rows for a model overflows (~55 framework rows
  each carrying long text) — filter by `code_grp_id` and/or `control_proc_type` (and avoid a
  `$select` that pulls `control_proc_code`/template bodies).
- Checked `col.calculated_field_type` (and the wider `_query`-split family) before writing raw DML —
  see `references/calculated_columns_query_split.md`.
- On PostgreSQL, checked every `calculated_column` expression for non-`IMMUTABLE` functions
  (`concat`, etc.) before generating — see `references/sql_dialects.md`'s IMMUTABLE note; `42P17`
  means a function used there isn't immutable.
- If a template branches on a fixed-value (enum) domain column (a `case`/`if` keyed by e.g. a
  stage/status column), looked up that column's real per-element stored value from the domain's
  element list — the same lookup the mock-data guidance already requires for enum columns — rather
  than assuming the elements' display order maps directly to sequential integers, before hardcoding
  literals in the `case`/`if`.
- After a brand-new static assignment, re-ran `task_generate_code_grp` bound to your *own* control
  procedure (not the bootstrap one) before generating, and read the generated text back to confirm
  your logic — not just the status — actually landed. See point 5 of "Actually generating code"
  above. (`prog_object` itself stays non-writable throughout; always go through that task.)

