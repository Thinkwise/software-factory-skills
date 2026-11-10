---
name: thinkwise-sf-reports
description: Reference guide for adding and maintaining reports in a Thinkwise Software Factory model — report, report_parmtr, tab_report, tab_report_parmtr and tab_report_grp, naming, what cannot be done through the write API (uploading a layout), opening a report from a menu, tile or process flow, translations, deletion, and report rights. Use whenever an MCP connector with Software Factory access creates, inspects or deletes a report or any of its child entities, and before planning a report in a build.
---

# Reports in the Software Factory

Confirm connector, `model_id`, and `branch_id` per `thinkwise-sf-base` first; its write hazards apply
to every write here. The routes below were observed on SF 2026.2 through the write API.

## Plan first

Apply `thinkwise-sf-base`'s **Confirm-before-mutate** rule. Before the first write, state: the report
id (with prefix), which table(s) show it, its parameters and where each takes its value from (a column
of the selected row, or user input), how it is opened (table report button, menu item/tile, process
flow), which roles get it — and that the **layout upload is a manual Software Factory step** (below).
Get the user's explicit confirmation.

## Routes

| Object | Operation | Fields that matter |
|---|---|---|
| Report | add `report` under `branch` | `report_id`, `report_type_id`, `report_description`, optional `type_of_communication` |
| Report parameter | add `report_parmtr` under `report` (key `report_id, report_parmtr_id`) | `report_parmtr_id`, `dom_id`, `order_no` (10, 20, …), `type_of_col` (0, 1, 3), `mand`, `report_parmtr_description` |
| Table report | add `tab_report` under `tab` (key `tab_id, report_id`) | `report_id`, `order_no`, optional `tab_report_grp_id` |
| Table report parameter | add `tab_report_parmtr` under `tab_report` (key `tab_id, report_id, col_id, report_parmtr_id`) | `report_parmtr_id`, `col_id` — the column the parameter takes its value from |
| Report group | add `tab_report_grp` under `tab` (key `tab_id, tab_report_grp_id`) | `tab_report_grp_id`, `tab_report_grp_description` (mandatory), `order_no` |

## Naming

Reports share one id namespace with tables, tasks and process flows, and SF derives program objects
from the id (`layout_<id>` for every table, task and report). A report named exactly like a table broke
LAYOUTS generation for the whole model. Give every report a distinguishing prefix: `rpt_`
(`rpt_sales_invoice`). See `thinkwise-sf-data-model` for the general naming rules.

## The layout cannot be uploaded through the write API

- An add with only `report_id` defaults `report_type_id` to `DER` (DevExpress), which needs a layout
  file in `file_spec` (a file contract) and a `report_action`. A string in `file_spec` only sets the
  file name and the commit fails with `422 file_upload_not_finished`; an object value is refused
  (property values must be scalar). `file_spec_data` is not editable.
- SSRS and Clear Reports need `path_spec`, a server path, and are server-hosted.

So add the report as type `DUMMY` (None): it stores with no file and no report action. Changing the
type to `DER`, uploading the layout and setting the report action are a **manual step in the Software
Factory** — list it in the plan and in the hand-off.

## Parameters and table reports

- SF proposes a `dom_id` for a new parameter — the domain of a column named like it, else a domain
  named like it — and `order_no` 10, 20, ….
  Name a parameter that receives a column's value like that column and give it the column's domain.
- **SF makes no `tab_report_parmtr` rows**, not even for parameters named like columns of the table.
  For each parameter that takes its value from the selected row, add a `tab_report_parmtr` under the
  `tab_report` yourself. SF doesn't check that the parameter's and column's domains match — check it
  yourself.
- A table report joins a report group by `tab_report_grp_id` (on add or by an edit). A table report has
  no translation object of its own.
- Report variants exist (`task_create_report_variant` is bound to `report`); see
  `thinkwise-sf-variants` before deciding a second report is needed.

## Opening a report

- **Table report button:** the `tab_report` row itself.
- **Menu item or tile:** `menu_item_type` 2, sent *before* `report_id` (setting the type clears the
  other targets) — see `thinkwise-sf-menus`.
- **Process flow:** action type 70 (execute report) needs `report_id`; action type 7 (execute table
  report) needs `tab_id` and `tab_report_id` (the report id). SF seeds one parameter input row per
  report parameter per report action; set an input by editing
  `process_action_modeler_report_parmtr_input` (a direct add of the stored input row is refused). See
  `thinkwise-sf-process-flows`.

## Translations

Fill the translation objects SF creates: report type 10, report parameter type 31, report group type
17 (see `thinkwise-sf-translations`). A parameter named like a column gets its type-31 translation
from that column's translation (a bracket placeholder if the column has none yet) — fill the column
first, then check the parameter instead of retyping it. They are left behind when the report is deleted; remove them with
`delete_record` on `transl_object`.

## Deleting a report

`task_delete_report` (bound, key only) removes the report with its parameters, its table reports and
their parameters, and the menu items that open it — but not a `tab_report_grp` it leaves empty;
delete that group yourself if nothing else uses it. Clean up the orphaned translation objects after.

## Rights

SF makes a `role_report_overview` row per role as soon as the report exists. A table report needs its
report, read on the table, and its own grant; report parameters stay hidden (`col_access_type` 3) after
the report is granted. Full rules in `thinkwise-sf-roles`.

## Pre-flight checklist

- Id prefixed `rpt_`, not colliding with a table/task/process flow id.
- Added as `DUMMY`; layout upload + `report_action` flagged as a manual step.
- Every row-bound parameter has its `tab_report_parmtr`, with matching domains.
- Opening route wired (table report, menu item type 2 before `report_id`, or process action 70/7 with
  parameter inputs edited).
- Translations (10, 31, 17) filled; rights granted per `thinkwise-sf-roles`.
