# Task variants, renaming/copying/deleting, control procedures, and translation

Loaded on demand from `thinkwise_sf_tasks`.

## Task variants (`task_variant`)

An alternate **presentation** of the same task — same `task_id`, same parameter set, same
generated logic — with its own icon, badge, confirmation message, display parameter, and
Confirm/Cancel button labels/translations. `task_variant_parmtr` lets a variant override a
parameter's mandatory-ness or default value; `task_variant_look_up_overview` lets it override a
parameter's look-up. Both support resetting back to the base task's configuration.

A variant **cannot** change the parameter list — that needs a genuinely different `task_id`.
Variants are for "same operation, different face" — e.g. one boolean-flip task exposed as an
"Activate" variant (default value `1`) and a "Deactivate" variant (default value `0`).

Create one from the owning task with `task_create_task_variant` (parameters: `task_id`,
`task_variant_id`, `task_variant_description`, `generate_transl_object`) — leave
`generate_transl_object` on unless the variant is deliberately meant to share the parent task's
translation.

**One task, one slot per table task list.** `tab_task` is keyed by `(tab_id, task_id)` — not by
variant. A table can only carry one `tab_task` row per task, so two variants of the same task
cannot both be added to the same table's plain task list at once. The per-variant choice of *which*
`task_variant_id` shows lives one level down, on `tab_variant_task_overview` — showing two variants
side by side on the same table means giving them separate **table variants**, each independently
selecting its own task variant via that overview entity, not two `tab_task` rows.

## Assigning table tasks

### By hand

Add a `tab_task` row picking the `task_id`, then configure its table-specific presentation:
`show_tab_task`, `icon`, `order_no`, `tab_task_grp_id` (to fold it into a task group on the action
bar), `screen_area_id`, `custom_display_type` (icon/text fallback chain — see the enum on
`tab_task`/`tab_task_grp`), `primary_action`, `refresh_after_execute`
(`none`/`row`/`subject`/`document`), grid double-click behaviour
(`grid_double_click`/`grid_double_click_col_id`), and `enable_tab_task_when_empty`. Then add
`tab_task_parmtr` rows for any parameter that should auto-fill from a column of the current row.

**`tab_task.icon` is a table-specific *override*, not the task's primary icon** — leave it unset to
inherit `task.icon_id`, and only set it when this table's context genuinely warrants a different icon
than the task shows everywhere else. **It's also verified upload-only**: unlike `task.icon_id`,
`tab_task` has no `icon_id` field at all — it's a plain file upload straight onto the row, not a pick
from the shared repository, so it can't be reused or consolidated via `task_update_icon_usage`. See
`thinkwise_sf_icons`.

**Set `enable_tab_task_when_empty=false`** for a task whose entire purpose is acting on one specific
selected row — e.g. a task bound only to launch a process flow via `grid_double_click`. It defaults to
`true`, but a task that just shows/filters detail for "the selected row" is meaningless with no row
selected, so leaving the default on makes it reachable in a state that can't do anything useful.

Use this when the assignment is genuinely one-off, or the target table only needs a subset of an
existing table's task list.

**When a new `tab_task_grp` (task group) is called for, propose these as its defaults while
confirming the plan** — per `thinkwise_sf_base`'s "Ask, don't default" convention,
this is what to put forward for sign-off, not something to apply silently unless the user corrects it:
- **`sub_menu = true`** — render the group as a dropdown rather than inline buttons.
- **`custom_display_type = icon_text_text_only_icon_only_overflow`** (value `0`) — "Icon + text",
  falling back to text-only, then icon-only, then overflow, as space runs out. Both fields default to
  `false`/unset on a plain add, so set them explicitly once confirmed rather than leaving the field
  default in place. The same `custom_display_type` default applies to a `tab_prefilter_grp` — see
  `thinkwise_sf_prefilters`.

### Bulk-copying an existing assignment

| Task | Bound to | Copies | Use when |
|---|---|---|---|
| `task_copy_task` | `task` | The whole task; optionally its table-task assignments (`copy_object_task`) and its functionality/template assignments (`copy_object_assignment`) | Duplicating a task already wired to several tables, wanting the clone wired the same way. |
| `task_copy_tab` | `tab` | A whole table's setup onto another table — refs, look-ups, GUI, reports, and (via `copy_object_task`) its full table-task list | A new table should start with the same task/report/reference lineup as an existing, structurally similar table. |

Bulk-copy then prune is usually faster than hand-assembling a large task list — but it copies
things you may not want, so treat it as a starting point on a structurally similar table, not a
shortcut on a dissimilar one. For a small, deliberate assignment, doing it by hand is just as fast
and leaves nothing to clean up.

## Renaming, copying, deleting

Go through the dedicated bound tasks rather than editing `task_id`/`task_variant_id` in place —
keys aren't renamable directly, the same immutable-key pattern as tables/columns elsewhere in the
model:

- `task_rename_task` (`from_task_id`, `to_task_id`) / `task_delete_task`
- `task_rename_task_variant` (`task_id`, `from_task_variant_id`, `to_task_variant_id`) /
  `task_delete_task_variant`
- `task_copy_task_variant` (`from_task_id`, `from_task_variant_id`, `to_task_variant_id`)
- `task_delete_task_ref` / `task_delete_task_conditional_layout`

## Control procedures for a task's own logic

For a `STORED_PROCEDURE`-typed task, the real logic is a control procedure exactly like any other
generated object — the **TASKS** code group, plus **DEFAULTS**/**LAYOUTS**/**BADGES** scoped to the
task wherever those concepts are enabled. Object naming carries straight over: `task_<task_id>` is
the task's own executable object; `default_<task_id>`, `layout_<task_id>`, `badge_<task_id>` are
its Default/Layout/Badge sub-objects. Follow
`thinkwise_sf_control_procedures` for the full sequence — in short, once the
`task`/`tab_task`/`task_parmtr` rows exist (Golden rule above):

1. Query `branch_rdbms_type` before writing a line of SQL.
2. Run **Generate code group** (`task_generate_code_grp`, bound to any `control_proc` in the TASKS
   group) to materialize the `task_<task_id>` placeholder — nothing to assign a template to exists
   before this.
3. Write the template and assign it (Static via the Assigning screen is the natural default for one
   task's own logic; SQL/dynamic only if the same template genuinely fans out across many tasks).
4. Queue actual generation with `task_add_job_to_generate_object_code` — the code-group step above
   only creates the placeholder, this is what actually produces `prog_object_generated_code`.
5. Confirm by re-reading the object (`generated_code_stale = false`) and reading the generated text
   itself to confirm the assigned template's own logic is really in it.

`FUNCTION`, `EXTERNAL_*`, and `ITP` tasks have no template to assign — their logic lives outside
the Software Factory's own code generation.

## Translation

Follow `thinkwise_sf_translations` for the general mechanics. Task-specific
points:

- A task's own label is a `transl_object` of the task's `type_of_object`, keyed by its bare
  `task_id` — confirm the live integer value rather than trusting a cached one (the enum spans
  ~150 model concepts and grows across platform versions).
- **Task parameters translate separately** — each `task_parmtr` is its own translation object,
  carrying only `transl` and `transl_form` (confirmed live: no grid/card-list/plural text, since a
  parameter never appears in a grid).
- **Confirm/Cancel buttons can have their own translation**, independent of the task's main label —
  gated by `confirm_button_has_alt_transl`/`cancel_button_has_alt_transl` on both `task` and
  `task_variant`. Leave these off unless a variant genuinely needs different button wording than
  the base task.
- `task_create_task_variant`'s `generate_transl_object` flag should stay on so the variant gets its
  own independent, editable label instead of silently inheriting the parent task's.
- `task_ref` is **not** independently translated — `ref_description` is a plain developer-facing
  description field, not user-facing text.
- **`tab_task_grp` (a task group's own label) is translatable too** — `tab_task_grp_description`
  auto-generates a bracket-placeholder `transl_object_transl` row on creation, translated the same way
  as any other object. Confirmed live `type_of_object = 16` for `tab_task_grp` — re-verify rather than
  trusting this across connectors/versions, per the usual caution on this enum.
- To find task text nobody has translated, look for the bracketed placeholder the platform
  auto-fills (`[task_id]`, `[task_parmtr_id]`), not a blank/null check.
- **Before calling a new task done, run the translation completeness gate from
  `thinkwise_sf_data_model`'s "Translating new objects" section** — a task's own label and
  every one of its parameters are separate translation objects (see above), and it's easy to translate
  the task and forget its parameters, or vice versa, without a final mechanical check.
