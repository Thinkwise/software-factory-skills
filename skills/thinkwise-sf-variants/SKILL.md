---
name: thinkwise-sf-variants
description: Reference guide for creating, configuring, and maintaining table, task, and report variants in a Thinkwise Software Factory model — the field-level-vs-snapshot inheritance mechanism and the Changes-compared-to-default/where-used mechanics. Use whenever creating, inspecting, or troubleshooting a variant via an MCP connector with Software Factory access, and before deciding whether a request needs a new variant at all versus a prefilter, a new screen type, or a separate table/task/report.
---

# Creating and Maintaining Variants in the Thinkwise Software Factory

A **variant** is an alternative presentation or configuration of an existing table, task, or report
— never a copy of its data or logic. A table variant still queries the same table/view; a task
variant still executes the same task procedure and parameter set; a report variant still runs the
same report. What changes is screen type, columns, permissions, defaults, wording, icon, and similar
presentation/context settings — never the underlying query, business logic, or authorization.

```text
Default subject, task, or report
              |
              +-- Variant A: selected overrides
              +-- Variant B: selected overrides
              +-- Variant C: selected overrides
```

Apply this whenever an MCP connector with Software Factory access is used to create, inspect, or
modify a variant of any kind. Domain: split-domain instances `sf/manage_datamodel`; single-domain
`sf/software_development`; otherwise find it with `search_domain_capabilities`.

**Companion skills, not duplicated here**: full task-variant mechanics (`task_variant`,
`task_variant_parmtr`, `task_variant_look_up_overview`, creation via `task_create_task_variant`) live
in `thinkwise-sf-tasks` — read it before building a task variant; this skill covers
only how a table variant *selects* a task variant (`tab_variant_task_overview`). Screen-type
assignment fields (`main_screen_type_id` etc.) must point at a screen type that already exists —
prefer an existing one, or build it first (`thinkwise-sf-subject-components`'
`references/screen_types.md`); see
`thinkwise-sf-build-planner`'s interaction-surface step and the screen-type API-quirk
note in `thinkwise-sf-data-model`. Conditional-layout-per-variant mechanics live in
`thinkwise-sf-conditional-layouts`. Prefilter states and groups live in
`thinkwise-sf-prefilters`. Scheduler and map per-variant settings live in
`thinkwise-sf-schedulers` and `thinkwise-sf-maps`.
Unit-testing guidance (what to test, what not to) lives in
`thinkwise-sf-unit-tests`.

## Golden rule — this is a judgment call skill, not just a mechanics reference

The mechanics of building a variant are simple API calls. The hard part — and the actual point of
this skill — is **deciding whether a variant is the right tool at all**, which one of the three
kinds to use, and how much of it to override. Whenever the guidance below doesn't make the answer
obvious, **stop and ask the user** rather than silently picking the option that sounds safest. This
applies especially to:

- Whether the request needs a variant at all, or is better served by a plain (unlocked) prefilter, a
  screen-type change on the default, or a genuinely separate table/task/report (see "Variant versus
  another mechanism" below).
- Which of the three variant kinds — table, task, report — actually matches what's being asked.
- Whether a described difference is "presentation/context" (variant-safe) or "different data, logic,
  or side effects" (needs a real separate object, not a variant).
- The variant's **name**, when the model's existing naming pattern is ambiguous or inconsistent.
- Any **delete**, or a change that resets/overrides something a menu item, detail, lookup, process
  flow, or drag-and-drop link currently depends on — confirm intent first (see "Track every
  reference" below).
- Whether a **set-level aspect** (grid, form, card list, tree, detail, filter, search, or sort) needs
  a Setup snapshot at all, versus staying inherited from the default. Taking that snapshot is a real,
  semi-durable design commitment (see "Set-level settings" below) — confirm it with the user before
  calling any `task_setup_tab_variant_*_overview` task; this is not a call the assistant should make
  unilaterally.

Only skip asking when the answer is genuinely unambiguous — e.g. the user names the exact variant to
reuse or extend, or the difference is trivially and entirely a presentation change.

## The three variant kinds — object graph

| Kind | Master entity(ies) | Presentation entity | Key | Created via |
|---|---|---|---|---|
| Table (subject) variant | `tab` (default) | `tab_variant_overview` | `tab_id, tab_variant_id` | Plain add against `tab_variant` (flat, no parent) — `task_create_tab_variant` exists but is not usable through the write API (see "Creating, copying, renaming, deleting a table variant") |
| Task variant | `task` (default) | `task_variant`/`task_variant_overview` | `task_id, task_variant_id` | `task_create_task_variant` — see `thinkwise-sf-tasks` |
| Report variant | `tab_report`/report master (default) | `report_variant` + `report_variant_overview` | `report_id, report_variant_id` | Plain `stage_resource` add against `report_variant` — the known-working route; a bound `task_create_report_variant` (on `report`) does exist but is untested, and may hit the same form-variant staging problem as `task_create_tab_variant` |

A table variant is by far the most structurally rich of the three — it carries not just its own
scalar settings but a full family of child `tab_variant_*_overview` entities, one per configurable
aspect of the table (columns, grid, form, tasks, reports, prefilters, look-ups, details,
conditional layouts, cubes, scheduler, maps, card list, tree, sort, filter, search).

### Before creating: confirm the plan

Before the first `tab_variant`-add/`task_create_task_variant`/`report_variant`-add call,
lay out the plan in one short message and get the user's confirmation on it — the create call itself
is cheap to undo, but the design decisions behind it (see the Golden rule above) are not ones to
guess at. This is the `thinkwise-sf-base` "Confirm-before-mutate" convention applied
at this skill's own grain:

- Which of the **three kinds** (table, task, report) this is.
- The intended **name**.
- Which **fields** will be overridden (field-level settings) and which **sets** (grid, form, card
  list, tree, detail, filter, search, sort) will get a Setup snapshot versus staying inherited.
- Any **variant→variant chaining** (a look-up or detail pointed at a specific variant of another
  table) this variant will introduce or depend on.

Only skip this confirmation when the user has already stated all of the above unambiguously.

### Creating, copying, renaming, deleting a table variant

Copy, rename and delete go through the dedicated bound tasks — keys aren't renamable in place, the
same pattern as tables/columns/tasks elsewhere in the model. **Creating** does not:

- **Create with a plain `tab_variant` add, not `task_create_tab_variant`.** The task (mandatory
  `tab_id`, `tab_variant_id`, `generate_transl_object`; optional `tab_variant_description`) stages,
  but every parameter patch — and any properties passed on stage — fails with
  `staged_resource_type_not_found`, because its staged type is a gui_form variant (verified through
  the write API on SF 2026.2). Instead add `tab_variant` directly, flat with no parent, sending
  `model_id`, `branch_id` (key lookups with `value_kind: "data"`), `tab_id` and `tab_variant_id`
  first, then any description. On commit SF creates the child overview rows itself (e.g.
  `tab_variant_col_overview`, form, grid, prefilter overviews) — patch those afterwards.
  `generate_transl_object` defaults to `false`; set it to `true` when the variant needs its own
  translation. Reported on SF 2026.2, the variant's own translation (type 281) appears only at
  definition generation, not right after the add — see `thinkwise-sf-translations`.
- `task_copy_tab_variant` — `from_tab_id`, `from_tab_variant_id`, `to_tab_variant_id`. Copies an
  existing variant's full configuration as a starting point for a new one (e.g. cloning a
  structurally similar variant onto the same or a different table).
- `task_rename_tab_variant` — `tab_id`, `from_tab_variant_id`, `to_tab_variant_id`.
- `task_delete_tab_variant` — `tab_id`, `tab_variant_id`. **Check `tab_variant_used` first** (see
  "Track every reference" below) — deleting a variant that a menu item, detail, lookup, or process
  flow still points at breaks that reference. The delete leaves the variant's `transl_object` rows
  behind; delete those too (see `thinkwise-sf-translations`).

Once created, a table variant's own row carries a full set of scalar fields — screen types,
CRUD/grid/form behaviour flags, icon, page size, badge, offline settings, and more (see the
field-level list below), each independently overridable. **Many of them only take effect with their
`apply_*` flag on `tab_variant` switched on** (`apply_main_screen_type_id`,
`apply_detail_screen_type_id`, `apply_icon`, `apply_page_size`, `apply_badge_interval`,
`apply_max_no_of_records`, `apply_no_of_cols_in_form`, …): set the flag together with the value, flag
first.

## Inheritance — the mechanic that actually matters

A variant inherits from its default until its `task_setup_tab_variant_*_overview` has run. Before
Setup it is pure inheritance; after Setup that surface holds independent values and **stops tracking
the default**. This is the single most common source of surprise in variant work: a change to the
base table silently stops reaching a variant that has been Set up.

For the full mechanic (field-level vs. snapshot inheritance per surface, exactly what Setup and Reset
do, the Changes-compared-to-default view, where-used, and the known gap where
`task_setup_tab_variant_tree_overview` does not populate `parent_col_id`), read
`references/inheritance_mechanics.md`.

## Attaching tasks, reports, look-ups, and details to a table variant

Once a table variant exists, it already has one row per task/report/prefilter/look-up/detail the
default table has — the same auto-population pattern as `tab_variant_col_overview`. Configure the
variant's presentation by patching these rows, not by re-adding them:

| Overview entity | Key | What it overrides |
|---|---|---|
| `tab_variant_task_overview` | `+task_id` | `show_tab_task`, **which `task_variant_id` shows** for this variant, icon, group, screen area, primary action, display type, order |
| `tab_variant_report_overview` | `+report_id` | `show_tab_report`, which `report_variant_id` shows, icon, group, screen area, display type, order |
| `tab_variant_look_up_overview` | `+ref_id` | Look-up control type, popup, **which `look_up_tab_variant_id`** the reference resolves to, visibility for filter |
| `tab_variant_detail_overview` | `+ref_id` | `show_detail`, order, screen area, **which `detail_tab_variant_id`** renders the detail, alt. translation for the reference-add label |
| `tab_variant_prefilter_overview` | `+tab_prefilter_id` | `main_prefilter_state`/`detail_prefilter_state`/`look_up_prefilter_state` (off/off_hidden/on/on_locked/on_hidden), group, order |
| `tab_variant_conditional_layout_overview` | see `thinkwise-sf-conditional-layouts` | Per-variant conditional formatting |
| `tab_variant_scheduler_overview` / `tab_variant_map_overview` / `tab_variant_cube_overview` | see their component skills | Per-variant scheduler/map/cube view selection |

**This is the one-`tab_task`-row-per-table constraint's resolution, confirmed by design**: `tab_task`
itself only allows one row per `(tab_id, task_id)` — it cannot carry two task variants of the same
task on the same table. Showing two task variants side by side means giving them **separate table
variants**, each independently picking its own `task_variant_id` via its own
`tab_variant_task_overview` row. The same logic applies to `tab_variant_report_overview` for report
variants.

**Look-up and detail chaining**: `tab_variant_look_up_overview.look_up_tab_variant_id` and
`tab_variant_detail_overview.detail_tab_variant_id` let one table variant point a reference or
detail at a *specific variant* of the target table, rather than its default. This is how a
"compact lookup" or "portal detail" variant on table B gets wired into a variant of table A — but
per the research, avoid chaining variant→variant→variant more than one or two levels deep before it
becomes difficult to trace which effective configuration actually renders at runtime.

## Report variants — creation and settings

`report_variant` itself is a bare add — the known-working route. A bound `task_create_report_variant`
does exist on `report` (an earlier search missed it), but it has not been run through the write API
and may hit the same form-variant staging problem as `task_create_tab_variant`; prefer the direct
add. Add it against `report_variant` (`report_id`, `report_variant_id`),
then configure the presentation entity `report_variant_overview` (same key), which carries:

| Field | Purpose |
|---|---|
| `report_action` | What happens on run — verified enum: `none`, `print_preview`, `print`, `export_to_PDF`, `export_to_RTF`, `xml`, `csv`, `xls`, `xls_data_only`, `xlsx_data_only`, `doc`, `word_rtf`, `xlsx`, `docx`, `tiff`, `html`, `png` |
| `printer_id` | Target printer, for a variant meant to print rather than preview/export |
| `type_of_communication` | Await-result mode — `synchronous`, `async`, `synchronous_with_progress` (default), `synchronous_with_progress_possible_async` |
| `display_parmtr_id` | Which report parameter's value is shown as the variant's display label |
| `confirm_button_has_alt_transl`/`alt_transl_confirm_button`, `cancel_button_has_alt_transl`/`alt_transl_cancel_button` | Per-variant Confirm/Cancel wording — leave off unless genuinely different from the default report |
| `icon_id`, `show_badge`/`badge_interval`, `no_of_cols_in_form`, `form_col_min_width_factor`, `conditional_layout_code` | Presentation, same pattern as table/task variants |
| `generate_transl_object` | Keep on unless deliberately sharing the base report's translation |

This is the mechanism behind the `print`/`preview`/`export_pdf`/`export_excel`-style variant families
— same report content and data selection, different `report_action`/`printer_id`/parameter defaults.
If the content, template, or underlying dataset must differ, that's a separate report, not a variant
(see below).

## Deciding when to use a variant — and when not to

A good variant describes one stable audience, workflow, or entry point in a single sentence:
*"Shop-floor view of released production operations, opened from the workstation menu, locked to the
current workstation, card layout, start/pause/complete/material-registration tasks only."* If it
can't be summarized that concisely, it may be trying to be a genuinely separate object.

| Requirement | Prefer |
|---|---|
| Same data and logic, different screen presentation | Table variant |
| Same task logic, different defaults or wording | Task variant |
| Same report, different parameters or output behavior | Report variant |
| User can optionally toggle a filter | A normal (unlocked) prefilter — not a variant |
| Dedicated menu worklist with a locked context | Table variant (with a locked/hidden prefilter) |
| Reusable component arrangement across unrelated subjects | A screen type — prefer an existing one; build a new one only when nothing fits (see `thinkwise-sf-build-planner`) |
| Different SQL dataset or joins | A separate view/table |
| Different business logic or side effects | A separate task |
| Different report content or template | A separate report |
| Different authorization | Roles and access control — a variant can only make rights *more* restrictive, never grant something the default/role denies |
| Tenant isolation | Access-control and data-isolation logic, not a variant |
| Different navigation, branding, or deployment | Separate application configuration |
| Personal presentation preference | User personalization, where available |

**Avoid creating a variant when**: the underlying query must genuinely differ; the action has
different business semantics; the report needs a different template or dataset; it would be the
*only* control on who can do what (rights must be enforced independently); the only real difference
is an optional filter a normal prefilter would cover; it requires overriding almost every setting
(a sign the "variant" is actually a separate object in disguise); it exists only to avoid fixing a
poor default; or a near-identical variant already exists with purely cosmetic differences.

## Naming, maintenance, and testing

Name a variant for the *job* it serves, not the role that happens to use it. When the base table
changes, every Set-up variant needs checking — Setup froze those surfaces, so new columns do not
appear automatically.

For the naming conventions, the Changes-compared-to-default / where-used maintenance workflow, and
what to test on a variant, read `references/variant_maintenance.md`.

## Pre-flight checklist

- **Ask before deciding** whether a variant is warranted at all, which kind, and its name — per the
  Golden rule above — whenever the framework doesn't make it obvious.
- **Create in the right order**: the `tab_variant` add (or the equivalent for task/report
  variants) first, committed; only then patch the auto-populated child `*_overview` rows. Don't use
  `task_create_tab_variant` — its parameters can't be set through the write API.
- **Field-level settings with an `apply_*` flag need that flag on** — set `apply_<field>` on
  `tab_variant` before (or with) the value, or the override has no effect. Per-row overrides without a
  flag (e.g. `tab_variant_col_overview.type_of_col`) stop inheriting the moment they diverge from their
  `default_*` mirror.
- **Set-level settings (grid/form/card list/tree/detail/filter/search/sort): run `task_setup_*`
  before editing a row.** Editing one row of a not-yet-set-up set snapshots *all* its rows into the
  variant anyway — and can change rows you didn't touch (a hidden PK came back visible,
  `type_of_col` 3 → 1). Re-read the whole set after any edit, and don't take the snapshot unless the
  set truly needs to be stable independently.
- **Use `task_reset_tab_variant_<x>_overview` to intentionally return to inheritance** — it exists
  for every overview kind, not just the snapshot ones.
- **Query `tab_variant_change` to audit drift** before a release or after any bulk copy — it's a
  live comparison, not a stored table, and only lists genuine differences.
- **One `tab_task`/`tab_report` row per table** — two task/report variants on the same table need
  two table variants, each with its own `tab_variant_task_overview`/`tab_variant_report_overview`
  selection, not two base rows.
- **Report variants: add `report_variant` directly** — the same bare-entity-add pattern the tasks
  skill documents for the `task` master row. `task_create_report_variant` exists on `report` but is
  untested and may fail like `task_create_tab_variant`.

