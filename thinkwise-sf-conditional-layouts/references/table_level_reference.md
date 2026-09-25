# Table-level conditional_layout, conditions, and tags — field reference

Loaded on demand from `thinkwise_sf_conditional_layouts`.

## Table-level `conditional_layout` — field reference

Keyed by `(model_id, branch_id, tab_id, conditional_layout_id)`.

| Field | Notes |
|---|---|
| `conditional_layout_description` | Translatable label |
| `show_conditional_layout` | **Master on/off switch**: several real rows carry a fully-configured colour/condition with `show_conditional_layout = false`. A layout can be completely modeled and left dormant; don't assume every row you find is actually active. |
| `col_id` | Target column. **Blank = whole row** (see "Row vs. column targeting" below) |
| `apply_to_grid` / `apply_to_form` / `apply_to_edit` / `apply_to_scheduler_resource` | Independent boolean flags — **not** a single enum. (A synthetic example with one combined `apply_conditional_layout` field is not the real shape; ignore any doc that implies a single field here.) |
| `font_id` | Legacy Windows-GUI-only named font — verified as a thin `(font_id, font_info)` lookup, superseded by `font_size` (L/XL) for Universal UI. Leave unset for new Universal UI work. |
| `background_color` | Legacy single Windows-GUI-only background colour (`Edm.Int32`). No `font_color` legacy equivalent exists — only background has this legacy/theme-pair asymmetry. |
| `background_color_light` / `background_color_dark` | **Universal UI** per-theme background colour — set both |
| `font_color_light` / `font_color_dark` | **Universal UI** per-theme font colour — set both |
| `bold` / `italic` / `underline` / `strikethrough` | Booleans |
| `font_size` | Enum: `L` = `0`, `XL` = `1`. Absent = default size |
| `generated_by_control_proc_id` | Set only if a control procedure owns/regenerates this row |

**No `order_no`/priority field exists on `conditional_layout`** — verified against the full live property
list. Unlike `tab_prefilter` (which has `order_no`), there is no administrator-settable evaluation
priority for overlapping table conditional layouts. This reinforces, with a concrete mechanism, why the
"make conditions mutually exclusive" guidance below matters more here than it might first appear: there
is no priority number to fall back on if two layouts both match the same row. (Scheduler time-cell
layouts are the exception — `scheduler_view_conditional_layout` is keyed with an explicit
`cell_color_no`; that family also documents "first match wins" — see the scheduler skill.)

Bound tasks: `task_copy_conditional_layout` (`from_tab_id`/`from_conditional_layout_id`/
`to_tab_id`/`to_conditional_layout_id`), `task_delete_conditional_layout`,
`task_rename_conditional_layout`, `task_show_history`, `task_unlink_generated_object`.

**Creating this row, verified**: a plain/unscoped add of a new `conditional_layout` record is rejected
as a weak/dependent-entity error, with candidate parents `tab` or `model_settings_modeler` — the same
shape of rejection documented for `scheduler` in `thinkwise_sf_schedulers`. Add
it as a detail of its owning `tab` record (supplying `model_id`/`branch_id`/`tab_id` as the parent key)
rather than as a standalone create.

### `conditional_layout_condition` — field reference

Keyed by `(model_id, branch_id, tab_id, conditional_layout_id, conditional_layout_condition_no)`. A
layout's conditions are AND-ed together; a layout with zero condition rows is always applied
(`show_conditional_layout` permitting). `conditional_layout_condition_no` is typically presented as a
non-editable/system-assigned field when adding a new condition through a staged create flow — the
platform assigns its actual value on commit rather than the caller supplying one; don't try to compute
or guess a sequential number for it.

| Field | Notes |
|---|---|
| `col_id` | The column this **condition** evaluates — independent of the parent's own `col_id` (the column that gets *styled*). `booking_hour.friday_total_hours_greater_than_8` styles `hours_friday` but conditions on `total_hours_friday` — the coloured column and the evaluated column are routinely different. |
| `condition` | 18-value enum (verified, identical set to `tab_prefilter`'s filter condition) — see table below |
| `type_of_value` | `constant` = `0` · `column` = `1` |
| `value` | Constant literal, when `type_of_value = constant` |
| `value_col_id` | Comparison column, when `type_of_value = column` |
| `until_type_of_value` / `until_value` / `until_value_col_id` | Same constant/column choice, for the second bound of `between`/`not_between` |

The `condition` field is an integer enum with 18 operators (`equal_to` = 0 through `not_in` = 17,
covering the comparison, range, string, empty and set families). **Pull the exact names and integers
from `get_entity_definition` on the condition entity** rather than relying on any list here — they
come back in full, with values, from the call you already make before writing.

**Not independently verified**: the exact serialization `value` needs for `in`/`not_in` (e.g. a
delimited list) — test against a live add before relying on a specific separator.

Real verified example (`booking_hour.friday_total_hours_greater_than_8`): one condition row,
`col_id = total_hours_friday`, `condition = 2` (greater_than), `type_of_value = 0` (constant),
`value = "8"`. A believable corrected shape of the doc's illustrative JSON:

```json
{
  "tab_id": "purchase_order",
  "conditional_layout_id": "order_status_completed",
  "show_conditional_layout": true,
  "col_id": "order_status",
  "apply_to_grid": true,
  "apply_to_form": true,
  "apply_to_edit": true,
  "apply_to_scheduler_resource": false,
  "background_color_light": -4684277,
  "background_color_dark": -4684277,
  "bold": false,
  "italic": false
}
```
```json
{
  "tab_id": "purchase_order",
  "conditional_layout_id": "order_status_completed",
  "conditional_layout_condition_no": 12345,
  "col_id": "order_status",
  "condition": 0,
  "type_of_value": 0,
  "value": "COMPLETED"
}
```
The numeric colour/enum values represent platform enumerations — maintain these through the Software
Factory's own named settings rather than hand-editing the integers.

### `conditional_layout_tag`

Plain `(tag_id, value)` pairs per layout — the same generic tagging mechanism used elsewhere in the
model (arbitrary metadata, not styling). Bound tasks: `task_show_history`,
`task_unlink_generated_object` only (tags are added/edited directly, not copy/rename/deleted as a unit).
