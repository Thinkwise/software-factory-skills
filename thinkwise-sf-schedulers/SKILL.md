---
name: thinkwise-sf-schedulers
description: Reference guide for creating and maintaining a Scheduler component in a Thinkwise Software Factory model — the scheduler_view entity family, resource columns, and time-cell conditional layouts. Use before working with a scheduler-related entity (including the bearing table's own task/process flow), and before writing or reviewing the control procedure template behind a scheduler view or its update handler.
---

# Setting Up and Maintaining a Scheduler Component in the Thinkwise Software Factory

Reference for the Scheduler's full lifecycle: the underlying subject's data model (one non-nullable
primary key, resource + activity rows in a single view) → `scheduler` (table-level config: resource
grouping, activity-linked columns, drag permissions) → one or more `scheduler_view` rows (timescales,
pagination, time-cell display) → `scheduler_view_resource_col` (extra read-only columns in the
resource panel) → `scheduler_view_conditional_layout`/`_condition`/`_tag` (time-cell colouring) →
screen (a dedicated Scheduler-only screen type) → tasks and process flows (click-to-create,
double-click-to-detail, external drag-and-drop, jump-to-date). Every entity/field/value below was
confirmed live against a real model (`sf/manage_scheduler` domain, with some of the same entities also
reachable via a `sf/manage_datamodel`-style domain in at least one connector) and against a working
reference application (`PROJECT_MANAGER`) implementing multi-table hierarchical resource planning with
HTML-formatted activities.

Apply this whenever an MCP connector with Software Factory access (`sf_mcp`, `indicium`) is used to
create, inspect, or troubleshoot a Scheduler component — follow the connector's standard
discovery→act flow; never guess entity/task/property names.
`scheduler`/`scheduler_view`/`scheduler_view_resource_col`/`scheduler_view_conditional_layout*`
typically live in a `manage_scheduler`-style domain; the underlying subject's `tab`/`col`/`ref` live in
a `manage_datamodel`-style domain (which may *also* expose `scheduler` and
`scheduler_view_conditional_layout*` directly — check both if the first search comes back empty rather
than assuming a single domain owns them); `control_proc`/`control_proc_template` (the view's SQL,
update handlers) live in a `manage_control_procedures`-style domain; `tab_task`/`task` live in a
`manage_tasks`-style domain; `process_flow`/`process_action` live in a `manage_process_flows`-style
domain For general data-modeling rules (naming, domain reuse, reference direction, unique indexes) see
`thinkwise_sf_data_model`. For how to actually write and generate the SQL behind a scheduler
subject that's a view (`tab` → `control_proc`/`control_proc_template` →
`template_prog_object_item` → generated `CREATE VIEW`, including the two-step "generate code group"
then "generate object code" sequence) see `thinkwise_sf_views` — a scheduler
subject is, in every verified case, a `create_view_method = template` view, since a real scheduler
subject always needs a `UNION` of resource types and/or calculated HTML/colour columns that Meta
Auto/Meta Custom can't express. For control-procedure mechanics generally (code groups, static vs. SQL
assignment, `branch_rdbms_type`, dialect translation) see
`thinkwise_sf_control_procedures`; every control procedure referenced below
(the view's SELECT, update handlers, process-flow-called tasks) is created and generated exactly that
way. This skill only covers what's specific to the Scheduler.

## What a Scheduler component is

A Scheduler visualizes appointments or tasks on a timeline: **time cells** represent slices of time (an
hour, a day, a week…) and **activities** are appointments plotted against a **resource** — an employee,
a machine, a truck, a room. It is a **Universal UI-only** built-in component; the legacy Windows GUI
equivalent (**Resource Scheduler**) needs a hand-written object model extender and should be treated as
legacy for new work (see "Migrating from the legacy Resource Scheduler extender" below). A table or
variant gets a Scheduler by placing the **Scheduler** screen component in one of its screen types; the
component silently hides itself if no `scheduler` row exists for that table, or if placed in a Windows
GUI screen without the extender — an empty component is usually a sign the definition is missing, not
that something crashed.

## Recommended workflow — new Scheduler from scratch

1. **Interview the user on the Scheduler's core design before touching the model**: resource shape
   (single grouping column vs. a multi-level hierarchy, and if hierarchy, whether it spans one
   self-referencing table or several physically different tables — the latter needs the
   prefixed-synthetic-key technique below); which `scheduler_view`s are needed and their
   timescales/pagination/business-hours behaviour; whether date-dragging and/or resource-dragging
   should be enabled; whether external drag-and-drop and/or an Add-activity task are in scope, and
   if so, which columns on the subject become that task's parameters; and how the activity's
   title/tooltip should render — see "Ask before building: what should an activity look like?"
   under "HTML and multiline activity formatting" below for the exact question (and HTML-style
   follow-up) to ask.
2. **Present that plan and get the user's explicit confirmation before creating any
   `scheduler`/`scheduler_view` row.** This is the Scheduler-specific instance of the
   confirm-before-mutate / ask-don't-default rules in `thinkwise_sf_base`'s
   "Shared conventions" section — resource shape, view/timescale count, drag-drop scope, and
   Add-activity parameters are all real design decisions, not mechanical CRUD, so don't let staging
   begin section by section without a confirmed plan covering all of them first.
3. Only then proceed entity by entity: confirm/build the subject's data model (primary key,
   resource+activity union shape) → `scheduler` → `scheduler_view` row(s) →
   `scheduler_view_resource_col` → conditional layout → screen → tasks and process flows — each of
   the sections below, in order.

## The subject the Scheduler points at

The subject (table or view) supplies both the activities and the resource rows.

Three constraints decide whether a Scheduler will work at all:

- **The primary key must be a single non-nullable column** — not a composite of resource + date. A
  nullable PK on a `UNION`-based view breaks drag-and-drop with a 400.
- **`max_no_of_records` and `page_size` must both be `0`** on the subject, or platform pagination
  fights the Scheduler's own windowing.
- **A view subject usually needs an instead-of update trigger** for resource dragging, unless the
  resource key is a format-matched string shared verbatim between resource and activity rows.

For the key design in depth (prefixed synthetic keys for a hierarchy spanning several tables,
representing resources with no activity, and the view-subject reference direction), read
`references/subject_data_model.md` — and `references/hierarchy_key_example.md` for a worked prefixed
synthetic-key hierarchy.

## `scheduler` — one row per table/variant

Keyed by `(model_id, branch_id, tab_id)`. `get_entity_definition` returns the full field list with
enums (`type_of_resource_grp_by`: `single_col_grp_by` = 0, `hierarchy_grp_by` = 1), the resource
grouping and activity title/tooltip/start/end column pointers, and the dragging flags. What it does
**not** tell you:

- **Create this row as a detail of its owning `tab` row, not unscoped.** A bare top-level add can be
  rejected in a way that reads like a permissions failure when it is really a routing problem.
  Navigate to the `tab` row and add through `detail_ref_tab_scheduler`; that also auto-populates
  `tab_id`, `model_id` and `branch_id`, so there is no need to set them by hand. When an unscoped add
  is rejected, check the entity's parent-relationship options before concluding access is missing.
- **`add_activity_task_id` and `activity_start_task_parmtr_id` both reject a direct patch**, returning
  `unknown_property` even when isolated in their own call on a freshly staged resource — and
  `add_activity_task_id` does so while reporting as `editable` in the staged field view.
  Build and generate the Add-activity task itself through the API (that part works fully), then
  **bind both `scheduler` fields by hand in the Software Factory** and say so.
- `activity_start_task_parmtr_id` is the Add-activity task's parameter that receives the clicked time
  cell's start date/time — the link that makes click-to-create land on the right slot.

## `scheduler_view` — one row per view

Keyed by `(model_id, branch_id, tab_id, scheduler_view_id)`. One Scheduler can offer several views
(Day/Week/Month-style), each with its own timescales, pagination and cell styling. Call
`get_entity_definition` for the field list and enums; what follows is what it won't tell you.

**Creating a new `scheduler_view` may be impossible through the write API.** On some connectors
`scheduler_view` reports `allow_add/update/delete = false` with no bound tasks, *and* `tab` exposes no
`detail_ref_tab_scheduler_view` navigation — unlike `scheduler`, which is created through
`detail_ref_tab_scheduler`. `tab_variant_scheduler_view_overview` is not an alternative: it is a
per-variant show/hide + conditional-layout toggle for a *pre-existing* view and cannot originate one.
Try the `tab` detail route first; if both signals above hold, **treat new-view creation as a manual
Software Factory step and say so** rather than hunting for alternate entity names. Everything
targeting an *existing* view is unaffected.

**Field semantics worth knowing** (the rest are self-describing):

| Field | What it actually does |
|---|---|
| `enable_sliding_window` | Off: a page spans the full range of the highest timescale (Jan 1–Dec 31 for a year). On: the window centres on *today* — quarter/month start a week back, year a month back |
| `show_label_lowest_time_scale` | Off still slices cells at that interval for fine-grained drag-drop; it only suppresses the header labels |
| `use_time_scale_*` + `time_scale_*_interval` | Which timescales are active, and the interval of each (e.g. every 2 hours) |
| `min_displayed_time` / `max_displayed_time`, `hide_monday`…`hide_sunday` | Business-hours and weekday clamp |

**Modeling rule of thumb**: the **highest** enabled timescale is the page you paginate through, the
**lowest** becomes the individual cells, and anything between renders as an extra header row.
Configure at least two timescales per view.

**Working hours are per view, globally — there is no per-resource working-hours setting.** Model
per-resource variation as differently-styled activities or time-cell conditions.

**Resources always sort alphabetically** on the grouping column; there is no sort-by-date/priority
setting. A numeric prefix baked into the grouping value is the usual workaround.

## `scheduler_view_resource_col` — resource panel columns

Keyed by `(model_id, branch_id, tab_id, scheduler_view_id, col_id)`. Shows extra, read-only
information alongside each resource in the grouping panel (an employee's role, a truck's capacity).

| Column | Purpose |
|---|---|
| `include_resource_col` (flag) | Whether the column is actually shown — an un-included row is configured but hidden |
| `order_no` | Display sequence |
| `col_width` (int, px) | Initial width; users can resize it afterwards (cached in the browser) |

Making one visible is conceptually three steps: locate the row, check `include_resource_col`, set
`order_no`/`col_width`. Point resource columns at a translated **look-up** value rather than a raw
foreign key or code — the panel is read-only real estate. Verified: all three of `PROJECT_MANAGER`'s
views expose exactly one resource column, `resource_name`, 250px wide.

**Locating the row, verified**: don't assume "locate" means "add" — through the API in use, a direct
add of a new `scheduler_view_resource_col` record (even when correctly routed as a detail of its
`scheduler_view`) was rejected, because the actual writable surface for this data exposes a
differently-named "overview" variant of the entity where **a row already implicitly exists for every
candidate column** on the view's subject, defaulting to not-included. The correct approach is to
address that existing row directly by its full key (`model_id`/`branch_id`/`tab_id`/
`scheduler_view_id`/`col_id`) as an **edit**, then set `include_resource_col = true` and the
`order_no`/`col_width` you want — not to add a new row. If an API's schema exposes both a plain-named
entity and an "overview"/similarly-suffixed variant for the same data, and a direct add on the plain
one fails, check whether the variant is the one actually meant to be written to.

Bound tasks: `task_show_history`, `task_unlink_generated_object`.

### Conditional layout on a resource column

There is **no resource-column-specific conditional layout entity** — use an ordinary table-level
`conditional_layout` targeting that same `col_id` on the subject table, with
`apply_to_scheduler_resource = true`.

Whether a resource column warrants one at all is the canonical test in
`thinkwise_sf_conditional_layouts`. The scheduler-specific candidates are a
capacity/availability figure that can run low or over, a role/type that should stand out, or a status
meaning the resource cannot currently take work. A plain always-populated label like `resource_name`
rarely needs styling.

## Time-cell colouring (`scheduler_view_conditional_layout` and friends)

This family colours the **background time cells** of a scheduler view — resource availability,
absence, capacity windows — as distinct from colouring the activities themselves. It is genuinely
optional: a scheduler can rely entirely on activity-level HTML styling instead.

For the entity/field reference, the condition and tag structure, the worked pattern for a varying
per-period resource state, and the "work time" capacity pattern, read
`references/time_cell_colouring.md`.

## Resource grouping

| Type | Setup |
|---|---|
| **Single column** | One resource column; rows sharing a value group together (e.g. group trucks by `truck_type`) |
| **Hierarchy** | A group-by column and a parent group-by column; every parent must also exist as its own resource row; configure default-expanded state and how many levels deep |

For a hierarchy spanning more than one physical table, use the prefixed-synthetic-key technique above
rather than assuming hierarchy grouping requires a single self-referencing table.

## Screen setup

Verified real configuration (`PROJECT_MANAGER`'s `project_planning_scheduler` `tab` row) — the pattern
to replicate for any new Scheduler:

| `tab` field | Value | Why |
|---|---|---|
| `main_screen_type_id` / `detail_screen_type_id` | both a screen type containing **only** the Scheduler component | Keeps the Scheduler as the sole focus of the screen |
| `max_no_of_records` / `page_size` | `0` / `0` | Disables platform grid pagination so the Scheduler's own windowing controls what loads — normal pagination fights the component otherwise |
| `allow_add` / `allow_copy` / `allow_delete` | `false` | Mutation happens through drag-drop/tasks, not the standard record CRUD buttons |
| `allow_update` | `true` | **Required** — drag/drop and resize write through this |
| `use_update_handlers` | `true` | Needed for a view subject to accept the drag/drop writes |

## Update handlers, resizing, and drag-drop

Dragging, resizing and reassigning activities are all the same mechanism: the Scheduler's update
handler writes new start date / end date / resource values straight into the subject's underlying
table (or, for a view, through whatever instead-of trigger sits behind it). Two prerequisites gate all
of it:

1. **Update permission** on the subject (off by default for views — a very common reason drag-drop
   silently does nothing).
2. The two toggles on `scheduler`: `allow_date_dragging` (move within the same resource) and
   `allow_resource_grp_dragging` (reassign to a different resource) — both default to on.

**Resizing** is date-dragging applied to one end only — if only one of the start/end date parameters is
wired on the related task/handler, resizing only works from that one edge.

**Resource dragging** rewrites the grouping column to the target resource's value; on a view subject
this needs an instead-of trigger unless the prefixed-synthetic-key trick (above) is in play. Before
reporting drag-drop as "broken," check, in order: (1) Update permission on the subject, (2) whether the
subject is a view needing an instead-of trigger, (3) whether the primary key contains a nullable
column.

**Only the columns `scheduler` actually configures** (`resource_grp_by_col_id`,
`activity_start_date_col_id`, `activity_end_date_col_id`) are guaranteed to reflect a drag/resize's
outcome inside the update handler. Other update-handler-enabled columns on the subject still arrive as
ordinary handler parameters, but nothing guarantees they're fresh on a drag — don't derive a
write-critical value (a foreign key, say) from one of those instead of from the configured column.
**Caution, not independently verified against a live drag** — a reasoned inference from the handler's
parameter contract, flagged here so it gets tested rather than assumed the first time it matters.

## Click-to-create, double-click, and external drag-drop

Three interaction recipes sit on top of a working scheduler: dragging a row from another grid onto
the scheduler, clicking an empty time cell to add an activity, and double-clicking an activity to
open a popup.

For all three (the `drag_drop` wiring for external drops, the Add-activity task and its
`activity_start_task_parmtr_id` binding, and the DUMMY-task + process-flow recipe behind a
double-click popup), read `references/click_and_drop_recipes.md`.

## Styling activities and resources

Activities can be coloured by a `conditional_layout` on the subject table, or styled inline with HTML
in the title column. **The two do not compose**: HTML/multiline formatting silences conditional
layout's font-size, strikethrough and underline on that activity — style inline in the HTML instead.
Resource-row styling uses `apply_to_scheduler_resource` on an ordinary table-level layout.

**Ask before building what an activity should look like** — a plain title, a title plus subtitle,
or a richer multi-line card — rather than assuming one.

For the activity/resource conditional-layout details and the HTML formatting contract, read
`references/activity_presentation.md`. For the HTML/multiline formatting contract itself, read
`references/html_activity_formatting.md`.

## Migrating from the legacy Resource Scheduler extender

The old Windows GUI Resource Scheduler extender (three separate subjects: Resource, Task/Activity,
Worktime; hand-written object model extender code; a zoom slider instead of named views) maps onto the
Scheduler component's concepts one-for-one, but not automatically. For the full concept-by-concept
comparison table and the step-by-step migration checklist, read `references/legacy_migration.md` before
starting a migration.

## Bound-task quick reference

| Entity | Bound tasks |
|---|---|
| `scheduler_view` | `task_copy_scheduler_view`, `task_delete_scheduler_view`, `task_rename_scheduler_view`, `task_show_history`, `task_unlink_generated_object` |
| `scheduler_view_resource_col` | `task_show_history`, `task_unlink_generated_object` (no copy/rename/delete — see the "Locating the row" note above: the row already exists implicitly for every candidate column and is edited in place, not deleted and re-added) |
| `scheduler_view_conditional_layout` | `task_copy_scheduler_view_conditional_layout`, `task_delete_scheduler_view_conditional_layout`, `task_rename_scheduler_view_conditional_layout`, `task_show_history`, `task_unlink_generated_object` |

`task_copy_scheduler_view` takes `from_tab_id`/`from_scheduler_view_id`/`to_tab_id`/
`to_scheduler_view_id` — useful for cloning a working timescale/pagination setup (e.g. `work_week`) onto
a new table rather than re-typing every flag.

## Known pitfalls

- **Nullable primary keys on `UNION`-based subjects break drag-and-drop** with a 400 error — synthesize
  a non-null, prefixed row identifier per union branch instead.
- **Resource dragging on a view subject needs an instead-of trigger** unless the resource key is a
  format-matched string shared verbatim between resource rows and activity rows.
- **Update permission is off by default for views** — the most common reason drag-drop silently does
  nothing.
- **A time-scale condition on a timescale the view doesn't enable is always true** — colours every
  cell, not none.
- **HTML/Multiline formatting silences conditional layout** on that activity (specifically font-size,
  strikethrough, underline) — style inline in the HTML/CSS instead.
- **No per-resource working hours** — `min_displayed_time`/`max_displayed_time`/hide-weekday are set
  per `scheduler_view`, globally.
- **Resources always sort alphabetically** on the grouping column — no date/priority sort setting.
- **No native resource capacity/availability concept** — model it via synthetic activities or explicit
  hour columns feeding a time-cell condition.
- **`max_no_of_records`/`page_size` must both be `0`** on the subject — otherwise platform pagination
  fights the Scheduler's own windowing.
- **No built-in way to disable Add-activity for specific resources** — gate it in the task/process flow,
  not by trying to suppress the click.
- **No single-resource calendar/day view, and no Gantt dependency lines** — both are deliberate product
  gaps; a custom component (e.g. FullCalendar-based as `employee_calendar_item` in the
  reference model) is the sanctioned route for either.
- **A rejected unscoped/top-level "add" of a new `scheduler` record is not necessarily a permissions
  problem** — before concluding access is missing, retry it addressed as a detail of its owning
  table's record instead of as a standalone create. A rejected top-level add and a routing problem can
  look identical from the error alone.
- **`scheduler_view_resource_col` is not directly addable, even correctly routed as a detail of its
  `scheduler_view`** — the writable surface is an "overview"-style variant of the entity with a row
  already implicit for every candidate column; locate and edit that existing row by its full key
  instead of adding a new one.

## Pre-flight checklist

- Create the `scheduler` record as a detail of its owning table's record, not as an unscoped/top-level
  add — the latter can be rejected outright even with correct permissions. For
  `scheduler_view_resource_col`, check whether the API exposes an "overview"-style variant with rows
  already implicit per candidate column — if so, edit the existing row by its full key rather than
  adding one.
- The subject's primary key is a single, non-nullable column — never resource + date, never a raw
  union-inherited column that goes `NULL` on some branches.
- `main_screen_type_id`/`detail_screen_type_id` point at a Scheduler-only screen type, and
  `max_no_of_records`/`page_size` are both `0`.
- At least two timescales are enabled per `scheduler_view`, and any `scheduler_view_conditional_layout_condition`
  constrains at least the lowest timescale actually present on that view.
- Update permission is enabled on the subject before expecting drag-drop to do anything.
- HTML/Multiline-controlled title/tooltip columns don't also rely on conditional layout for
  font-size/strikethrough/underline — those are silently ignored once HTML is in play.
- A DUMMY task used as a process-flow trigger carries no SQL/business logic of its own — that belongs
  in the flow's `change_filter`/`open_document`/`activate_scheduler` actions and their control
  procedures.
- A popup-style "Open document" target has its own `popup_screen_type_id` set on the variant being
  opened — without it, "Open document" navigates instead of popping up.

