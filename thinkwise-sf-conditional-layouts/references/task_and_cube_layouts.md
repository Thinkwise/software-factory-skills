# Task-level and cube-level conditional layout

Loaded on demand from `thinkwise_sf_conditional_layouts`.

## Task-level `task_conditional_layout` — field reference

Keyed by `(model_id, branch_id, task_id, conditional_layout_id)`. Tasks and reports have no grid, so
their conditional layouts style **parameters on the input form** instead of a column: `col_id` is
replaced by `task_parmtr_id`, and there is no `apply_to_*` flag family (a task form has only the one
surface). Otherwise the same styling fields as the table family
(`background_color_light`/`_dark`, `font_color_light`/`_dark`, `bold`/`italic`/`underline`/
`strikethrough`, `font_size`, legacy `background_color`/`font_id`).

`task_conditional_layout_condition` mirrors `conditional_layout_condition` with parameter references in
place of column references: `task_parmtr_id` (condition's own evaluated parameter), `value_task_parmtr_id`
/ `until_value_task_parmtr_id` (for `type_of_value = column`-equivalent comparisons against another
parameter). Same 18-value `condition` enum, same `constant`/`column`-style `type_of_value` enum.

**`task_variant_task_conditional_layout`** — keyed by `(..., task_id, task_variant_id,
conditional_layout_id)`, exposing only `show_conditional_layout`: a per-variant on/off override of a
layout defined at the base task, the task equivalent of `tab_variant_prefilter_overview`'s per-variant
state override. Tables have **no equivalent per-variant override** for `conditional_layout` — verified
absent (see "Known gap" below) — table conditional layouts are table-wide only.

Good task/report use cases (styling, not validation, which must still be added separately): a required
parameter needing attention, a selected quantity exceeding available stock, a chosen date outside the
planning window, a destructive option that's been selected, a missing external-system identifier.

Bound tasks mirror the table family: `task_copy_task_conditional_layout`
(`from_task_id`/`from_conditional_layout_id`/`to_task_id`/`to_conditional_layout_id`),
`task_delete_task_conditional_layout`, `task_rename_task_conditional_layout`, `task_show_history`,
`task_unlink_generated_object`.

## Cube-level `cube_view_field_conditional_layout` — field reference

Keyed by `(model_id, branch_id, cube_id, cube_view_id, cube_field_id, conditional_layout_id)`. Cube-view
conditional layouts are a distinct, flat sub-family (condition inline, no child entity) with their own
gradient/multi-surface fields — see
`references/cube_level_conditional_layout.md` for the full verified field reference before creating or
inspecting one of these rows.
