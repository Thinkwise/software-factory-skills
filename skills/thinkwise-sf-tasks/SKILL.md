---
name: thinkwise-sf-tasks
description: Reference guide for creating and configuring tasks in a Thinkwise Software Factory model — task types, parameters, look-ups, form setup, variants, and table task assignment. Use whenever an MCP connector with Software Factory access creates, inspects, or troubleshoots a task, before working with the task, task_parmtr, task_ref, task_variant, or tab_task family of entities.
---

# Creating Tasks in the Thinkwise Software Factory

A **task** is the Software Factory's unit of "do something" — anything from a single UPDATE
statement to a call out to an external program. Every task is its own top-level object (`task`,
keyed only by `task_id`), independent of any table. It only becomes a **table task** once it's
bound to one via `tab_task`; until then it's an **unbound** task, reachable only from a menu item,
a process flow, or the API.

Apply this whenever an MCP connector with Software Factory access is used to create, assign, or
inspect a task. Domain: `sf/manage_tasks`.

**Companion skills, not duplicated here**: the actual control-procedure/template mechanics behind
a task's generated code (code groups, business-logic variables, static vs. SQL assignment, the
two-step "generate code group then generate object code" sequence, multi-RDBMS dialects) live in
`thinkwise_sf_control_procedures` — read it before writing a task's template.
Full translation mechanics (`transl_object`/`transl_object_transl`, `type_of_object`, approval
workflow) live in `thinkwise_sf_translations`. This skill covers what's
specific to tasks; both companions cover the shared machinery in depth.

**Gotcha**: `tab_task`, `task_parmtr`, `tab_task_grp`, and `tab_task_parmtr` are also
reachable as entity sets under a `manage_datamodel`-style domain — but the master `task`,
`task_variant`, and `task_ref`/`task_ref_col` entities were **not** found there
(`entity_set_not_found`) and only resolved under `sf/manage_tasks`. Don't assume every task-adjacent
entity lives in the same domain as the rest of the data model — confirm each one via
`search_domain_capabilities`/`get_available_domains` rather than guessing from where a sibling entity
happened to resolve.

## Plan first

This is the task-grain application of `thinkwise_sf_base`'s "Confirm-before-mutate"
convention (see its Shared conventions section) — don't restate that rule, apply it. Before the first
`stage_resource`/`stage_task` call for a new or changed task, state the plan and get it confirmed. For
a task, "the plan" means naming:

- The **task type** (`task_type_id`) and whether it's **bound or unbound** — and if bound, to which
  table.
- The full **parameter list** — each parameter's direction (input/output) and purpose.
- Any **look-ups** (`task_ref`) the parameters need, and what they point at.
- Which of the **four form mechanisms** — Groups / Conditional layout / Layout / Defaults (see "Form
  setup" below) — the form will use, and why.

This generalizes the `task_conditional_layout`-specific confirmation rule further down (never add one
without checking first) to the whole task, not just its conditional layout. If the task is part of a
larger build (e.g. from `thinkwise_sf_build_planner`), fold this into that plan instead
of confirming it separately once the task is already being staged.

## Golden rule — creation order is enforced, not just conventional

A brand-new task's pieces have to be created in this order; the API rejects several of the
shortcuts:

1. **The `task` row first** — a plain `stage_resource`(add)/`patch_resource`/`commit_resource`
   against `task`, keyed only by `task_id`. There is no dedicated "create task" bound task; it's an
   ordinary entity add, the same as creating a `tab` or `col`. Nothing else below can exist before
   this row does.
2. **Bind it to a table via `tab_task`, if it's a table task** — keyed by `(tab_id, task_id)`.
   Setting `tab_task.task_id` to a `task_id` that doesn't exist yet is rejected outright, even
   though the field presents as an ordinary editable string — it's enforcing that the `task` row
   exists first.
3. **Add its parameters via `task_parmtr`** — keyed by `(task_id, task_parmtr_id)`, a child of
   `task`, **not** of `tab_task`. If a parent-based add doesn't resolve a navigation to `task`,
   fall back to a plain add with the full key supplied as explicit fields.
4. Only once all three exist does the control-procedure flow apply: **Generate code group** to
   materialize the `task_<task_id>` placeholder, then write/assign a template, then generate the
   actual code. See `thinkwise_sf_control_procedures` for that sequence in
   full — it applies to a task's own logic exactly as it does to a table's.

**A table task does not receive that table's primary key for free.** Unlike a Handler, which gets
the row's key automatically, a task bound via `tab_task` has no built-in way to know which row it's
acting on. If the task's logic needs the row's identity, add an explicit `task_parmtr` matching the
table's PK column id (e.g. `lead_id` for a task on `lead`) — otherwise this doesn't surface as an
error until the logic is written and something is silently missing.

## The object graph

| Entity | Key | Role |
|---|---|---|
| `task` | `task_id` | The master object: logic type, confirmation, badge, communication mode. |
| `task_parmtr` | `task_id, task_parmtr_id` | One row per input/output parameter, plus its default form placement. |
| `task_ref` / `task_ref_col` | `task_ref_id` / `+tab_id, col_id` | A custom look-up config for one or more parameters. |
| `task_variant` / `task_variant_parmtr` | `+task_variant_id` | An alternate presentation of the same task and parameter set. |
| `task_conditional_layout` | `task_id, conditional_layout_id` | Static, condition-driven font/colour styling on a parameter. |
| `tab_task` / `tab_task_parmtr` | `tab_id, task_id` / `+col_id, task_parmtr_id` | Binds the task to a table; binds a parameter to a column. |
| `tab_task_grp` | `tab_id, tab_task_grp_id` | Groups related table tasks under one action-bar button. |
| `tab_variant_task_overview` | `tab_id, tab_variant_id, task_id` | Per table-variant override — which task variant shows, its ordering/visibility. |
| `task_variant_look_up_overview` | `task_id, task_variant_id, task_ref_id` | Per-variant override of a look-up. |

## Task logic types (`task.task_type_id`)

This decides what kind of program object the task actually generates:

| task_type_id | Shown as | When to use it |
|---|---|---|
| `STORED_PROCEDURE` | Template | The default for real server-side logic. Generates an actual stored procedure from a control-procedure Template — everything in `thinkwise_sf_control_procedures` applies to this type. **Only this type has a template to assign.** |
| `FUNCTION` | GUI code | Client-side logic that never touches the database — copy-to-clipboard, open a URL, trigger a download. No control-procedure template; the logic lives in GUI code instead. |
| `EXTERNAL_PROCEDURE` | External stored procedure | Calls a stored procedure that already exists in the database, outside anything the Software Factory generates. |
| `EXTERNAL_FUNCTION` | External function | Same idea, for a database function. |
| `EXTERNAL_PROGRAM` | Windows command | Launches an OS-level command/executable from the server. |
| `ITP` | ITP interface | Legacy ITP integration task type. |
| `DUMMY` | None | No generated program object at all — a pure carrier (menu entry point, or something that only passes parameters into a process flow) with no server logic of its own. |

Before hunting for a missing Assigning-screen entry, check `task_type_id`: only `STORED_PROCEDURE`
tasks (and their Default/Layout/Badge sub-objects, when enabled) go through the control-procedure
assignment flow.

setting `task_type_id=DUMMY` makes the task's own `object_name` field flip to
hidden/non-editable (there's no generated object to name) — don't try to patch it for a `DUMMY` task;
only types that actually generate something (`STORED_PROCEDURE`, and presumably the other
non-`DUMMY`/non-`ITP` types) need/accept `object_name`.

`task.type_of_communication` ("Await result") is the separate, second setting controlling how the
GUI waits for the task: `synchronous` (0), `async` (1), `synchronous_with_progress` (2, the default
for Template tasks), `synchronous_with_progress_possible_async` (3).

## Task-level row &amp; behavior settings (`task` entity)

Beyond `task_type_id` and `type_of_communication` above, these `task` fields govern how the task
behaves once triggered against `sf/manage_tasks`:

| Field | Shown as | When to set it |
|---|---|---|
| `single_transaction` | Atomic transaction | On for a Template task whose related data changes must succeed or roll back together. |
| `ask_confirmation` / `confirmation_msg_id` | Ask confirmation | On for destructive/irreversible/expensive/high-impact actions, with a specific message — see `thinkwise_sf_messages`'s "Task confirmation messages". |
| `popup_for_each_row` | Popup for each row | Off (the default) to show the task's form/confirmation once for the whole selection; on only when each selected row genuinely needs its own input or its own confirmation — flipping it on for an ordinary bulk action is the message-storm anti-pattern (`thinkwise_sf_messages`). |
| `shift_code` + `ascii_code` | Shortcut | Together form the keyboard shortcut (a modifier plus a key code) — set both or neither; avoid GUI/reserved or duplicate combinations. |
| `show_badge` + `badge_interval` | Show badge / Badge interval (seconds) | Only when a meaningful badge query will actually be implemented and refreshed at a sensible interval — see the Badge concept in `thinkwise_sf_control_procedures`. |
| `repeat_after_execute` | Repeat after execute | On for repetitive capture workflows (e.g. scanning) where the form should reopen immediately after each execution, not for ordinary one-shot actions. |
| `generation_order_no` | Generation order | Change only when one generated task genuinely depends on another having generated first. |
| `offline_executable` | Offline executable | On only after checking platform constraints — an offline task cannot use look-ups, and any parameter meant to be filled by the user (rather than an offline-safe default) must be hidden. |
| `icon_id` | Icon | Set to a suitable icon from the repository as part of creating the task — the task's own icon wherever it appears (action bars, menus). Follow `thinkwise_sf_icons`; a task icon should show the outcome/verb, not a generic gear. |

## Bound, unbound &amp; table tasks — and the security implication

An unbound task (no `tab_task` row) can still be a menu item, a process-flow step, or an IAM
start object — and per platform-team guidance, **it remains reachable through the Indicium API even
with none of those wired up.** Not showing a task anywhere in the GUI is not the same as securing
it; role/rights configuration is what actually restricts who can call it. If logic should never be
independently callable at all, prefer a genuine subroutine/function control procedure over an
unassigned task.

A **table task** is the same `task` row plus a `tab_task` binding — that's what gives it row
context and lets `tab_task_parmtr` auto-fill a parameter from the current row's column (see
Parameters below).

## Parameters (`task_parmtr`)

Each row is one input or output on the task's form, independent of any table:

| Field | Purpose |
|---|---|
| `task_input` / `task_output` | Direction: typed in by the caller, or returned for the caller to use afterward. |
| `type_of_col` | `editable` (0) / `read_only` (1) / `hidden` (3) — static, independent of the dynamic Layout mechanism below. |
| `mand` | Static mandatory-ness, before any dynamic Layout logic can loosen or tighten it. |
| `dom_id` | Domain backing the parameter's type/control — set explicitly, don't trust a default. |
| `type_of_default_value` / `default_value` / `default_value_query` | A literal default, or a query evaluated when the form opens — the lightweight alternative to a full Default control procedure. |
| `case_type` | Upper / lower / initial caps / proper case, enforced on input. |
| `alias_task_parmtr_id` | Points this parameter's identity at another parameter's — the same borrowing pattern `col.alt_transl_col_id` uses for columns, for deliberately sharing presentation/translation rather than duplicating it. |
| `label_width` / `field_width` / `field_height_in_positions` / `field_no_of_positions_further` / `field_in_next_col` | Static form placement/sizing — pure layout, no code. |
| `form_field_in_next_grp` + `form_next_grp_label` | Starts a new labelled group on the form. |
| `field_on_next_tab` + `next_tab_label` | Starts a new section/tab on the form. |
| `layout_input` / `layout_type_output` / `layout_mand_output` | Column-level gate for the Layout concept (see Form setup). |
| `default_input` / `default_output` | Column-level gate for the Defaults concept (see Form setup). |

**Table task parameter binding**: `tab_task_parmtr` (keyed by `tab_id, task_id, col_id,
task_parmtr_id`) binds a parameter to a specific column of the bound table so it auto-fills from
the selected row instead of asking the user to type it. This is the explicit step needed to give a
table task the row's PK or any other row-derived value — nothing does this automatically.

## Task look-ups and form setup

A task parameter can offer a look-up, and a task's popup form is shaped by four different mechanisms
that are easy to conflate (parameter order, groups, `task_conditional_layout`, and the screen type).

Use the standalone `task_ref`/`task_ref_col` add flow for look-ups — `task_create_task_ref` fails on
the follow-up call.

For both in full (the look-up entities and their control enum, and all four form mechanisms with
guidance on which to reach for), read `references/task_form_and_lookups.md`.

## Variants, assignment, logic, and translation

- **Task variants** — an alternative presentation of the same task; the general variant mechanic
  lives in `thinkwise_sf_variants`.
- **Assigning a table task** — one `tab_task` row per (table, task). Two variants on the same table
  screen need two *table* variants via `tab_variant_task_overview`, not two `tab_task` rows.
- **A task's own logic** is an ordinary control procedure; only `STORED_PROCEDURE` tasks go through
  the Assigning flow (`thinkwise_sf_control_procedures`).
- **Translation** — a task's name, tooltip and every parameter translate separately; see
  `thinkwise_sf_translations`.

For the step-by-step on each (variant creation and parameter overrides, bulk-copying an assignment
with `task_copy_task`/`task_copy_tab`, renaming/deleting, and the per-object translation ids), read
`references/task_maintenance.md`.

## `task.object_name` / `task.task_description` reject a direct patch

Both can reject a direct patch with an "unknown property"-style error **even set in complete
isolation** — they look editable in the staged view but the write layer refuses them.
`object_name` auto-derives from `task_id` (observed default: `<code_type_prefix>_` + `task_id`) and
is not reliably overridable this way. If a task genuinely needs a different generated object name,
treat it as unresolved through this write path rather than retrying the same patch.

## Pre-flight checklist

- **Create in order**: `task` → `tab_task` (if table task) → `task_parmtr` → generate code group →
  assign template → generate object code. Each step's API rejects the ones that skip ahead.
- **Add the table's PK as an explicit `task_parmtr`** on any table task whose logic needs to
  identify the row — it is never supplied automatically.
- **Check `task_type_id` before assigning a template.** Only `STORED_PROCEDURE` goes through the
  control-procedure Assigning flow.
- **Both enablement gates** — task-level `use_layouts`/`use_defaults` *and* parameter-level
  input/output flags — before assuming a Default/Layout template actually runs.
- **One `tab_task` row per (table, task).** Two variants on the same table screen need two table
  variants (via `tab_variant_task_overview`), not two `tab_task` rows.
- **Hiding a task isn't securing it.** An unassigned task is still callable via the API; use
  role/rights to actually restrict it.
- **Bulk-copy (`task_copy_task`/`task_copy_tab`) is a starting point, not a final state** — prune
  what the target doesn't need.
- **Set a tooltip on a new task as part of finishing it** — a Software Factory validation flags a
  task, report, or prefilter left with no tooltip text at all.

