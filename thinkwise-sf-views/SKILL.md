---
name: thinkwise-sf-views
description: Reference guide for creating views in a Thinkwise Software Factory data model — naming, entity/column setup, domain reuse, modeling references to the view's source tables, and writing/assigning the SELECT code that backs a view. Use whenever creating, reviewing, or troubleshooting a view via an MCP connector with Software Factory access (e.g. sf_mcp, indicium), especially when converting a user's ad hoc SQL query into a view. Does not cover deployment.
---

# Creating Views in the Thinkwise Software Factory

Reference for the view lifecycle covered by this skill: `tab` (type `view`) → columns → references
→ control procedure → template → `template_prog_object_item` → generated `CREATE VIEW` program
object, generated and verified. Deployment (pushing the generated code to an actual database) is a
separate concern this skill does not cover.
Apply this whenever an MCP connector with Software Factory access (`sf_mcp`, `indicium`) is used to
create, inspect, or convert a query into a view `tab`/`col` typically live in a `data_modeling`-style domain;
`control_proc`/`control_proc_template`/`template_prog_object_item` typically live in a
`manage_model`-style domain For
the general control-procedure/template/assignment mechanics referenced throughout (code groups,
`[PARMTR]` substitution, static vs. SQL assignment, dialect differences), see the
`thinkwise_sf_control_procedures` skill — this skill only covers what's specific
to views.

## What a view is

A view is a `tab` entity with `type_of_table = view` (enum: `table` 0, `view` 1, `function` 2,
`mqt` 4). Like a table it has columns, a primary key, references, screens, tasks, security —
everything a table has — except the data is never stored; it's composed at query time from a
`SELECT` statement, so it's always current and never needs syncing.

`tab.create_view_method` picks how that `SELECT` gets defined (enum: `meta_auto` 0, `meta_custom` 1,
`template` 2):

| Method | What you write | When to use |
|---|---|---|
| **Meta Auto** (`meta_auto`) | Nothing — map each view column to a source column (`col.view_tab_id`/`col.view_col_id`), run the `task_generate_view_from_clause` bound task, the `FROM`/join logic (`tab.view_from_clause`) is derived automatically | Only a straight pull from one or a few tables joined on their modeled references, no filtering, no aggregation |
| **Meta Custom** (`meta_custom`) | Hand-edit `tab.view_from_clause`/`view_where_clause`/`view_grp_by_clause`/`view_having_clause`; the `SELECT` clause is still derived from the view's columns | Rare middle ground — custom joins/filters but still want the platform to build the select list |
| **Template** (`template`) | The entire `SELECT` statement, written as a control procedure template | Anything with real business logic: multi-table joins, aggregation, calculated fields, `UNION`, conditional logic |

**Default to Template.** In a large, mature production model inspected directly (210 views), every
single one used `create_view_method = template` — zero used Meta Auto or Meta Custom. A view earning
its keep almost always needs a join condition, a filter, or a derived column the auto-generated
`FROM` clause can't express, so teams converge on Template as the standard rather than starting with
Meta Auto and migrating later.

A fourth `type_of_table` value, `mqt` (materialized query table / snapshot), persists and
periodically refreshes the result instead of computing it live. Reach for it only once a view's
underlying query becomes a measurable, repeated performance cost — don't start there pre-emptively.

## Naming

Base rules match tables generally: singular, self-explanatory, underscore-separated, no
abbreviations, no meta-information baked into the name. View-specific points:

- **Name the view for the business question it answers, not its mechanics** — `customer_list`,
  `additional_cost`, not `join_customer_and_customer_detail`.
- **Reserve a prefix for platform-generated/dynamic-model view categories, used consistently.** The
  Thinkwise report-label pattern is the canonical example: any view feeding translated report labels
  is named with the `rpt_lbl_` prefix so the dynamic-model concept can find it. If a model has its
  own generated-view categories (audit/history, staging, …), give each one fixed prefix and document
  it — don't let it drift per developer.
- **Current official guidance is lowercase `snake_case`** (`customer_list`, not `Customer_List`).
  At least one large production model instead uses `PascalCase_With_Underscores` throughout (a
  legacy convention predating current guidelines). Follow whatever the model already uses; for a new
  model, follow the lowercase guideline. Consistency within one model matters more than which style
  is picked.
- **Name the control procedure and template after the view** so the code producing a view's data is
  trivially discoverable from the view's name. A bare match (`control_proc_id == tab_id`) is
  simplest and needs no explaining — pick one convention (bare match, or a fixed prefix like `Vw_`)
  and hold to it across the model; don't mix both.

## Confirm scope before modeling

Before creating the `tab` row, state the plan back to the user and get their confirmation — this
applies to every view being designed, not only an ad hoc-query conversion (see below). This is the
`thinkwise_sf_base` "Confirm-before-mutate" convention applied at this skill's own
grain; it isn't superseded by anything below about the view's own setup mechanics:

- **Source tables/columns** the view pulls from.
- **Intended grain** — what one row of the view is meant to represent.
- **Primary-key candidate** — the column(s) that define that grain.
- **`create_view_method`** — Template vs. Meta Auto vs. Meta Custom (default to Template — see
  above).

**Flag, don't silently decide, if the request is a poor fit for a plain view** — heavy aggregation
over a large table, queried by dozens of other things, on source data that barely changes. A
snapshot (`type_of_table = mqt`) or a scheduled denormalized table is often the better trade; raise
it with the user rather than defaulting to a view.

## Setting up a view — the basics

1. **Data model → Tables → New table.** Set `type_of_table = view`, pick `create_view_method`
   (default `template`).
2. **Model the columns before writing any code.** For Template views, the control procedure's
   `SELECT` list must match the view's modeled column list, in the same order — model columns first,
   then write `SELECT` to match, not the other way around.
   - **Column order**: same 10-per-step convention as regular tables (`col.order_no` 10, 20, 30, …),
     leaving gaps for later insertions.
   - **Primary key**: pick the column(s) that define the view's actual **grain** (the level of
     detail one row represents) — usually the query's `GROUP BY`/`DISTINCT` columns, or the source
     table's PK for a row-for-row pull. If the grain isn't obvious from the request, ask the user what
     one row of the view is meant to represent before picking the columns/primary key. Getting the
     grain wrong (a PK that isn't actually unique per row) is the most common view bug — nothing
     enforces uniqueness on a view by default, so verify manually against real data
     (`GROUP BY <candidate PK> HAVING COUNT(*) > 1`) before shipping.
     **Derive the PK from base-table key(s)**, or a combination of keys across the joined tables.
     Never calculate it with `row_number()` or use `newid()`/a random GUID. Indicium resolves a single
     row either **by key** (one row requested, essentially always fast) or through **`$filter`**
     (runs the whole view definition, then filters). A calculated key forces even a one-row lookup
     down the slow path, and `row_number()` also blocks pushdown by numbering every row first.
   - **Reuse existing domains** for every column representing the same concept as an existing column
     elsewhere in the model — see next section.
   - **Editability and mandatory**: default every column to **not editable** and `mand = false`
     — set `type_of_col`/`grid_type_of_col`/`form_type_of_col` to `read_only` (or `hidden` for
     keys and query/reference plumbing). Make a column `editable` (and `mand` where the handler
     needs it) only where a user or the view's update handler actually writes it. See "Column
     editability and mandatory" below — this is the opposite of the table default.
3. **References are part of modeling the view, not an optional follow-up.** For every column on the
   view that is FK-shaped (its value is meant to match another table's primary key — e.g. an
   `employee_id` column, or an `absence_id`-style pointer), add the `ref`/`ref_col` at this point,
   before writing the query. They are never implied by the view's `FROM` clause; Meta Auto/Meta
   Custom infer references from mapped source columns, but Template gives none for free — skip this
   step on a Template view and the column silently has no look-up, no detail grid, and no
   auto-derived OData/Indicium navigation, even though the generated `SELECT` still returns the right
   data.
   - See the `thinkwise_sf_data_model` skill's "References (foreign keys)" section for the
     full look-up-vs-detail explanation. The one point specific to views, repeated here because it's
     easy to get backwards: **the direction is the same as any table-to-table FK.** For a view
     column pointing at a real table's primary key, `source_tab_id` = the real table (the PK-owner),
     `target_tab_id` = the view (the FK-holder) — not the other way around. Getting this backwards makes the reference render as a
     detail grid on the view instead of the look-up you almost always want there.

     Example — view `employee_absence_overview`, column `employee_id` pointing at `employee`:
     ```
     ref:      source_tab_id = employee,   target_tab_id = employee_absence_overview,
               check_ref = false,   show_detail = false
     ref_col:  source_col_id = employee_id,   target_col_id = employee_id
     ```
     `check_ref = false` because a view carries no physical FK constraint; `show_detail = false`
     because a detail grid on the real table listing view rows is rarely useful. If two or more view
     columns point at the same target table, set `ref_add` on each (e.g. `"most_recent"` /
     `"upcoming"`) so their auto-derived `ref_id`s don't collide.
4. Write and assign the actual query (below).
5. Regenerate and verify the generated code (below).

**The new view and its columns need translating, same as any table.** `tab`/`col` created here get
the platform's usual bracket-placeholder translation until filled in — see
`thinkwise_sf_translations` for the detection query and field reference. Do
this after the column list is finalized (step 2) so it isn't repeated every time a column gets
renamed while the view is still being modeled.

## Reusing columns and domains

A view column is not "read-only, so it doesn't matter" — every domain decision made for the source
tables should carry through:

- **Match the domain (`col.dom_id`) of the source column exactly**, not just the data type. If
  `customer.customer_code` uses domain `Customer_Code`, the corresponding view column surfacing the
  customer code should use the same `Customer_Code` domain — not a fresh domain with the same
  `NVARCHAR(20)` shape. This keeps default UI controls, translations, input constraints, and
  domain-level validation consistent everywhere the value appears. Verified in a real production
  view: `Customer_Code`, `Customer_Group`, `Currency`, `Variety_No` and other columns all reuse the
  exact same domain IDs as their source tables; generic domains like a date domain or a datetime
  domain get reused wherever a date/datetime is surfaced, rather than each view minting its own.
- **Only introduce a new domain for a genuinely new business concept** — a computed/derived value
  with no 1:1 existing column (a calculated total, a concatenated display string, a derived flag).
  Don't create a "view-only" duplicate of an existing domain out of convenience.
- **Aggregations/calculations should still reuse the base domain where the semantics match** (a
  summed amount column can use the same currency/amount domain as the column being summed) — only
  diverge if the aggregation changes the meaning (a `COUNT` result is a plain integer, not whatever
  domain the counted column used).
- **FK-shaped columns inside a view keep the same column name as the table they reference**, exactly
  like normal FK columns — this is what lets Indicium/OData auto-derive the relationship and keeps
  look-ups working without extra configuration.

## Column editability and mandatory — invert the table default

On a table, most columns start editable and you selectively lock a few down. **On a view,
invert that:** default every column to **not editable**, and open up only the columns that
are genuinely meant to change. A view stores nothing — an inline edit on a view column is
inert unless something catches it, so a column left editable "because the source table's
column was" just renders a broken-looking input.

- **Set a view column to `editable` only when one of these holds:**
  - a user edits it directly *and* the view has an update handler / `instead of`-style
    handler (or process logic) that persists the edit to the real table(s) — see
    `thinkwise_sf_control_procedures`'s Handler guidance and
    `references/subject_presentation_design.md`'s "Tables vs. views";
  - the view's own handler writes the column while reacting to another edit on the row (a
    derived value it recalculates and pushes back).

  Everything else — identifying columns, denormalized look-up labels, derived status,
  aggregates, FK-shaped and sort/disambiguation plumbing — stays **not editable**.

- **Not-editable splits into `hidden` vs `read_only`, same enum as a table:**
  - **`hidden`** — surrogate/identity keys carried through only to fix the grain, and
    columns that exist purely to make the query or a reference work (FK-shaped columns
    backing a look-up, sort helpers, disambiguation columns) that a user never needs to read.
  - **`read_only`** — everything a user reads but never types into: business identifiers,
    look-up labels, statuses, amounts, counts, dates. Shown, not editable.

- **Apply the decision on all three fields** — `col.type_of_col`, `grid_type_of_col`, and
  `form_type_of_col`. A view's read-only intent holds on every surface, so unlike the table
  default (where the form stays editable regardless of the grid) these move together. Set
  them in the same `stage_resource` call that creates the column, alongside order / PK /
  domain — don't leave them at the `editable` default and patch later.

- **Mandatory (`mand`) is only meaningful on an editable view column.** `mand = true` on a
  `read_only` or `hidden` view column does nothing a user can act on and only produces
  spurious "required field" validation on a row they cannot complete. Default view columns
  to `mand = false`; set `mand = true` only where the column is `editable` **and** the
  handler genuinely needs a value. After assigning a domain whose own default is mandatory,
  re-read the column and force `mand = false` if it reverted — see the domain-default revert
  quirk in `thinkwise_sf_data_model`'s "Domains" section.

## Writing and assigning the view's SELECT

A view's body is a control-procedure template in the `VIEWS` code group, assigned to the view's
`prog_object` and then generated — the same two-task generation sequence as any other control
procedure (`thinkwise_sf_control_procedures`).

The column list the SELECT returns must match the view's modeled columns exactly, in order.

For the step-by-step (creating the control procedure and template, assigning it, generating, and
verifying the generated SQL), read `references/view_code_assignment.md`.

## Recursive/hierarchical (explosion) views

For a self-referencing hierarchy (a bill-of-materials explosion, an org chart, a category tree), the
Template `SELECT` is almost always a recursive CTE — this brings SQL-Server-specific gotchas around
query hints and type matching between the anchor and recursive members. See
`references/recursive_views.md` for the full detail before writing one.

## Converting a user's ad hoc query into a view

Use when a user hands over a working SQL query (from SSMS, a report tool, a BI dashboard) and asks
for it to become a proper view. See `references/adhoc_query_conversion.md` for the full workflow —
it follows "Confirm scope before modeling", "Setting up a view — the basics", and "Writing and
assigning code to a view" above step-for-step, with a handful of conversion-specific differences
(deriving grain/PK from the query, confirming source names against the live model, diffing the
result against the original query).

## Performance

- **Keep the body pushdown-safe.** Grid filters, prefilters, key lookups, and cube drill-downs all
  filter *outside* the view. `distinct`, `union`, window functions, filters on aggregates, and
  outer-join-side filters can force the whole view to be built first. See
  `thinkwise_sf_control_procedures`' `references/sql_style_guide.md`, "Write pushdown-safe queries".
- **Index the base-table columns users filter or sort on through the view** (see
  `thinkwise_sf_data_model`'s "When to add a (non-unique) index").
- **Remove heavy views from reference filtering** when it isn't essential. Filtering a heavy view
  costs far more than filtering its underlying table.
- **Don't use a query-driven lookup as a grid presentation field** on a large view.
- **Precompute only as a last resort.** Use an `mqt` snapshot (see above) or a scheduled
  precomputed table only after a view measurably can't perform. It gives up real-time data.

## Pre-flight checklist

- PK derived from base-table keys (not `row_number()`/`newid()`), and the body is pushdown-safe (see
  "Performance").
- Model columns (order, PK, domains) before writing the `SELECT` — the template must match the
  column list, not the reverse.
- Default to `create_view_method = template` unless the pull is genuinely a trivial single/few-table
  join with no filter or aggregation.
- Reuse the source column's exact `dom_id` for every view column that isn't a genuinely new derived
  concept.
- Default every view column to not editable (`type_of_col`/`grid_type_of_col`/`form_type_of_col`
  = `read_only`, `hidden` for keys/plumbing) and `mand = false`; make a column `editable` (and
  `mand` where required) only where a user or the view's update handler genuinely writes it —
  the opposite of the table default.
- Verify the chosen primary key is actually unique per row against real data — a view enforces
  nothing on its own.
- Model a `ref`/`ref_col` for every FK-shaped column before writing the template — never leave it as
  "just a column with matching values." Remember the direction reversal for views: `source_tab_id` =
  the real table, `target_tab_id` = the view (opposite of a normal table-to-table FK). Getting this
  backwards renders as a detail grid on the view instead of the look-up you want.
- New view not showing up to attach code to? Run **Generate code group** (`task_generate_code_grp`,
  bound to `control_proc`) for `VIEWS` first — but that only creates the placeholder `prog_object`,
  it doesn't produce code by itself.
- Leave a new template's code empty and generate the code group first — don't hand-guess the
  scaffold. If the write API rejects a true-empty `template_code` as mandatory, use a short
  placeholder comment instead of blank.

