---
name: thinkwise-sf-data-model
description: Reference guidelines for designing and naming domains, tables, and columns in a Thinkwise Software Factory data model — naming conventions, entity classification, column order, data types, references, and menu placement. Use whenever designing or reviewing a data model, or making sf_mcp calls that create or inspect domains, entities, columns, or references, to check names, types, and structure against these conventions before proposing or executing changes.
---

# Thinkwise Data Modeling Guidelines — Domains, Tables, and Columns

Reference conventions for the Thinkwise Software Factory data model, compiled from the official
Thinkwise data modeling guidelines (docs.thinkwisesoftware.com) and Thinkwise Community articles.
Apply these when designing a new data model, reviewing an existing one, or using sf_mcp tools that
touch domains, entities, or columns.

## Bulk-importing a whole data model in one call — check for a custom task first

Some models have a **custom-built** task (not a standard feature — may or may not exist in the model
you're working with) that upserts a whole batch of domains/tables/columns/indexes/references from one
JSON payload, instead of creating each object individually via the flow described in the rest of this
skill. See `references/bulk_import_data_model.md` for how to check whether it exists, confirm its
shape, and fall back to the normal per-object flow if it doesn't.

## General naming rules (apply everywhere)
- **Singular, lowercase names** — never plural, never mixed case.
- **Self-explanatory names** — a reader shouldn't need extra context to understand what it represents.
- **Split into subnames with underscores** (`sales_order_line`, not `salesorderline` or `SalesOrderLine`).
- **Avoid abbreviations** — spell words out fully, except where a platform name-length limit forces it, or for the conventional exceptions `id` and `no`.
- **No meta-information in the name** — don't encode data type, length, or table membership into the name itself.
- **Prefer reusing an existing, already-reviewed naming word component over inventing a new one when
  an equivalent term already exists.** Every new distinct word introduced into a table/column/domain
  name enters its own review step (a Software Factory validation tracks unreviewed naming components)
  — reusing vocabulary already used elsewhere in the model, when the meaning genuinely matches, avoids
  growing that backlog for words that already mean the same thing. This is the naming-level version of
  the label-reuse rule under "Form & grid groups" below.
- **Never name a column or domain after a SQL reserved/keyword-adjacent word** — `level`, `year`,
  `order`, `group`, `date`, `time`, `table`, `view`, `index`, `key`, `value`, `user`, `values`,
  `check`, `default` — even when the target RDBMS happens to tolerate it unquoted. These names get
  woven directly into generated SQL identifiers, and hitting one live (both `level` as a column and
  `year` as a domain, in the same model) surfaced the problem only once hand-written SQL referencing
  them was deployed, not at generation time. If a column/domain already has one of these names, use
  the dedicated rename task (for columns/domains, not a delete-and-recreate) to fix it — but the
  rename task only updates model metadata and structural DDL; it does **not** rewrite any
  hand-authored control-procedure/view/task template text that already referenced the old name by
  string, so grep every template referencing the old identifier and update it by hand afterward, then
  regenerate. **It also leaves the old id's translation object behind as an orphan** — the renamed
  column/domain gets a fresh `transl_object`/`transl_object_transl` under its new id, but the old id's
  rows aren't deleted, just no longer reachable from anything live. Run
  `task_delete_unused_transl_objects` (bound to `branch_appl_lang` — see
  `thinkwise_sf_translations`) afterward as a branch-wide cleanup, rather than
  leaving stale rows to accumulate.

## Language of names
Every name (tables, columns, domains, domain elements) is written in one consistent human language —
this skill's own examples are English, but the actual language is whatever the model already uses.
- **Expanding an existing data model**: match the language already in use. Check existing table/column/domain
  names before adding anything — if the model is in Dutch (`werknemer`, `verkooporder`), new additions must
  be Dutch too, not English, even though this document's examples are in English. Don't mix languages within
  one model.
- **Starting a new data model from scratch** (no existing tables/domains to infer from): **ask the user what
  language to model in** before naming anything, unless they've already stated it (e.g. they wrote the request
  in a specific language, or named entities themselves in it) — in that case just follow their input instead of
  asking a redundant question.

## When a guideline conflicts with an existing model's own established convention

These rules describe the ideal. When expanding an **existing** model whose own convention is
genuinely *pervasive* — one generic surrogate-key domain everywhere, no diagrams, no per-column
sort/search/filter tuning — matching that convention usually beats introducing a new one that only
the newest objects follow, because a model inconsistent with itself carries its own cost.

Say which you're doing and why when it comes up. This is not licence to ignore the rules below: it
applies to pervasive conventions, not to a one-off inconsistency or an outright mistake.

## Tables (entities)
Classify every table into one of four types before modeling its columns; if a table doesn't cleanly fit one, that's a signal to restructure rather than just rename:
1. **Strong entities** — exist independently, single-column primary key with no foreign keys as part of it (e.g. `sales_order`).
2. **Weak entities** — can't exist without a parent (e.g. `sales_order_line`). Name = parent entity name + qualifying addition. **The foreign key to the parent is part of the primary key, and comes first (topmost) in it** — followed by the entity's own discriminating column(s). See "Column order" below for exactly where an identity column fits into that sequence.
3. **Link tables** — resolve many-to-many relationships. **The primary key is the composite of the foreign keys to the two linked tables — no separate identity column is needed**, since the pairing itself is the row's identity. **Name** = `<table1>_<table2>`, and the **primary key column order follows the same order as the name**: for a link table `employee_employee_function`, the primary key is `employee_id` first, then `employee_function_id` second. (If the association needs to repeat over time — e.g. it carries a historized start/end date range, so the same pair of foreign keys can legitimately appear in more than one row — it's no longer a pure link table; it becomes a weak entity of one side with its own identity column added as the last primary key column, per rule 2 and "Column order" below.)
4. **Inheritance tables** — implement a 1:1 "is-a" relationship with a parent; named for the specialization.

A built-in validation (`tsf_guidelines_categorize_entities`) flags tables that don't qualify as any of the four.

### Table description

**`tab_description` should say more than the table's own name restated in words.** A description
that just spells out the title (`sales_order` → "Sales order") tells a reader nothing they couldn't
already see from the name itself. Write what the table is actually *for* — the role it plays in the
model, what business process or concept it captures, and anything a reader wouldn't guess from the
name alone (e.g. `sales_order` → "A customer's confirmed order for one or more products, used to
drive fulfillment and invoicing"). This applies whenever a table is created or reviewed, the same as
naming and classification above.

### Icon

Set `tab.icon_id` to a suitable icon from the repository as part of creating the table — it's the
table's own icon wherever it's shown (menu item, document, tree/detail navigation), not a cosmetic
extra to skip. Follow `thinkwise_sf_icons` for how to search/reuse the repository and
what to do if nothing fits (ask the user, don't guess or leave it blank). A view used as a business work
queue should get the work concept (e.g. "orders to release" → order/check), not a generic table/view
icon — see that skill's subject-icon guidance.

### Exposing new tables on a menu

Creating a table is only half of making it usable. A **strong entity** (rule 1) — or the parent side of
an **inheritance** relationship (rule 4) — is a candidate **top-level subject**: something a user should
be able to open directly from the menu, not just reach by drilling into a parent's detail grid. **Weak
entities (rule 2) and link tables (rule 3) are usually not** top-level subjects — they exist to be detail
rows or associations under something else, and defaulting them onto the menu clutters it with entries
nobody opens directly. Treat that as a strong default, not an absolute: occasionally a weak entity is
genuinely browsed standalone, and that's a judgment call, not a rule violation.

**Don't decide silently which candidates become menu items.** After creating or reviewing a batch of new
tables, present every candidate top-level subject as a **multi-select checkbox-style question** (one
option per table, so the user can tick which get added and leave the rest unticked — e.g. because
they're only ever reached through a parent's screen, or aren't ready for end users yet) rather than
adding all of them, or guessing which "obviously" belong.

For the ones the user picks, follow the `thinkwise_sf_menus` skill for the actual
menu/group/item work — including its own golden rule to confirm menu type and group placement, and to
create a new menu (rather than assuming an existing one fits) if the model doesn't have one yet for the
relevant platform.

## Columns
- Same general rules: lowercase, singular, self-explanatory, underscore-separated.
- **Don't prefix non-key columns with the table name** — redundant since the table context is already known.
- **Primary key**: name = `<table_name>_id`.
- **Foreign key**: must have the exact same name as the parent table's primary key column — this is also what lets OData/Indicium auto-derive relationship names.
- Prefer `INT` identity for surrogate primary keys; use `BIGINT` only for tables expected to exceed ~2 billion rows. Only non-FK primary key columns should be identity columns.
- **One fact per column, atomic values only** — don't pack multiple values into a delimited string.
- **Prefer NOT NULL with a sensible default** over nullable columns, unless the absence of a value is itself a meaningful business state.
- **A column's default value must match its data type and, if backed by a domain with elements, be a
  valid element (or within the domain's min/max range for a ranged domain).** This is checked by a
  Software Factory validation, not enforced at write time — `stage_resource`/`patch_resource` will
  commit a default value that's the wrong type or out of range without complaint, and it only surfaces
  later as a validation error. Double-check a newly-set default against its column's actual domain/type
  before considering the column done, including for a data-migration script's own column defaults.
- **Before finalizing a new column's name, check its translated label doesn't collide with another
  column's label already in use on the same table** — two columns with different ids but identical
  rendered captions is flagged by a Software Factory validation and confuses a user reading the
  form/grid.
- **A column can be calculated/expression-backed (`calculated_field_type` non-zero) instead of physically stored** — it reads back identically to a real column on a normal query, with no visible difference. See "Calculated columns" below for the different kinds and when (rarely) to reach for one; this matters most when writing hand-written SQL against the table directly (control procedures, migrations) — see `thinkwise_sf_control_procedures`'s "Calculated columns are not physical" note before including such a column in an insert/update/merge statement.

## Data sensitivity classification

Every column carries a data-sensitivity/privacy classification, and a Software Factory validation
flags any column left at its undecided default — more strongly for columns the platform can already
infer are *likely* sensitive from their name/domain. Decide it deliberately when creating a column,
the same as its domain/type: for an obviously personal or confidential field (name, email address,
national id, financial account, health data) set the classification explicitly rather than leaving it
unset; for a column where sensitivity genuinely isn't obvious, ask the user rather than guessing — this
has real compliance consequences, not just a lint warning. Confirm the exact field/enum name live via
the column entity's own metadata before writing to it.

## Calculated columns

Only reach for a calculated column when the value genuinely cannot be a normal stored one. Two kinds
exist: **`calculated_column`** (same-row logic, free to read, indexable when `PERSISTED`) and
**`expression`** (a correlated subquery re-run per row, never indexed — expensive, and the cost is
invisible on read).

Default to `calculated_column` for same-row logic; reserve `expression` for a value that must reach
another table. Where a Default control procedure could set the value once at write time, prefer that
over either.

For the full decision table, how to write an `expression` query, the `t1` row alias, the 2026.2
`_query`-split pattern, and the performance rules, read `references/calculated_columns.md`.

## Decide presentation settings before creating any columns — one rule, applied everywhere

Column order, grid visibility, form/grid group and section flags, sort, search, filter, grouping and
aggregation are all **per-column settings that belong in the same write that creates the column.**
Decide the whole plan for a table up front, in one pass, rather than creating bare columns and
retrofitting presentation afterwards — retrofitting means re-reading and re-patching every row, and
it is where these settings get silently left at their defaults.

The same applies when a table changes later: a column added to an existing table joins the existing
plan (its group, its order, its sort/filter behaviour) in the write that creates it.

## Column order
- **Primary key columns come first**, in the order they appear in the key. For weak entities and link tables, that means the foreign key(s) to the parent(s)/linked table(s) come before the entity's own discriminating column(s) — mirroring the strong → weak ordering rule for composite primary keys.
- **If the primary key includes an identity column, that identity column always comes last within the primary key** — every foreign-key-shaped key column precedes it. A pure link table (rule 3 above) has no identity column at all; a weak entity that needs one (e.g. a historized association, or a classic detail like `sales_order_line`) puts the parent foreign key(s) first and the identity column last.
- After the primary key, place **other foreign keys / reference columns** next, followed by the table's **regular data columns**.
- If a table has **trace/audit columns** (created/modified by + date), put them last, since they're metadata about the row rather than business data — keeps the meaningful columns together and predictable to scan. This is ordering guidance only, not a prompt to add them — see "Integrity, structure, and consistency" below on when (not) to add them.
- **Order-number increments**: use the column's order-number (sequence) property to control this layout, and leave gaps rather than numbering consecutively — **increase by 10 for each column, starting at 10 for the first column** (10, 20, 30, …). This leaves room to insert a column later at, e.g., 15, without having to renumber every column after it.

**API quirk**: when scripting table creation through a metadata-driven modeling API rather than the UI, a column added before the table's real primary key has been committed can silently default `primary_key = true` (which then also forces `mand`/mandatory to read-only-`true`), regardless of what was requested for that column. This happens with no error — the write reports success. After the intended primary key column is committed, re-read the rest of the table's columns and explicitly correct `primary_key`/`mand` on any that picked up the wrong default rather than assuming the original request held.

## Grid visibility, groups, sort, search, and filter

These are the per-column presentation settings, all set in the same write that creates the column
(see the rule above). The decisions that matter:

- **Grid visibility** — set `grid_type_of_col` (`editable`/`read_only`/`hidden`) deliberately; the
  default behaves as `editable`, so every column shows unless you say otherwise. A grid should show
  only what a user needs at a glance. Hide surrogate keys, audit timestamps, and fields relevant to
  only a subset of rows — those belong on the form. Make look-up and status columns `read_only` when
  their value should change through a task, not an inline edit.
  **Don't forget `col.type_of_col`** — a third, base-level field separate from
  `grid_type_of_col`/`form_type_of_col`, surfacing in the Software Factory as plain "Column type"
  next to domain/primary-key/mandatory rather than near the presentation settings. Set it alongside
  the other two whenever a visibility decision should hold everywhere.
  **Carve-out:** on a weak entity's own detail tab, the inherited-PK foreign-key columns default to
  **hidden**, not read-only — the parent row already implies them.
- **Groups** — two independent pairs on `col`: `form_field_in_next_grp`/`form_next_grp_label` and
  `grid_field_in_next_grp`/`grid_next_grp_label`. Set the flag **on the column that starts the new
  group**. `field_on_next_tab`/`next_tab_label` is a different, stronger break (a whole new tab), and
  grids have no tab concept. This is banding *columns* under a header — not the same thing as
  grouping grid *rows*, which is below.
- **Sort** — every table should have a deliberate default sort (`default_sort`, `sort_no`,
  `sort_order`, `allow_sort`): a natural order column, a name/code, or a date, often descending.
- **Search and filter** — `visible_for_search`/`search_order_no`/`search_condition`/
  `include_in_global_filter` and `visible_for_filter`/`filter_order_no`/`filter_condition`.
  `visible_for_search` and `visible_for_filter` share the same three-way enum:
  `always` / `extended` / `never`.

**Before choosing any of this, name the subject's job** — find-and-open, work queue, compare records,
maintain a record, review exceptions, analyze totals, or select-in-a-lookup each want a different
column set, sort and filter. See `references/subject_presentation_design.md`.

For the full guidance on each (which columns to hide vs. read-only and why, group-vs-section choice,
keeping a group plan current as a table changes, and how to choose search/filter conditions per
column type), read `references/column_presentation.md`.

## Grid row grouping and aggregation

Runtime row grouping (`allow_grp`, `grp_box_visibility`, `grp_until`, `default_sort`) and column
aggregation (`aggregation_summary_type`) are opt-in and mostly belong on *overview* grids. A detail
grid under a parent record typically leaves `allow_grp = false` entirely — it is already scoped.

Aggregate only same-unit measures; never sum a rate, a ratio, or an id.

For when grouping earns its place, the aggregation types, and how `grp_until` builds grouping levels,
read `references/grid_grouping.md`.

## References (foreign keys)

Whenever a column's value is meant to match another table's primary key, model an actual `ref` row
(plus one `ref_col` per join column) **at the same time you add the column** — without it there is no
look-up combo, no detail grid, no derived navigation property, and no integrity check.

**Direction — one rule, no exceptions:** `source_tab_id` = the table whose primary key is referenced
(the parent/PK-owner); `target_tab_id` = the table **or view** holding the FK-shaped column. This is
identical for a view child; there is no separate "view case" that reverses anything. `ref_col.source_col_id`
must be part of `source_tab_id`'s primary key. Look-up renders on the target, detail on the source.

A wrong direction is accepted at write time with no error, surfacing later as the validation
*"foreign key reference with integrity does not contain the full primary key of the source table"* —
which always means the two are swapped.

**Self-referencing FKs can't cascade on SQL Server**: set `on_delete`/`on_update` to `no_action` and
implement any reparenting in a control procedure.

For the look-up-vs-detail presentation choice, disambiguating multiple references between the same
pair (`ref_add`), and choosing a table's `look_up_display_col_id`, read
`references/references_and_lookup.md`.

## Diagrams (one per functional/subject area)

Diagrams group a model's tables into readable subject areas. **Creating or editing a diagram is not
possible through this kind of API** — no writable entity, and the `diagram` bound tasks are not
usable either. Never attempt it; when a new table should appear on a diagram, say so as a manual
Software Factory step.

For which diagram a new table or reference belongs on, when to split one that has outgrown itself,
and the bound-task inventory, read `references/diagrams.md`.

## Domains, data types, elements, and status columns

A **domain** is the reusable type definition behind a column (its data type, length, control, and any
fixed element list). Prefer a per-entity domain over one generic surrogate-key domain, and reuse an
existing domain before inventing one.

Two traps worth carrying here: **on a PostgreSQL branch prefix every domain you create with `dom_`**
(a blanket prefix, not a case-by-case check — domain and column names collide), and **setting
`dom.control_id` silently flips a numeric domain's `alignment` to right**, so re-check and reset it.

For the full guidance (naming, data-type recommendations per kind of value, `elemnt` domain elements
vs. a look-up table, and the read-only-by-default convention for status columns), read
`references/domains_and_elements.md`.

## Conditional layout — consider it, don't default to it

When a new or changed table has a status, state, severity or threshold column, take one deliberate
pass asking whether a conditional layout would genuinely help a user scanning the grid. Good
candidates: a status a user acts on differently per value, a date that can run overdue, a quantity
that can breach a threshold. **Only add one where there's a real candidate — not just because a table
has a status column, and never without confirming with the user first.**

This section only decides *whether* one is warranted. For the mechanics — field reference, the
condition enum, themes, accessibility — and the full "Should this object get one?" test, see
`thinkwise_sf_conditional_layouts`.

## Translating new objects

Every table (`tab`), column (`col`), and domain element (`dom_elemnt`) created following this
skill gets a translation object auto-generated with placeholder text — literally the object's own
ID wrapped in brackets (`[sales_order_line]`, `[customer_code]`) — which is what actually renders
in the running application until it's translated. Creating the object is not the last step for
anything user-facing: after modeling a new table/column/domain element (or a batch of them), follow
the `thinkwise_sf_translations` skill to find and fill in these
placeholder-marked objects, the same way "Exposing new tables on a menu" above is a required
follow-up, not an optional polish pass.

**Don't rely on remembering to do this as you go — verify it with a query as the last step of the
task, every time.** A real session translated the new tables it created and still left every one of
their columns sitting at bracket-placeholder text, because "translate the new objects" was followed
as a narrative reminder during the build rather than checked mechanically at the end. Before
declaring any modeling task complete, run this — scanning the **whole branch**, not just the objects
touched this session, since a narrower scan misses pre-existing gaps the task happened to touch in
passing:

```
/transl_object_transl?$filter=model_id eq '<model>' and branch_id eq '<branch>' and startswith(transl,'[')&$select=type_of_object,transl_object_id,transl
```

Zero rows is the actual definition of "done," not "I translated the things I remember creating."
Every skill that creates translatable objects (`thinkwise_sf_views`,
`thinkwise_sf_tasks`, `thinkwise_sf_menus`, and any plan produced by
`thinkwise_sf_build_planner`) points back to this query as its own final gate rather
than repeating it — treat this section as the canonical source for it.

## Integrity, structure, and consistency
- **Enforce referential integrity at the database level.** Enable "check integrity" on every foreign key reference unless there's a specific reason not to (e.g. deliberately historical/soft references, or a reference into a view — see "References (foreign keys)" above, where `check_ref = false` is the norm since a view carries no physical FK constraint) — relying on application logic alone invites orphaned records the moment something bypasses the normal flow.
- **Don't add trace/audit columns (created/modified by + date) to a table on your own initiative.** Thinkwise ships a standard "trace fields" Thinkstore solution for exactly this purpose, and hand-modeling equivalent columns duplicates/bypasses it. Only add them if the user specifically asks for created/modified-by-and-date tracking on a table — and even then, don't just model the columns: ask the user to confirm whether they actually want manually-added columns, or would rather use the trace fields Thinkstore solution instead. Only proceed with manual columns once they've confirmed that's what they want.
- **Be deliberate about triggers.** Treat them as a last resort for enforcing data rules — look at control procedures, defaults, integrity checks, or expression columns first, since triggers hide logic outside the model and complicate generated code and debugging.

## When to use a unique index
Thinkwise's Software Factory has no separate "unique constraint" — uniqueness outside the primary key is always a **unique index** (Datamodel → Tables → Indexes → check "Unique"). **The primary key itself does not need one of these index rows at all** — it's established purely by each key column's own `primary_key` flag; verified live across a whole real model, zero rows anywhere used `indx.primary_key = true`. Don't model an `indx`/`indx_col` row just to represent a table's primary key — reserve `indx` for genuinely additional secondary/unique/non-clustered indexes.
- **Use one whenever a column (or combination) is a natural/business key that isn't the primary key** — e.g. email address, customer code, an order number within a scope — so the database rejects duplicates rather than relying on application-level checks alone.
- **Don't duplicate the primary key.** A unique index matching the PK's columns exactly is redundant, flagged by a Software Factory validation (2023.1+), and can create FK-dependency issues that make it hard to drop or regenerate.
- **Prefer a unique index over a code-level "no duplicates" check** for: consistent translated error messages from the platform (vs. raw SQL Server constraint text), and the ability to filter out NULLs so optional-but-must-be-unique-when-present columns behave correctly.
- **Regenerate and execute after adding one** — a unique index has no effect until the source is generated and executed against the database (a common cause of "it still lets me create duplicates").

## When to add a (non-unique) index
Indexes are the biggest single performance lever, and every one of them slows each insert, update, and delete and uses storage. This section is the canonical index guidance; other skills point here.
- **Check what already exists first.** The Software Factory already indexes the primary key (clustered on SQL Server), foreign keys, and default-sort columns.
- **Do index** join columns, and selective columns users filter, sort, or group on (title, status, order number, SKU). `references/subject_presentation_design.md`'s "Index alignment" covers common filter-plus-sort paths.
- **Prefer one composite index over overlapping single-column ones** when queries filter on several columns together. Put the most selective, most frequently filtered column first. Tick **include** on extra columns to make it a **covering** index, so a lookup never goes back to the base table.
- **Don't** add an index speculatively; index a low-cardinality column (a few distinct values); pile indexes onto a complex query (more indexes mean longer plan compilation); or use a random GUID as a clustered primary key (random insert order fragments the table).
- **Verify against real usage.** On SQL Server, `sys.dm_db_missing_index_details` lists indexes the optimizer wanted, and `sys.dm_db_index_usage_stats` shows which existing ones are actually used. Treat any index Claude proposes as a hypothesis to check against the execution plan.
- **Maintenance:** schedule `tsf_optimize()` regularly on the SF, IAM, and application databases. It rebuilds indexes so fragmentation doesn't slowly degrade performance.

## Quirks when scripting these changes through a metadata-driven modeling API

Scripting domains/tables/columns/references (and more) through a metadata/staging-style write API,
rather than the Software Factory UI directly, surfaces a set of verified-live quirks — enum keys
rejected in favor of raw numeric values, individual fields silently dropped from combined writes,
child rows with their own hidden NOT-NULL order-number fields, introspection payload size limits,
parent-resolution failures on weak entities, translatable-field writes rejected pre-commit,
unscoped queries matching the wrong model/branch, screen-type creation being UI-only, and blanket
write rejections that are actually a role/rights gap. See `references/api_write_quirks.md` for the
full list before scripting bulk changes through this kind of API.
