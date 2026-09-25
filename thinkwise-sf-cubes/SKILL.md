---
name: thinkwise-sf-cubes
description: Reference guide for creating and maintaining cubes (analytical pivot/chart views) in a Thinkwise Software Factory model — the cube_* entity family, dimensions vs. values, aggregation types, intervals and hierarchies, calculated fields, pivot and chart settings, editable values, and per-role/per-variant cube rights. Use before working with any cube entity, and before deciding whether a request needs a cube at all versus a Grid, report, or dedicated BI tool.
---

# Creating and Maintaining Cubes in the Thinkwise Software Factory

A **cube** is an analytical dataset built on top of one existing subject (table or view), for
interactive pivoting, slicing, and charting — not a copy of the subject's data, and not a
replacement for the subject's own Grid/Form. It classifies the subject's fields into two kinds:

- **Dimensions** — categorical fields used to segment and group: time, customer, product, region,
  status, work center.
- **Values** — measurable facts aggregated within that grouping: revenue, quantity, hours, a record
  count. (The schema's own enum literal for this is `measure`; every UI, doc, and this skill call it
  a **Value** — see "Naming traps" below.)

A **cube view** is one saved, named arrangement of those fields — which dimensions sit in which
axis, which values are shown, filters, sorting, totals, and pivot/chart presentation. One cube
commonly carries several views, each answering one specific question.

```text
Subject at a defined grain (one row = one clearly stated business fact)
  ├─ Dimensions: who / what / where / when / category
  └─ Values: amount / quantity / duration / count
        ↓
Cube view
  ├─ Filters            (restrict without becoming an axis)
  ├─ Categories/Rows     (primary drill path)
  ├─ Series/Columns      (secondary axis, low cardinality)
  └─ Values              (the aggregated numbers shown)
        ↓
Pivot table and/or chart
```

Apply this whenever an MCP connector with Software Factory access creates, inspects, or modifies a
cube, cube field, or cube view. Domain: `sf/manage_cubes`.

**Companion skills, not duplicated here**: general screen-type/component mechanics (`screen_type`,
`tab`, `main_screen_type_id`, how components attach to a screen) are covered in
`thinkwise_sf_build_planner`'s interaction-surface step and the screen-type API-quirk
note in `thinkwise_sf_data_model` — a new screen type can't be created through the MCP
tools, so a cube's screen types (`cube`, `cube_horizontal`, `cube_no_fields` are the default
cube-capable ones) and components (Pivot table, Chart, Cube panel, Cube view bar) must be assigned to
a table by picking from what already exists. Table-variant inheritance mechanics in general (field-level vs.
snapshot, `tab_variant_change`, `tab_variant_used`) live in `thinkwise_sf_variants` —
this skill covers only the cube-specific override entities (`tab_variant_cube_overview`,
`tab_variant_cube_view_overview`). The general conditional-layout mechanic (colors, fonts, condition
types) lives in `thinkwise_sf_conditional_layouts`, but note
`cube_view_field_conditional_layout` is a **separate, cube-specific entity family**, not a row in
that skill's `conditional_layout` table — see "Conditional layouts on a cube view" below.

## Golden rule — this is a judgment-call skill, not just a mechanics reference

Building a cube field or view is a handful of API calls. The part that actually matters — and the
part every piece of Thinkwise's own documentation and community feedback stresses — is getting the
**analytical design** right before touching the model:

- **State the grain first.** What does one row of the source subject mean? ("One invoiced sales
  line," "one stock position per item and location.") If a join behind the subject can duplicate a
  business fact — history joins, many-to-many, mixing transaction rows with pre-aggregated totals —
  the cube's totals will be wrong even though every individual aggregation is technically correct.
  Validate the source subject independently before creating the cube.
- **Classify every field deliberately.** The generated proposal from `task_enrichment_create_cube`
  is a starting point, not a finished cube — the documentation explicitly calls out reviewing and
  removing semantic-free ID columns, confirming values come from the most detailed (fact-grain)
  data source, and re-checking every auto-assigned dimension/value split.
- **Classify each value's additivity.** Additive (sums cleanly across every dimension, e.g. sales
  quantity), semi-additive (sums across some dimensions but not time — e.g. an end-of-day balance),
  or non-additive (percentages, ratios, unit prices, distinct counts). A cube that silently lets a
  user sum a snapshot balance across months is easy to build and wrong to read.
- **Decide if a cube is even the right tool.** See the comparison table below — a cube is for
  repeated, rearrangeable, drill-and-pivot analysis; it is not a substitute for a Grid/Form (record
  inspection/editing), a report (pixel-perfect fixed documents), a couple of fixed KPI tiles, or an
  enterprise BI platform (Power BI/Qlik/Tableau) for cross-system governed analytics — Thinkwise
  documentation explicitly recommends OData export to those tools for that scale.
- **Ask before guessing** on: the cube's/view's/field's name when the model's naming isn't obvious,
  whether a value should be editable (see "Editable values" below — this has hard technical
  preconditions, not just a checkbox), each value's additivity classification
  (additive/semi-additive/non-additive) whenever it isn't obvious from the business meaning, any
  dimension-vs-value split that diverges from what `task_enrichment_create_cube` auto-generated, and
  whether a described "one more axis" request is actually a sign the view has become an unreadable
  everything-view (avoid one cube view with dozens of dimensions/values — prefer several focused
  views).

| Need | Prefer |
|---|---|
| Inspect or edit individual records | Grid/Form |
| A few fixed KPIs | Dashboard, tiles, or a purpose-built view |
| A pixel-perfect official document | Report |
| Cross-system, governed enterprise analytics at scale | Power BI/Qlik/Tableau via OData export |
| A fixed simple trend, no pivoting needed | A plain chart on a focused subject |
| Users repeatedly rearrange/drill/slice operational data | **Cube** |

## Object graph

```text
cube  (one per source subject/table, domain key sf/manage_cubes)
 ├─ cube_field            (one per dimension/value; cube_field_type: dimension | measure)
 │   └─ cube_field_query   (per-RDBMS SQL expression, for calculated/formula fields)
 ├─ cube_view              (one saved pivot/chart configuration)
 │   ├─ cube_view_field            (places one cube_field into an area of this view)
 │   │   ├─ cube_view_field_filter        (default filter values, when area = filter)
 │   │   ├─ cube_view_field_total         (extra total rows/cols, when area = value)
 │   │   └─ cube_view_field_conditional_layout  (cube-specific conditional formatting)
 │   ├─ cube_view_constant_line     (target/threshold lines on a chart axis)
 │   └─ cube_view_field_set_up      (mirror entity backing the visual "Cube set-up panel")
 ├─ cube_view_grp           (groups views into a submenu of the cube view bar)
 ├─ chart_legend_color      (custom per-member series colors on a value's chart legend)
 ├─ role_cube_overview / role_cube_field_overview   (per-role rights, incl. cube-panel & edit rights)
 └─ tab_variant_cube_overview / tab_variant_cube_view_overview   (per-table-variant overrides,
     domain key sf/manage_datamodel — see "Per-variant overrides" below)
```

Every one of these keys off `model_id, branch_id, cube_id` first, then its own id chain — the same
pattern as every other Software Factory object family.

## Creating a cube

`task_enrichment_create_cube` — bound to the `cube` entity itself, mandatory `tab_id` (the source
table), optional `cube_description`. Documented/expected to be addressable directly by the **new**
`(model_id, branch_id, cube_id)` you want to create — the same "the task creates its own bound row"
pattern used by `task_create_tab_variant` elsewhere in the model. **Verified live this did not
work**: staging this task against a not-yet-existing cube's key was consistently rejected (across
repeated attempts and domain variants) rather than creating the row. The reliable fallback, confirmed
live: skip the task entirely and create `cube` with a plain add — set `model_id`/`branch_id`/
`cube_id`/`cube_description`/`allow_dragging_fields` by hand, the same as any other top-level entity.
This forgoes the task's auto-generated field proposal, so expect to build `cube_field` rows
individually afterward (see below) — extra work for a wide table, but the only path that reliably
works.

Running the task, when it *does* work:

- Auto-generates a proposed set of `cube_field` rows (dimensions and values) from the table's columns.
- Changes the source table's screen type to a cube-capable screen type.
- Needs review, not blind acceptance — per the docs, remove semantic-free ID columns, confirm every
  value is sourced from the fact-grain table, and re-classify anything mis-detected as dimension vs.
  value.

**`cube_field` has the same fallback need.** Its declared navigation properties on `cube`
(`detail_ref_cube_cube_field_dimension`/`_value`, splitting fields by dimension vs. value) look like
the natural parent-nav path for adding one, both are rejected as invalid parent
targets for a staged add. Add `cube_field` with a plain top-level add (the full compound key supplied
directly) instead of trying to nest it under `cube`.

`cube.default_cube_view_id` sets which view opens by default; `cube.allow_dragging_fields` is the
model-level switch for the end-user "Cube panel" (drag-and-drop self-service rearranging — see
"User customization" below). `cube.olap_connection`/`olap_server_name`/`olap_db_name`/`olap_cube_name`
are legacy Windows-GUI-only OLAP cube settings (Microsoft Analysis Services) — irrelevant to a
Universal/web cube and only relevant when maintaining an old Windows application.

`task_delete_cube` removes the whole cube. `task_unlink_generated_object` (present on `cube`,
`cube_field`, `cube_view`, and more — every entity here carries `generated_by_control_proc_id`)
detaches a row that a control procedure generated, before manually editing it — the same
generated-object convention documented for scheduler/map components.

## Naming trap: "dimension"/"measure" vs. "Dimension"/"Value"

`cube_field.cube_field_type` is a two-value enum: **`dimension`** (0) and **`measure`** (1). Every
UI screen, the docs, and the 2025.1 modeler split call the second one **"Value"**, not "Measure" —
community feedback specifically flagged the old combined "Cube fields" tab as confusing before it
was split into separate **Dimensions** and **Values** tabs. When reading or writing
`cube_field_type`, use the enum literal `measure`; when talking to a user or naming things, say
"value." Don't let the schema's internal name leak into a field's user-facing description.

## Cube fields and cube views

A cube field is either a **dimension** (categorical: who/what/where/when) or a **value** (an
aggregated measure). The schema's enum literal for the latter is `measure`, but every UI and doc
calls it a **Value** — see the naming trap above.

A **cube view** is one saved arrangement of those fields; one cube commonly carries several, each
answering a specific question.

For the full field reference (aggregation types, date intervals and hierarchies, calculated fields
via `cube_field_query`, and cube-view creation and settings), read
`references/cube_fields_and_views.md`.

**Performance:** Universal UI cubes run one filtered, aggregated query per expand (and "Expand all",
2026.1+, fires all of them at once), so the underlying view must be pushdown-safe. Read
`references/cube_performance.md` before building a cube on a large or complex view.

## Field placement in a view — `cube_view_field`

Each field in a view is placed into an **area**: filter, category (rows), series (columns), or value.
`cube_area` must be set **after** `order_no` in the same write, or it is dropped.

For the full placement reference (every area and its cardinality guidance, sorting and totals,
`cube_view_field_filter` including its use on category-row fields, constant lines, chart legend
colours, and the pivot-vs-chart presentation settings), read
`references/chart_and_field_placement.md`.

## Editable pivot values

A cube value can be made directly editable in the pivot, but it has preconditions and a structural
trap with self-referencing hierarchies. Read `references/editable_values.md` **before enabling this**.

## Permissions — `role_cube_overview` / `role_cube_field_overview`

Confirmed live, both role-scoped and independent of a table's own row/column rights:

| Entity | Key fields | Purpose |
|---|---|---|
| `role_cube_overview` | `available` | Whether this role can see/use the cube at all |
| | `dragging_fields_granted` (with meta-mirror `sf_allow_dragging_fields`) | Whether this role gets the end-user Cube panel (self-service rearrange), independent of whether the cube-level `cube.allow_dragging_fields` switch is even on |
| `role_cube_field_overview` | `available` | Whether this role sees this specific dimension/value at all |
| | `editable` (with meta-mirror `sf_editable`) + `granted` | Whether this role can edit this specific value — on top of every other editable-value precondition above |

Both carry `rights_icon` (`super_user`/`grant`/`read`/`hidden`/`unauthorized`) mirroring the standard
rights model used everywhere else. A cube can leak information through aggregated totals even when
individual rows stay hidden — apply and test subject/row-level authorization, cube and cube-field
availability, edit rights, drill-down access, and export permissions together, not any one of them
in isolation. Filters and hidden fields are UI conveniences, never a substitute for these rights.

## Screen types, customization, and known friction

A cube still needs a place to appear, and end users can reshape it at runtime.

For placing a cube on a screen type, the per-variant overrides, what the runtime Cube panel lets
users change, the known Software Factory modeling friction around cubes, and a full worked example
(a sales revenue cube end to end), read `references/cube_deployment_and_friction.md`.

## Recommended workflow — new cube from scratch

1. Write down the analytical question and audience in one sentence.
2. Identify the source subject and state its exact row grain; validate independently (control
   totals) that joins behind it don't duplicate facts.
3. `task_enrichment_create_cube` with `tab_id` (+ optional `cube_description`) to generate the
   starting proposal.
4. Review every generated `cube_field`: remove semantic-free IDs, fix any mis-classified
   dimension/value, confirm `col_id` sources are fact-grain.
5. **Gate: present the proposed dimension/value classification, hierarchy plan, and view list to the
   user, and get their explicit confirmation before proceeding to any further staged writes**
   (interval/hierarchy wiring, additional views, etc.) — don't treat step 4's review as silent
   authorization to keep building. This is the `thinkwise_sf_base`
   "Confirm-before-mutate" convention applied at this skill's own grain.
6. Set `type_of_grp_interval`/`grp_interval_numeric_range` on date/numeric dimensions that need
   bucketing; wire `cube_field_grp_id` for genuine hierarchies.
7. For ratios/margins, add a `cube_field` with `summary_type = sql_expression` and one
   `cube_field_query` row per target RDBMS, using the `t1` alias.
8. Create one or more focused `cube_view` rows — each answering one question, not an
   everything-view.
9. Add `cube_view_field` rows placing each relevant `cube_field` into `cube_area_filter`/
   `cube_area_category_row`/`cube_area_series_column`/`cube_area_value` — patch `cube_area` directly
   rather than via the drag-drop task.
10. Configure `cube_view_field_filter` defaults, `sort_order`/`sort_by_cube_field_id`,
    `show_top_x`/`show_other`, and `expand` per field.
11. Configure `cube_view` totals (`show_*_total`, `total_position`), `drill_down_grid`, and
    `default_cube_view_type` (pivot vs. chart).
12. For a chart view: `chart_type`, `chart_palette_id`, labels/legend, and any
    `cube_view_constant_line`/`chart_legend_color` overrides.
13. Add `cube_view_field_conditional_layout` sparingly, testing each apply-to-cell/total/grand-total
    flag separately.
14. Decide `cube.allow_dragging_fields` and per-role `dragging_fields_granted`; grant
    `role_cube_overview`/`role_cube_field_overview` rights.
15. Only enable `editable` on a value after confirming every precondition in "Editable pivot values"
    holds for its intended grain.
16. Wire the table's screen type/components — picking an existing cube-capable screen type, since
    creating a new one isn't supported via MCP (see `thinkwise_sf_build_planner`) — and
    any per-variant overrides (`tab_variant_cube_overview`/`tab_variant_cube_view_overview`).
17. Validate totals against an independently calculated control total, check performance at
    production-like cardinality (including "Expand all"), and test light/dark conditional-layout
    themes.

## Worked example

For a full worked example building a sales revenue cube end to end (grain, dimensions, values, the
view layout and its chart), read `references/worked_example.md`.

## Pre-flight checklist

- **State the grain and validate control totals before creating anything** — a technically correct
  `sum` over duplicated rows is still a wrong business answer.
- **`task_enrichment_create_cube` can reject a not-yet-existing cube's key outright**;
  don't spend more than one retry on it. Fall back to a plain add on `cube` (and, separately, on
  `cube_field` — its declared dimension/value navs from `cube` aren't valid parent-nav targets
  either).
- **Review the generated proposal — never accept it unchanged.** Remove ID-only fields, confirm
  fact-grain sourcing, re-check every dimension/value classification.
- **`cube_field_type` enum literal is `measure`; call it "Value" everywhere user-facing** — don't
  let the schema name leak into descriptions or conversation.
- **`cube_field_grp_id` is a self-referencing parent pointer** — set it on the *child* dimension to
  build a hierarchy; this is the opposite direction of variant-tree `parent_col_id` documented in
  the variants skill, so don't assume the two work the same way.
- **Wiring `cube_field_grp_id` is not enough to see a hierarchy in the pivot** — every level, not
  just the leaf, needs its own `cube_view_field` placement in the same area (ancestor-to-leaf order),
  or the tree renders flat with no nesting at all.
- **A self-referencing hierarchy (org chart, BOM, category tree) sharing its table with an editable
  value is a structural trap**, not just a permissions edge case — a parent with exactly one child can
  look editable and silently write into the child's row instead. Give the hierarchical/browsing view a
  second, `editable = false` field on the same column; keep the real editable field only in a
  separate flat view.
- **Calculated/ratio fields live in `cube_field_query`, one row per RDBMS, alias `t1`** — never as a
  plain average of a stored ratio column.
- **Default to a limited period and keep the underlying view pushdown-safe** — no window-function or
  `distinct` dimensions; test "Expand all" on production-sized data (`references/cube_performance.md`).

