# Scheduler click-to-create, double-click popup, and external drag-drop

Loaded on demand from `thinkwise_sf_schedulers`.

## External drag-and-drop

Users can drag rows from an unrelated grid/tree (a backlog of unassigned orders) onto a time cell to
create an activity from them, via a **drag-drop link** (`drag_drop` entity family — the full field
reference for `drag_drop`/`drag_drop_parmtr`/`drag_drop_matrix`, including the `drop_behavior`
enum and the variant-combination matrix, lives in `thinkwise_sf_subject_components`;
this section only covers what's specific to a Scheduler as the drop target):

1. On the source subject, define a drag-drop link: source tab, target tab (the Scheduler's subject),
   and a **Drag-drop task** run on drop.
2. Map **Drag-drop parameters** — source column → task parameter.
3. Because the target is a Scheduler, a **Drop date time parameter** field appears; picking it
   auto-populates the Scheduler's own `activity_start_task_parmtr_id`.
4. Set the Scheduler's **Add activity task** to the same drag-drop task so click-to-create and
   drag-to-create share logic.
5. Enable the interaction (`Enable drag-drop`) — it's off by default.

Dragging multiple selected rows fires the task once **per row**, not a single batched call; parameters
shared between source and target are validated for equality on drop — a mismatch silently blocks the
drag rather than erroring.

## Click-to-create and double-click → popup

### Click-to-create (Add activity task)

Build a table task with parameters for everything the new activity needs, set it as the Scheduler's
**Add activity task**, and pick a **Start date time parameter** — the clicked cell's date/time is
passed in automatically (`scheduler.activity_start_task_parmtr_id`). `PROJECT_MANAGER`
uses `project_planning_scheduler_add_activity`, a plain `STORED_PROCEDURE` table task, wired to
`activity_start_task_parmtr_id = start_date`.

**Other parameters can auto-populate from the clicked row too, not just the start date.** The start
date/time binding above is the one field the Scheduler special-cases explicitly
(`activity_start_task_parmtr_id`); a task parameter with default-input enabled and named identically to
a column on the subject should also inherit that column's value from the clicked row through the
platform's ordinary column-to-parameter default-binding mechanism (the same one table Defaults use) —
useful for passing along which resource was clicked, not just when. **Not independently verified
against a live click** — reasoned from the platform's general default-input mechanism; test it against
an actual click before relying on it silently working.

**A parameter that should render as a look-up in the task's input form isn't automatically one just
because its domain matches a real table's primary key.** Model a task-level reference for it (the task
equivalent of a table's `ref`) pointing at the source table, the same way an FK-shaped view column
needs its own `ref`/`ref_col` before it gets look-up behavior (see `thinkwise_sf_data_model`).

**Known limitation**: no built-in way to disable "Add activity" for specific resources/resource
groups. Workaround: a default value or a process-flow check that blocks execution and shows a message.

**Hide the task's own display**: an Add-activity task is meant to be triggered only by the click,
never as a manual toolbar button sitting next to it — set the table task's display type to hidden
(leave it enabled/shown as a table task otherwise; hiding only its button rendering doesn't disable
the click-to-create binding, which fires independently of button visibility).

**The new Add-activity task (and its parameters) needs translating too.** Like any newly created
task, it's created with a bracket-placeholder translation (`[employee_schedule_add_activity]`) —
that's what shows on the table-task button/toolbar until it's translated, not a broken label.
`scheduler_view` rows (e.g. `month`, `work_week`) get the same placeholder treatment. Follow
`thinkwise_sf_translations` after wiring up the Scheduler to catch these
alongside the underlying subject's own table/column labels.

### Double-click — two valid routes

1. **Simple route — direct task.** Table task with `grid_double_click = true` on the Scheduler's
   subject. `PROJECT_MANAGER`'s own activity double-click,
   `project_planning_scheduler_open_activity_detail`, is exactly this — a plain `STORED_PROCEDURE`
   table task, no process flow at all. Use this when double-click just needs to run logic or navigate.
2. **Popup route — DUMMY task + process flow.** Use this when you specifically want a modal detail view
   without leaving the Scheduler screen. Full recipe below.

### The DUMMY-task + process-flow + popup recipe

**1 — Create a DUMMY task.** `task_type_id = 'DUMMY'` — no SQL of its own; its only job is to be
something a grid can double-click and a process flow can declare as its starting point. `PROJECT_MANAGER`'s Scheduler toolbar buttons `project_planning_scheduler_go_to_date` and
`project_planning_scheduler_go_to_next_week` are both `task_type_id = DUMMY`.

**2 — Wire it up.** Attach the dummy task as a table task on the Scheduler's subject; check
**Double click on record** (`tab_task.grid_double_click = true`) for a double-click trigger, or
`show_tab_task = true` alone for a toolbar button.

**3 — Build the process flow.** Name it by the model's own convention — `pf_<task_id>` verified in
this model — check **User action** (`process_flow.use_starting_points = true`), add the dummy task as
its starting point, and lay out `start` → *actions* → `stop`.

**4 — The actions.** For a jump-to-date flow (**verified**, `pf_project_planning_scheduler_go_to_date`):
`start` (98) → `execute_tab_task` (6, runs the DUMMY task to collect a date) → **`activate_scheduler`
(790)**, a dedicated Scheduler process action that jumps the Scheduler to that date → `stop` (99). For a
double-click-to-detail flow: `start` → **`change_filter`** (330, filters the target table to the
double-clicked row's key) → **`open_document`** (2, opens a **dedicated table variant** rather than the
default) → `stop`.

**5 — Make "Open document" render as a popup, not a navigation.** Point step 4's `open_document` at a
table variant whose `main_screen_type_id`, `detail_screen_type_id`, `zoom_screen_type_id` **and
`popup_screen_type_id`** are all set to the same lightweight screen type. the flow
`open_employee_calendar_item` (`start` → `change_filter_employee_calendar_item` (330) →
`open_document_employee_calendar_item` (2, `tab_variant_id = form_only`) → `stop`) targets a
`form_only` variant with exactly this shape. Skip the dedicated `popup_screen_type_id` and "Open
document" just does a normal full-screen navigation instead of a modal.

Relevant `process_action_type` codes, verified:

| Action | Code |
|---|---|
| `start` | 98 |
| `stop` | 99 |
| `execute_tab_task` (Start table task) | 6 |
| `change_filter` (Change filters) | 330 |
| `open_document` (Open document) | 2 |
| `activate_scheduler` (Activate Scheduler) | 790 |

**Note**: in the live reference model, `open_employee_calendar_item` is actually invoked via
`process_flow.use_api_trigger = true` from a custom FullCalendar component rather than a grid
double-click — the change-filter/open-document/popup-variant mechanism is identical regardless of
trigger; combine it with steps 1–2 above to get the double-click version.

**Tip — more than one action per appointment.** Double-click only gives one destination. If users need
to choose between several actions (edit, cancel, duplicate…), route the double-click into a process
flow with a chooser step instead of cramming branching logic behind a single click.

**Gotcha**: if a task parameter comes through empty on double-click, check the underlying view's join
before touching the task/parameter mapping — a real case traced an empty parameter to the view not
joining on both the resource and the activity id.
