---
name: thinkwise-sf-postgresql-migration
description: Step-by-step guide and checklist for adding PostgreSQL as a supported platform on an existing Thinkwise Software Factory application (dual-platform, alongside SQL Server/other platforms already enabled) — enabling the platform, porting every category of hand-written SQL, resolving PostgreSQL-specific validation errors, and the dialect/structural rewrites and tooling quirks discovered doing this live. Use whenever a user asks to add PostgreSQL support to an existing model, migrate/port an application to PostgreSQL, or troubleshoots a PostgreSQL-specific generation/validation error (naming collisions, MERGE/FK errors during generation, etc.) in a Thinkwise model.
---

# Migrating a Thinkwise Software Factory application to PostgreSQL

First version of this skill, distilled from a real, live, single-session migration of a
medium-sized model (RK_SCHEDULER_TEST — ~25 tables, ~150 code objects, ~1000 generated objects once
PostgreSQL was enabled) from SQL-Server-only to dual-platform (SQL Server + PostgreSQL). Every
technique, gotcha, and dead end below was verified live via an MCP connector (`sf_mcp`-style) during
that migration — nothing here is theoretical. Follow `thinkwise_sf_base`'s shared
conventions (confirm-before-mutate, ask-don't-default, the staged add/patch/commit write hazards)
throughout; this skill only adds what's specific to a PostgreSQL migration.

**Scope assumption: this is a dual-platform migration** (PostgreSQL added *alongside* an existing
platform, not replacing it) — the far more common ask, since it carries zero risk to the existing
deployment. If the goal is a full cutover (drop the old platform once PostgreSQL is verified), the
same porting work applies; skip duplicating templates per platform and edit in place instead, and
disable/remove the old `branch_rdbms_type` row as a final step. **Confirm which of the two the user
wants before starting** — it changes whether you create a second template per object or edit the
existing one, which is expensive to unwind after the fact. See `thinkwise_sf_base`'s
"Ask, don't default."

## Before starting: confirm the plan

Per the mcp_base "confirm-before-mutate" convention, applied at this migration's own grain: before
staging the first write, tell the user the shape of the work — which categories from the checklist
below actually have content in this model (query each category first; don't assume), roughly how many
objects that means, and the platform-scope decision above. A migration touches dozens to low-hundreds
of objects; the user should see that scope before it starts, not discover it partway through.

## Step 0 — Enable PostgreSQL (manual, outside the API)

**`branch_rdbms_type` is read-only through every MCP connector checked** (`allow_add`/`allow_update`/
`allow_delete` all `false`, no bound task, no unbound task like `unlink_generated_object.platform`
does what's needed either). There is no API path to enable a platform. **Tell the user to enable it
directly in the Software Factory's own UI** (Project settings for the model/branch → RDBMS types →
enable PostgreSQL) and wait for confirmation before continuing. Verify it took:

```
GET /branch_rdbms_type?$filter=model_id eq '<model>' and branch_id eq '<branch>'
```

Confirmed enum (one gap, not a typo): `sqlserver = 0`, `iseries = 1`, `oracle = 3`, `postgresql = 4`
(no `2`).

## Step 1 — Confirm scope before writing anything

Query `branch_rdbms_type` regardless of what the user says enabled it — confirm live, every time
(see `thinkwise_sf_control_procedures`'s "Check branch_rdbms_type first").
Everything below assumes it now returns at least two rows.

## The full checklist — every category of hand-written SQL/config to migrate

Query each of these against the live model before assuming any category is empty or non-empty — in
the reference migration, domain default queries turned out to be completely empty while calculated
fields and prefilters both had real content. Don't skip a category because a sibling category was
empty.

| # | Category | Where it lives | Per-platform? | Notes |
|---|---|---|---|---|
| 1 | Custom control procedures | `control_proc` where `control_proc_type = 1`, via `control_proc_template` | Yes — one template per platform | The bulk of the work; see "Porting control procedures" below |
| 2 | Framework helper control procedures | `control_proc` rows like `sql_tsf_user`, `sql_tsf_send_message` | Yes, but **auto-provided** | Don't hand-port — see "Framework helpers" below |
| 3 | Calculated field queries | `col_query.calculated_field_query` | Yes (`rdbms_type` in the key since 2026.2) | One row per `(tab_id, col_id, rdbms_type)` — for `calculated_column` rows, also verify every function used is `IMMUTABLE` on PostgreSQL (see dialect reference); `concat` is not |
| 4 | Column-level default value queries | `col_query.default_value_query` | Yes | Same entity as #3, different field |
| 5 | Domain default value queries | `dom_query.default_value_query` | Yes | Was empty in the reference migration — still check |
| 6 | Prefilter queries (query-based prefilters) | `tab_prefilter_query.query` | Yes (as of 2026.2 — see quirk below) | One row per `(tab_id, tab_prefilter_id, rdbms_type)` |
| 7 | Domain/column name collisions | `dom.dom_id` vs. `col.col_id` | N/A — modeling issue, not code | PostgreSQL-specific validation; see "Domain/column collisions" below |
| 8 | Seed/demo data & other `UPGRADE`-group scripts | `control_proc` where `code_grp_id = 'UPGRADE'` and `control_proc_type = 1` | Yes | Large, mechanical, low logical risk — see "Seed data" below |
| 9 | Subroutines never generated before | `subroutine` / `control_proc` (PROCEDURES/FUNCTIONS/TABLE_VALUED_FUNCTIONS) | Yes | Known API gap — see "Subroutines" below |

**What does *not* need touching**, confirmed by inspection rather than assumption:
- Table/column data types (`dom.dttp_id` family) — the framework maps these per platform automatically.
- Generic table/index/constraint/trigger-wrapper DDL (`control_proc_type = 0` rows like `sql_tables`,
  `sql_handlers`, `sql_views`) — Thinkwise's own meta-generator, already dialect-aware.
- CLR objects — if `CLR_ASSEMBLIES`/`CLR_FUNCTIONS`/`CLR_PROCEDURES` have no `control_proc_type = 1`
  rows, there's nothing to port (CLR has no PostgreSQL equivalent; if custom CLR *is* found, flag it
  to the user as a required redesign, not a mechanical port).
- Reports, if the model has none (`report` entity set empty).
- Spatial columns, if location-style data is stored as plain lat/lng `numeric` + JSON text rather than
  SQL Server `geography`/`geometry` — check before assuming a PostGIS dependency exists.

## Step-by-step workflow

1. **Step 0/1 above** — enable the platform, confirm `branch_rdbms_type`.
2. **Verify framework helpers auto-generate** (see below) before touching anything else — if they
   don't, that's a product issue to flag, not something to work around by hand-writing framework code.
3. **Inventory custom control procedures**: `GET /control_proc?$filter=... and control_proc_type eq 1`,
   grouped by `code_grp_id`. This is your real work list — ignore `control_proc_type in (0, 2)` rows
   entirely (see `thinkwise_sf_control_procedures`'s "control_proc_type" section).
4. **Port control procedures in ascending order of risk**: Views (usually mechanical) → Defaults →
   Handlers → Tasks → Subroutines (structural: procedure/transaction model differs) → Triggers
   (structural: row-level `NEW`/`OLD` vs. batch `inserted`/`deleted`). Generate and read back the
   actual generated code for each before moving on — never trust `committed: true` alone.
5. **Port calculated fields, column/domain default queries, and prefilter queries** (checklist items
   3–5, 6) — same dialect substitutions as control procedures, no `control_proc_template`/
   `template_prog_object_item` machinery involved; write straight into the `_query` child entity's
   `rdbms_type = 4` row.
6. **Resolve domain/column name collisions** (checklist item 7) — do this *before* the first full
   model validation pass if possible; it's a modeling issue independent of any code, cheap to fix, and
   will otherwise mask other validation output.
7. **Port seed/demo data** (checklist item 8) — last, since it's large and low-risk; budget time by
   size, not complexity.
8. **Full model validation** in the Software Factory UI. Expect more than one round — see "Known
   PostgreSQL-specific validation errors" below for the two categories hit live.
9. **Generate everything, deploy to a real PostgreSQL instance, and exercise the highest-risk flows**
   — anything with a structural (not just syntax) rewrite: triggers, cross-item state, cascading
   handlers. A clean generation says nothing about runtime correctness for these.

## Porting control procedures

Follow `thinkwise_sf_control_procedures`'s multi-dialect section
(`control_proc_template` per platform, `template_prog_object_item` per `(rdbms_type, prog_object_id)`,
generate via `task_generate_code_grp` then `task_add_job_to_generate_object_code`, verify by reading
`prog_object_generated_code`) for the mechanics of *how* to wire a new template. This skill adds what's
specific to *porting T-SQL to PostgreSQL* once you're in that flow — see
`references/dialect_conversion_reference.md` for the full substitution table and the structural
rewrites (cross-item shared state, trigger redesign, cursors, identity retrieval, message/abort
semantics) that come up constantly in real handler/trigger/subroutine ports.

When an API or tooling call blocks the migration itself — `branch_rdbms_type` refusing writes, a
generation/validation error with no obvious cause, or a step that only resolves manually in the
Software Factory — read `references/known_issues_and_gaps.md` before working around it; it records
the symptom, root cause, and what actually worked for each.

**Ordering `template_prog_object_item` rows**: a fresh assignment's `order_no` defaults to whatever the
`control_proc_template`'s own `order_no` happens to be — this is *not* reliably a safe position
relative to the framework's own wrapper items (`handler_start`/`handler_insert`/`handler_end`, etc.).
Always query `prog_object_item` for the target object first, confirm where the framework's own items
sit, and explicitly set your item's `order_no` strictly between the ones it needs to run between — a
value that merely "looks" early/late without checking is how a pre-mutation validation ends up running
*after* the mutation it was meant to guard (verified live: this exact mistake happened and was only
caught by reading the generated code, not by the generation status).

## Framework helpers — verify, don't hand-port

`sql_tsf_user`, `sql_tsf_send_message`, `sql_tsf_original_login`, `sql_tsf_optimize_indexes`, and
similar framework-owned control procedures (recognizable by the `sql_tsf_`/`pg_tsf_` naming and by
being genuinely generic plumbing, not application logic) already have a PostgreSQL counterpart shipped
by Thinkwise (`pg_tsf_user`, `pg_tsf_send_message`, ...) that the platform-enable step creates as a
stale placeholder automatically. **Before writing anything by hand for one of these**: run
`task_generate_code_grp` + `task_add_job_to_generate_object_code` for its `prog_object_id` on
`rdbms_type = postgresql` and read the result. Verified live, it just works — `tsf_user` becomes
`coalesce(current_setting('session.tsf_user', true), current_user)`, `tsf_send_message` becomes a
`raise warning`/`raise exception` pair, with zero manual porting. Only fall back to hand-writing one of
these if generation comes back empty or wrong.

**This also means `tsf_send_message`'s abort semantics differ by platform** — see the dialect
reference for what this changes in every handler/trigger/task that calls it.

## Subroutines that were never generated before — known API gap

A standalone subroutine (`PROCEDURES`/`FUNCTIONS`/`TABLE_VALUED_FUNCTIONS` code group) that has *never*
been generated on *any* platform has no `prog_object` row to build on. Verified live, twice: neither
`task_generate_code_grp` bound to the subroutine's own control procedure nor bound to the framework's
group-level control procedure materializes the missing placeholder — unlike every other code type
(views, handlers, tasks, triggers), where the same call reliably creates one. This isn't
platform-specific to PostgreSQL — it's a gap in the object-creation API path for this one code-type
shape, just one a PostgreSQL migration is likely to trip over if the model has any subroutine that was
authored but never deployed. **Write and save the PostgreSQL template anyway** (`control_proc_template`
add/edit both work fine standalone), then tell the user this specific object needs one manual
"Generate" pass in the Software Factory's own UI before the template takes effect — don't keep
retrying alternate API calls once both documented paths have failed.

**Side effect to know about**: `task_generate_code_grp` bound to *any* control procedure was observed
to bulk-materialize stale placeholders across many unrelated code groups and tables at once (a single
call aimed at a trigger control procedure also produced dozens of `ug_*`/`badge_*`/`chg_*` placeholders
for the same table) — broader than "creates placeholders for this code group" as documented elsewhere.
Harmless on its own, but see "MERGE/FK errors" below for a failure mode this can trigger at scale.

## PostgreSQL-specific errors

Three recur and each has a known cause:

- **Domain/column name collisions** — PostgreSQL shares one namespace, so a domain named like a
  column fails validation. **Prefix every domain with `dom_`**, as a blanket rule applied to all of
  them, not case by case.
- **MERGE/FK errors during generation** are a repository-internal issue, not a problem with the
  application's own data — don't go hunting in the model for a cause.
- **Seed/demo data** is mechanical but bulk, and a seed script bypasses Handlers.

For the diagnosis and fix for each, read `references/pg_specific_errors.md`.

## Verification, every time

- Read `prog_object_generated_code` after every generation — `generated_code_stale = false` and a
  "successful" job status prove generation ran, not that the SQL is dialect-correct or semantically
  equivalent to the original.
- For anything with a structural rewrite (see the reference doc), read the *full* generated body and
  confirm the rewritten logic, not just that it compiles — an ordering mistake (see "Ordering
  `template_prog_object_item` rows" above) generates cleanly and only shows up on inspection.
- Re-run full model validation after the domain/column collision fix specifically — it's likely to
  surface follow-on messages (like the unresolved input-constraint one above) that were masked by the
  first error.

## Pre-flight checklist

- [ ] Confirmed dual-platform vs. full-cutover with the user before starting.
- [ ] Queried all nine checklist categories against the live model — didn't assume any is empty.
- [ ] Verified at least one framework helper (`tsf_user`/`tsf_send_message`) auto-generates correctly
      before hand-porting anything.
- [ ] Ported control procedures in risk order (views → defaults → handlers → tasks → subroutines →
      triggers), reading generated code after each, not just checking `generated_code_stale`.
- [ ] Checked every cross-item template assignment (pre/post-mutation pairs) for shared state that
      can't survive PL/pgSQL's declare-before-begin rule — see the reference doc.
- [ ] Checked every `tsf_send_message(..., abort=true)` call site for now-dead `rollback`/`return`
      code after it (PostgreSQL raises immediately; SQL Server doesn't).
- [ ] Cross-referenced every domain against every column for exact-name collisions before the first
      full validation pass, and confirmed a renaming convention with the user before applying it.
- [ ] Ported calculated fields, column/domain default queries, and prefilter queries — not just
      control procedures — checking each of the three `_query`-split entities independently.

