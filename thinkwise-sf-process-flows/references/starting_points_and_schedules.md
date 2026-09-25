# Process flow starting points, schedules, and canvas alignment

Loaded on demand from `thinkwise_sf_process_flows`.

## Schedules

Weak entity under `process_flow`. Mandatory: `model_id`, `branch_id`, `process_flow_id`,
`schedule_id`, `recurrence_type` (default `daily`=0; other values `weekly`=1, `monthly`=2),
`recurrence_day` (default `1`), `occur_type` (default `once`=0; other values `recurring`=1,
`recurring_all_day`=2), `occur_once` (mandatory **only** when `occur_type=once` — a `TimeOfDay`).

Day-of-week flags (`monday`…`sunday`) are hidden and only relevant when `recurrence_type=weekly`;
month-position fields only matter when `recurrence_type=monthly`. Minimal daily-at-a-fixed-time
schedule: `{model_id, branch_id, process_flow_id, schedule_id, occur_once: "02:00:00"}` with
everything else left at its default.

Schedules only make practical sense once the flow qualifies as a system flow (every action
non-interactive) — a schedule on a flow that still has an interactive action has nothing meaningful
to fire unattended.

## Starting points — what can launch a flow, and a hard write-API limitation

`process_action_start_object_available` records which real object (a table row, a report, a task) can
launch the flow, landing execution at a specific `process_action` rather than always at the literal
`start` node. It references `process_action_id` directly; which kind of object is the candidate is
expressed by *which* of its FK-shaped columns is populated (`tab_id`/`tab_variant_id`,
`report_id`/`report_variant_id`, `task_id`/`task_variant_id`) — there's no separate discriminator
column.

**Only eight `process_action_type` values are ever observed as starting points**, confirmed against
real data across ten live models:

| Type | Why it can start a flow |
|---|---|
| `activate_detail` (1) | Opening/activating a detail is itself a user launch point |
| `open_document` (2) | Opening a document can be the trigger |
| `add_record` (3) | Creating a new row can launch a flow (e.g. a wizard) |
| `edit_record` (4) | Editing a row can launch a flow |
| `delete_record` (5) | Deleting a row can launch a flow |
| `execute_tab_task` (6) | The overwhelming majority of real starting points — any table task |
| `execute_task` (60) | A standalone task launching a flow |
| `execute_system_task` (61) | A system task launching a (system) flow |

Every other type — including `start`, `stop`, `execute_tab_report`/`execute_report`/`generate_report`,
`activate_grid`/`activate_form`, `decision`, and every connector type — was **never** observed as a
starting point. `start`/`stop` are excluded because they're the flow's own implicit entry/exit, not
things a user or API launches into; reports have schema support (`report_id`/`report_variant_id`
columns exist) but weren't exercised in any live model sampled — treat report-triggered starts as
theoretically schema-supported but unverified in practice.

**`process_action_start_object_available` itself is read-only through this MCP write API** — both
`add` and `edit` via `stage_resource` return `403`/`staging_request_failed`, even against an existing
row, and the only bound write operation found, `task_reset_process_action_start_object` (zero
parameters), *clears* a starting point rather than selecting one. **This is not actually a blocker,
and no manual step in the Software Factory's own UI is needed** (correcting an earlier version of this skill that claimed
otherwise): **the trigger object simply needs to be modeled as its own eligible-type action wired
directly to `start` inside the flow.** Any action of one of the eight types above that sits
immediately after `start` is automatically usable as a launch point for its underlying task/table/
report — `process_action_start_object_available` reflects that structural fact rather than being a
separate switch you flip. Confirmed live (2026-07-28): a menu-triggered flow needs an `execute_task`
action (`task_id` = the menu's trigger task) as the first action after `start`; putting the trigger
task outside the flow and hoping to "wire it up" separately (via the Software Factory's own UI or
otherwise) is the mistake to avoid — build it into the flow's own action chain instead.
