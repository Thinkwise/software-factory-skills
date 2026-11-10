---
name: thinkwise-sf-roles
description: Reference guide for roles and rights in a Thinkwise Software Factory model — adding a role, granting rights by editing the per-role role_*_overview rows, what read access on a table does and does not grant (columns, prefilters, details, task/report parameters, cube fields), side effects of update rights, and completing a role so it can do its job on its own. Use whenever an MCP connector with Software Factory access creates or inspects a role or any role_*_overview entity, and whenever planning which role gets which rights.
---

# Roles and rights in the Software Factory

Confirm connector, `model_id`, and `branch_id` per `thinkwise-sf-base` first. Its write hazards apply
to every edit here: refusals come back as normal results, properties apply in order and stop at the
first refused one, and every written field must be read back.

Menu-level rights (menu, list bar group/item, tile group/tile) and their `rights_icon` enum are
documented in `thinkwise-sf-menus` ("Security: grant, don't fork"); this skill owns the general rights
model and the completeness rules.

## Plan first

Apply `thinkwise-sf-base`'s **Confirm-before-mutate** rule. Before the first write, state per role:
which tables it reads/changes, which tasks, reports, process flows and cubes it gets, which columns
stay hidden on purpose, and how each object is reached (menu item, tile, detail, look-up). Get the
user's explicit confirmation. **Ask, don't default** on the two flags that widen a role far beyond its
job: `all_rights` and `allow_public_api` stay false unless the user explicitly asks for them.

## Adding a role

Add `role` under `branch` with `role_id`, `role_description` (mandatory) and `order_no`. SF then
creates its translation object (type 707) and an overview row per object for the role's rights.
Deleting the role deletes its rights, but not its `transl_object` row — delete that too (see
`thinkwise-sf-translations`).

## Rights are edits of SF's overview rows

SF keeps one overview row per role and object as soon as both exist. **A right is an edit of that row,
by its full key; the edit creates the rights record.** Never add or delete these rows (the entity sets
allow update only). Prefer plain edits over the `task_*_set_rights` wizards (e.g.
`task_role_tab_prefilter_set_rights`): those are multi-row tasks with `next_action`/`input_set`
parameters.

The rows are virtual until an edit changes them: an edit that sends the current value commits
without error but stores nothing, so read the rows first and edit only those whose value really
changes.

| Right | Overview entity (key after model_id, branch_id) | Fields |
|---|---|---|
| Table | `role_tab_overview` (role_id, tab_id) | `select_granted`, `insert_granted`, `update_granted`, `delete_granted`, `export_granted`, other `*_granted` |
| Column | `role_col_overview` (role_id, tab_id, col_id) | `col_access_type`: 0 editable, 1 read-only, 3 hidden (numeric) |
| Detail | `role_tab_detail_overview` (role_id, ref_id) | `granted` |
| Task | `role_task_overview` (role_id, task_id) | `granted` |
| Table task | `role_tab_task_overview` (role_id, tab_id, task_id), per table that shows the task | `granted` |
| Task parameter | `role_task_parmtr_overview` (role_id, task_id, task_parmtr_id) | `col_access_type`: 0, 1, 3 |
| Prefilter | `role_tab_prefilter_overview` (role_id, tab_id, tab_prefilter_id) | `visible`, `always_on` |
| Menu / tile levels | see `thinkwise-sf-menus` | `granted` |
| Cube | `role_cube_overview` (role_id, cube_id) | `dragging_fields_granted` (the cube panel) |
| Cube view | `role_cube_view_overview` (role_id, cube_id, cube_view_id) | `granted` |
| Cube field | `role_cube_field_overview` (role_id, cube_id, cube_field_id) | `granted` |
| Process flow | `role_process_flow_overview` (role_id, process_flow_id) | `granted` |
| Subroutine | `role_subroutine_overview` (role_id, subroutine_id) | `granted` (for a role that calls it through the API/GUI) |
| Report | `role_report_overview` (role_id, report_id) | `granted` |
| Table report | `role_tab_report_overview` (role_id, tab_id, report_id) | `granted` |
| Report parameter | `role_report_parmtr_overview` (role_id, report_id, report_parmtr_id) | `col_access_type`: 0, 1, 3 |

Field names drift between versions — confirm with `get_entity_definition` before the first edit of an
entity you haven't used in this session.

## What a grant does and does not grant

Most grants only make the parts of an object **available** to the role; each part needs its own grant.

- **Read on a table** makes its columns, prefilters, cube fields and the menu items that open it
  available, but grants none of them:
  - every column stays hidden (`col_access_type` 3) until set to 1 (read-only) or 0 (editable — still
    effectively read-only while the role lacks update/insert on the table). A role with read alone sees
    an **empty screen**, so grant every column the user works with, and leave a column hidden only on
    purpose (cost prices, technical fields) by sending 3;
  - prefilter rows read `visible` true by default: send `always_on` true for one that limits the role
    to its own rows (with `visible` false to lock it), and `visible` false for one the role must not
    switch;
  - every cube field stays ungranted.
- **Task and report parameters** stay hidden (3) after the task or report is granted: give each 0 or 1.
  A task parameter's effective access also counts the table task, so grant that too. A parameter whose
  own `type_of_col` is 3 stays hidden whatever the role grants — change the parameter instead. Read back
  `effective_col_access_type`, not only `col_access_type`: every column without a grant of its own yet
  (not just calculated ones) can read back a value outside 0/1/3, such as 4.
- **A look-up column**'s grant is stored but has no effect until its display column is granted —
  grant the display column first, then read back the look-up column's effective access.
- **A detail** (`role_tab_detail_overview`) becomes available only once the role reads both its source
  and target table, and is still not granted: grant it when the user reaches the child from the parent.
- **A report** grant makes its table reports (on tables the role reads) and its parameters available
  only; grant each table report and parameter (see `thinkwise-sf-reports`).
- **A menu group or item** reads `available = false` until its menu (and, for an item, its group) is
  granted — grant top-down: menu, group, item (see `thinkwise-sf-menus`).
- **A process action** (`role_process_action_overview`, read-only) is available only when the role
  holds the right the action opens — table, detail, task, table task or report (`action_available`
  says whether it does). Grant the flow and those rights.

### Side effect of `update_granted`

Setting `update_granted` true also switches on `grid_edit_mode_granted`, `import_granted` and
`mass_update_granted`. Send them false **in the same edit**, after `update_granted`, when the role
should not have them. Without update they are read-only (and false): don't send them in an edit that
doesn't set `update_granted` true, not even as false — a refused field stops the rest of the write.

## Completing a role

A role must be able to do its job on its own. With each grant, also grant what it depends on:

- a table task needs its task; a table report needs its report and read on the table;
- a shown look-up needs read on its source table (the `source_tab_id` of each `ref` whose
  `target_tab_id` is the table read); a look-up column the role cannot see (3) needs none;
- a menu item needs its group, its menu and the right on what it opens; a tile needs its tile group,
  its menu, and the right on what it opens;
- a cube needs read on its table;
- every table the role reads needs a way in: a menu item or tile, a detail from a table it opens, or a
  look-up;
- the columns of every table it reads, the parameters of its tasks and reports, the prefilters of its
  tables, the fields of its cubes, and the rights its process flows' actions open.

Grant only what the job needs: read alone on look-up tables, no insert/update/delete there. A role for
external users (a customer or employee portal) should never get read on a table it doesn't need, not
even to close a gap — that exposes every row of it.

**Every table and task needs at least one role.** SF validation reports `val_tab_not_assigned_to_role`
and `val_task_not_assigned_to_role` otherwise; the exception is a task only system flows run.

## Role design

Give a role one responsibility. Instead of adding ever more menu items to a department or job role,
add an operational role for the activity (one menu item or tile, or one focused variant) and map it to
the user group in IAM. SF flags overly broad roles with `val_role_menu_items`. Configuration roles,
which maintain base data, are the exception and may hold several items.

## Pre-flight checklist

- Role plan confirmed with the user; `all_rights`/`allow_public_api` false unless asked.
- Rights set by editing existing overview rows by full key — never add/delete them; never resend an
  unchanged value (it commits as a silent no-op).
- After read on a table: columns granted (0/1) or deliberately hidden (3); prefilters set; cube fields
  granted.
- After a task/report grant: table task/table report granted; parameters given 0/1;
  `effective_col_access_type` read back.
- `update_granted` side effects reset in the same write where unwanted.
- Every object reachable (menu item, tile, detail or look-up); look-up source tables readable.
- Validation clean for `val_tab_not_assigned_to_role`, `val_task_not_assigned_to_role`,
  `val_role_menu_items`.
