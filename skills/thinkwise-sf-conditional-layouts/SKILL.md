---
name: thinkwise-sf-conditional-layouts
description: Reference guide for conditional layouts (conditional formatting) in a Thinkwise Software Factory model — data-driven styling such as status colours on tables, tasks, and cube views, including row/column targeting, light/dark themes, and accessibility. Use before inspecting or modifying any conditional-layout entity via an MCP connector with Software Factory access, or whenever asked to add or change status colours, warning highlights, or any "make this red/bold/green" styling.
---

# Conditional Layouts (Conditional Formatting) in the Thinkwise Software Factory

Thinkwise calls this feature **conditional layout**; despite the name, its purpose is conditional
*formatting* — changing how a value or row *looks* based on data, never what the user is allowed to do
with it. A scan of 71 model exports found 4,058 standard conditional-layout definitions (~34,000
condition records), dominated by status visualization (1,467 definitions with `status` in their
identifier) — followed by completion, progress, blocked records, invalid/missing data, priority,
changed/deleted records, and planning states.

Apply this skill whenever an MCP connector with Software Factory access is used to create, inspect, or
troubleshoot conditional layout.

## Entity and domain map

Conditional layout is **not one entity family** — it repeats, independently, once per object type it
can decorate. Domain: split-domain instances put each family in the domain of the object it decorates
(column below); single-domain `sf/software_development` holds them all; otherwise find it with
`search_domain_capabilities`.

| Object type | Entities | Domain (Indicium · split-domain) |
|---|---|---|
| Table (grid/form/edit/scheduler resource) | `conditional_layout`, `conditional_layout_condition`, `conditional_layout_tag` | `sf/manage_datamodel` — note there's no Card list or Tree surface among the `apply_to_*` flags below; see `thinkwise-sf-subject-components` for those two components generally |
| Task parameter form | `task_conditional_layout`, `task_conditional_layout_condition`, `task_conditional_layout_tag`, `task_variant_task_conditional_layout` (per-variant override) | `sf/manage_tasks` |
| Cube view (cells/totals) | `cube_view_field_conditional_layout` (condition fields are inline — no separate condition child, confirmed) | `sf/manage_cubes` |
| Scheduler time cells | `scheduler_view_conditional_layout`/`_condition`/`_tag` | `sf/manage_scheduler` — see `thinkwise-sf-schedulers`, not duplicated here |
| Report parameter form | `report_conditional_layout`, `report_conditional_layout_condition` | Not reachable in the split domains checked; reachable on single-domain — see "Report and variant conditional layout" below |

## What conditional formatting does and doesn't do

It can change: background colour, font colour, bold/italic/underline/strikethrough, font size (L/XL),
one cell or the entire row, grid/form/edit/scheduler-resource presentation, task/report parameter
styling, and cube cells/totals.

It cannot: prevent invalid data, make a field mandatory or read-only, hide a task, change
authorization, execute business logic, or guarantee a user acts on a warning. Those need validation,
layout logic, context logic, rights, or database logic instead.

> Conditional formatting communicates a state; it should not be the only mechanism enforcing that state.

| Requirement | Use instead |
|---|---|
| Show a late delivery date in red | Conditional layout (this skill) |
| Make a delivery date mandatory | Layout procedure |
| Disable a task for completed orders | Context procedure |
| Prevent an invalid delivery date | Default, task, handler, or constraint |
| Show the number of late orders | Badge |
| Only show late orders | Prefilter (`thinkwise-sf-prefilters`) |
| Explain why a value is red | Conditional-layout help text, or a supporting status/message column |

## Should this object get a conditional layout? — the canonical test

**This is the one home for this decision.** Sibling skills (data model, tasks, scheduler, cubes) point
here instead of repeating it; they contribute only their own candidate list.

When creating or changing an object, take **one deliberate pass** asking whether a conditional layout
would genuinely help someone scanning it. A good candidate is a value the user *acts on differently*
depending on what it says:

- a status or state with distinct handling per value
- a date that can run overdue
- a quantity that can breach a threshold, or a capacity that can run low
- a destructive or irreversible option that has been selected

**Only add one where there is a real candidate — not merely because a table has a status column, a
task has parameters, or a scheduler has a resource column.**

**Never create one without confirming with the user first.** Present the candidate column(s)/
parameter(s), the condition, and what the formatting would communicate, and get explicit agreement
before creating anything. A plan that includes a conditional layout is not final until that is
confirmed. (This is `thinkwise-sf-base`'s ask-don't-default convention at this
skill's own grain.)

Follow `thinkwise-sf-base`'s "Shared conventions" section (confirm-before-mutate,
ask-don't-default) at this skill's own grain: before the first `stage_resource`/`commit_resource` call,
propose to the user — in plain language — the target column(s) or rows to style, the condition(s) that
will trigger each, and the colour/severity mapping for each state. Use the "Common use cases" colour
table below as a starting point to *propose*, not a default to apply silently. Get explicit confirmation
before staging anything, particularly when the target column is one of several plausible choices (see
"Row vs. column targeting") or a state's severity is genuinely ambiguous (see "Common use cases").

## Table-level `conditional_layout` — the core family

One `conditional_layout` row per named layout on a subject, with one or more
`conditional_layout_condition` children (all must match) and optional `conditional_layout_tag` rows.
Call `get_entity_definition` for the field lists and the 18-value condition enum.

**Pass enum values as the raw integer, not the string key** — the key form is rejected.

For the per-field reference across all three entities, read `references/table_level_reference.md`.

## Row vs. column targeting

Leave `col_id` **empty** to colour the entire row; set it to colour one cell. The scan's own ratio —
383 row-level layouts vs. 3,675 column-level, plus 440 with no condition at all (always-applied) — shows
a strong platform-wide preference for focused cell formatting.

**Default to a specific column.** It gives the user a direct visual link between the problem and the
value, and stacks more legibly with other row content. Reserve whole-row formatting for genuinely
record-level states: blocked, cancelled/deleted, an entire failed message, an unavailable production
order, an urgent safety condition. Avoid whole-row for one missing field, an ordinary status column, or
several independent conditions layered onto one row — those read more clearly as separate,
column-targeted layouts. When more than one column is a plausible target, ask the user which one rather
than picking unilaterally.

## Where to apply it: `apply_to_grid` / `apply_to_form` / `apply_to_edit` / `apply_to_scheduler_resource`

Four independent booleans, verified as such (not a combined enum):

- **`apply_to_grid`** — comparative scanning across many rows: statuses, deadlines, blocked orders,
  stock shortages, integration failures, planning conflicts. The most natural home for most layouts.
- **`apply_to_form`** — state that stays relevant while viewing one record: invalid/incomplete fields,
  important record state, values needing attention before an operation. Less useful for comparative
  facts ("highest value in this list").
- **`apply_to_edit`** — only when the formatting actively helps *while editing*: a value that becomes
  invalid after another field changes, a threshold crossed mid-edit. Apply to Edit must be combined
  with Grid and Form, not used alone: it is editable only while `apply_to_grid` and `apply_to_form` are
  both `true`. A new layout gets `apply_to_edit = true` by default, so send `false` explicitly when the
  layout shouldn't show while editing. Setting Grid or Form to `false` turns it off and makes it
  read-only; setting them back to `true` unlocks it, but the value stays `false` — set it again if it
  should apply. Don't enable it if it
  would obscure the normal mandatory-field indicator or look like a hard validation error while editing
  is still permitted.
- **`apply_to_scheduler_resource`** — colours the **resource** row/label in a Scheduler's grouping
  panel rather than an activity bar (grey out an unavailable resource, tint hierarchy levels). See
  `thinkwise-sf-schedulers` for the Scheduler-specific evaluation rule
  ("first matching record per resource wins") and the HTML-formatting interaction (HTML/Multiline
  title/tooltip columns silence conditional layout, specifically font-size/strikethrough/underline).
- **No `apply_to_card_list` or `apply_to_tree`** — confirmed this is the complete flag set, so neither
  component has its own dedicated conditional-layout surface. Whether either inherits `apply_to_grid`'s
  or `apply_to_form`'s styling at render time hasn't been independently confirmed — see
  `thinkwise-sf-subject-components`'s Card List and Tree sections for the same open
  question from that side, and test empirically before relying on it.

Universal UI does not support conditional layouts on radio-button, signature, checkbox, or HTML
controls, per platform documentation.

## Colour and font fields

Universal UI and the legacy Windows GUI use different colour/font field sets on the same row, and a
layout can be authored for one and look wrong on the other.

For the two field sets, which to set for which target, and how to compute a colour value without the
Software Factory's own colour picker, read `references/colour_and_font.md`.

## Choosing conditions

Same reasoning as prefilters/tasks (see `thinkwise-sf-prefilters` for the general
column-vs-query framing), applied to the 18-value enum above:

- **Equal to / Not equal to** — discrete states (`status = BLOCKED`, `interface_status != PROCESSED`).
  With Not equal to, decide deliberately whether `NULL` should count as exceptional. For a
  boolean-domain column, the plain string literal `"true"`/`"false"` is accepted directly as the
  constant `value` — no special encoding needed.
- **Greater/smaller than, Between** — thresholds and bands (`stock_quantity < minimum_stock`,
  `progress between 80 and 99`). Use `type_of_value = column` (`value_col_id`) to compare two columns on
  the same row instead of hardcoding a threshold — more maintainable than duplicating a constant across
  many layouts.
- **Contains/starts with/ends with** — sparingly, for structured codes/prefixes/filenames. Don't derive
  business state by searching free text a user typed; add a real status/expression column instead.
- **Is empty / Is not empty** — missing-but-important data (`external_reference is empty`). If the value
  is actually mandatory, back it with real validation too, not just the colour.
- **In / Not in** — verified to exist in the enum; format of `value` not independently confirmed, test
  before relying on it.

**Expression fields** are the platform's answer to conditions needing several business rules, date
arithmetic, aggregation, related-table data, complex `NULL` handling, or role-dependent behaviour —
model a `case`-based expression column (`is_overdue`, `has_shortage`, `requires_approval`) and condition
the layout on a simple equality against it, keeping the business logic in one place instead of
duplicated across many condition rows.

## Task-level and cube-level layouts

`task_conditional_layout` styles a **task's parameters** in its popup form;
`cube_view_field_conditional_layout` styles **pivot cells** and has four independent surface flags
(`apply_to_cell` / `apply_to_total_cell` / `apply_to_custom_total_cell` / `apply_to_grand_total_cell`).
Both repeat the table-level shape rather than sharing it — call `get_entity_definition` on each for
its own fields.

For both field references and their differences from the table-level family, read
`references/task_and_cube_layouts.md`. For the cube family in depth — the four surface flags,
per-measure targeting, and the cube-specific condition shape — read
`references/cube_level_conditional_layout.md`.

## Report and variant conditional layout

`report_conditional_layout`, `report_conditional_layout_condition`, and
`report_variant_report_conditional_layout` are distinct translatable object types (see "Translation"
below).

- **(Indicium · single-domain)** `report_conditional_layout` is an ordinary entity set in
  `sf/software_development` — read its fields with `get_entity_definition` (the shape is presumably
  parallel to `task_conditional_layout`, with `report_parmtr_id` in place of `task_parmtr_id`; don't
  assume it).
- **(Indicium · split-domain)** None of the three was reachable in the domains checked
  (`sf/manage_datamodel`, `sf/manage_control_procedures`, `sf/manage_screentypes`,
  `sf/manage_tasks`); only the orphaned `report_conditional_layout_tag` was. Search the other domains
  with `search_domain_capabilities` before planning the report layout as a manual step in the Software
  Factory.

The per-table-variant override is `tab_variant_conditional_layout_overview` (`show_conditional_layout`
and the `apply_to_*` flags per variant) — reachable on single-domain; **(Indicium · split-domain)** it
was not found in `sf/manage_screentypes` or `sf/manage_datamodel`, so search the other domains before
treating table layouts as table-wide only. See `thinkwise-sf-variants` for the overview-row mechanics.

## Related but distinct: chart legend colour

`chart_legend_color`/`chart_legend_color_condition` are a **separate** mechanism (confirmed as distinct
translatable object types) for colouring chart legend entries/series — not part of the
`conditional_layout` family and not covered by this skill. Don't conflate a request to "colour a chart
series by status" with a table/task/cube conditional layout; it's a different entity family under the
chart configuration itself.

## Translation

Every layout name is a translatable object, generated with a bracket-placeholder default like any other
model object — see `thinkwise-sf-translations` for the full mechanics. Confirmed
live `type_of_object` values (from the model's own enum, not guessed):

| Object | `type_of_object` |
|---|---|
| `conditional_layout` | 44 |
| `conditional_layout_condition` | 45 |
| `conditional_layout_tag` | 573 |
| `task_conditional_layout` | 590 |
| `task_conditional_layout_condition` | 591 |
| `task_conditional_layout_tag` | 593 |
| `task_variant_task_conditional_layout` | 594 |
| `report_conditional_layout` | 585 |
| `report_conditional_layout_condition` | 586 |
| `report_conditional_layout_tag` | 588 |
| `report_variant_report_conditional_layout` | 589 |
| `cube_view_field_conditional_layout` | 49 |
| `cube_field_conditional_layout` (legacy) | 225 |
| `tab_variant_conditional_layout` | 283 |
| `scheduler_view_conditional_layout` / `_condition` / `_tag` | 1032 / 1033 / 1034 |
| `chart_legend_color` / `_condition` | 1037 / 1038 |

Before considering a new layout done, check `transl_object_transl` across every language the branch
supports (`branch_appl_lang`) for lingering `[bracket]`-placeholder text, rather than assuming one write
covered every configured language.

## Common use cases (design guidance)

Design guidance on *what* to condition on and *how* to style it (status-colour table, missing-data,
planning, deadline, financial, and generated-value patterns) — see
`references/design_patterns.md` before proposing a colour/severity mapping to the user.

## Overlapping layouts, accessibility, and when not to

Several layouts can match one row; colour alone is not an accessible signal; and some problems want a
prefilter, a status column or a separate screen rather than formatting.

For the resolution order when layouts overlap, the accessibility and contrast rules, and the cases
where conditional layout is the wrong tool, read `references/usage_guidance.md`.

## Pre-flight checklist

- **Default to a specific `col_id`/`condition_cube_field_id`/`task_parmtr_id` target**, not a blank
  whole-row layout — the platform's own usage is ~90% column-level.
- **Set `show_conditional_layout` deliberately** — a fully-configured layout can exist with it `false`;
  don't assume every row you find is active, and don't forget to flip it on when you actually want the
  layout live.
- **Set both light and dark variants of every colour** (`background_color_light`/`_dark`,
  `font_color_light`/`_dark`) — the legacy single-value fields (`background_color`, `font_id`) are
  Windows-GUI-only and ignored by Universal UI. A background colour needs no `background_type` — leave
  it out of a write (the Software Factory stores `0`), even when a layout you copy from reads back `0`.
- **Don't add a condition twice** — `conditional_layout_condition_no` is a global identity assigned on
  commit (not 1..n per layout), so the key won't catch a repeat; check for an identical condition first, and edit an existing one by full key.
- `apply_to_edit` defaults to `true` on add and is editable only while `apply_to_grid` and
  `apply_to_form` are both `true`; switching one off sets it to `false`, and switching it back on
  doesn't restore it — re-set it.
- **When targeting the scheduler-resource surface** (`apply_to_scheduler_resource = true` with
  `apply_to_grid`/`apply_to_form = false`), set `apply_to_scheduler_resource` to `true` *before* setting
  `apply_to_grid`/`apply_to_form` to `false`, doing it in the other order gets
  `apply_to_grid` silently reset back to `true` by the layout engine.
- The condition's own evaluated column/parameter/field (`conditional_layout_condition.col_id`,
  `task_conditional_layout_condition.task_parmtr_id`, `cube_view_field_conditional_layout.
  condition_cube_field_id`) can legitimately differ from the parent row's *target* — don't assume they
  must match.
- Use `type_of_value = column` (`value_col_id`/`value_task_parmtr_id`) for a threshold that varies by
  record, instead of hardcoding a constant across many layouts.
- Remember: layouts have no `order_no`/priority field — see above. Make overlapping conditions mutually
  exclusive, or drive them off one expression field.

