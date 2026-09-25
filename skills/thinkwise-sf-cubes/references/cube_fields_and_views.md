# Cube fields and cube views — dimensions, values, intervals, hierarchies

Loaded on demand from `thinkwise_sf_cubes`.

## Cube fields — dimensions and values

Confirmed schema (`cube_field`):

| Field | Purpose |
|---|---|
| `cube_field_type` | `dimension` or `measure` (="Value" — see above) |
| `col_id` | Source column on the underlying table |
| `summary_type` | Aggregation: `average`, `count`, `min`, `max`, `stddev`, `stddevp`, `sum`, `var`, `varp`, `formula`, `sql_expression` — only meaningful for a value |
| `summary_display_type` | How the aggregated number is shown: `default`, `percentage_of_column`, `percentage_of_row`, `percentage_of_variation`, `abs_variation` |
| `no_of_decimals` | Display precision — set by business meaning, not raw DB scale |
| `editable` | Whether this value can become an editable pivot cell (see "Editable values" — several other preconditions also apply) |
| `grp_interval` + `type_of_grp_interval` | Enables and selects an interval/bucketing for a dimension: `alphabetical`, `numeric`, `date`, `date_year`, `date_quarter`, `date_month`, `date_week_of_year`, `date_week_of_month`, `date_day_of_year`, `date_day_of_month`, `date_day_of_week`, `year_age`, `month_age`, `week_age`, `day_age` |
| `grp_interval_numeric_range` | The bucket width, for `numeric` intervals |
| `cube_field_grp_id` | **Hierarchy parent** — see below |

### Intervals

Use `type_of_grp_interval` to reduce cardinality on a raw date/number into something users can
actually scan: order date → `date_year`/`date_quarter`/`date_month`; lead time → `numeric` buckets
via `grp_interval_numeric_range`. Per the research, day-of-week numbering starts at 1 = Sunday —
confirm this matches user expectations before shipping a week-based view, and take particular care
with fiscal calendars, week numbering, and daylight-saving boundaries.

### Hierarchies — `cube_field_grp_id`

Confirmed live: `cube_field_grp_id` is a **self-referencing lookup to another `cube_field` on the
same cube**. To nest "Product" under "Product group," set the **Product** field's own
`cube_field_grp_id` to the **Product group** field's `cube_field_id` — the child row points at its
parent, the same directional pattern as a normal FK column, not the inverted pattern variants use for
tree hierarchies. Once grouped this way, the child dimension is no longer independently offered
outside its parent's hierarchy — group dimensions only when every child genuinely has one meaningful
parent throughout the analyzed period; don't group two fields together merely because they're usually
shown side by side.

**`cube_field_grp_id` alone does not make the hierarchy appear in a pivot.** Verified live: wiring the
parent-child chain via `cube_field_grp_id` and placing only the leaf field in `cube_area_category_row`
produced a flat list with no nesting at all — every ancestor level was invisible. The fix: place
**every level of the hierarchy**, not just the leaf, as its own `cube_view_field` row in the same
area, in ancestor-to-leaf order (outermost first). `cube_field_grp_id` establishes the levels'
parent-child *identity* (and is what makes a grouped child stop being independently offered in the
field picker) — it does not by itself drive nested-row rendering from a single placement. Set
`expand = true` on the outermost level's `cube_view_field` row so the tree opens one level deep by
default rather than fully collapsed.

### Calculated fields — `cube_field_query`

For `summary_type = sql_expression` (the current, non-deprecated mechanism — `formula` is the older
Windows-era equivalent), the actual expression lives in a **separate per-RDBMS row**:
`cube_field_query`, keyed by `(cube_id, cube_field_id, rdbms_type)` with a single `formula` text
field. This is how ratios and margins get computed **after** aggregation, referencing sibling cube
fields through the mandatory alias `t1`:

```sql
(t1.revenue - t1.cost) / NULLIF(t1.revenue, 0)
```

Write one `cube_field_query` row per RDBMS your branch targets (`sqlserver`, `oracle`, `postgresql`,
`iseries`). This is the correct way to build gross margin, average selling price (revenue/units),
utilization, completion percentage, and variance — always guard division by zero and null
propagation, and never average pre-computed row-level ratios when you can recompute them from
aggregated numerator/denominator instead.

## Cube views

`cube_view` is one full pivot/chart configuration. Confirmed fields, grouped by concern:

**Identity & visibility**: `cube_view_description`, `show_cube_view`, `cube_view_grp_id` +
`order_no`/`abs_order_no`, `cube_view_icon_id`, `screen_area_id`, `custom_display_type` (the same
icon/text/overflow-fallback enum used by menu items and tasks — `icon_text_*`, `text_only_*`,
`icon_only_overflow`, `overflow`, or `hidden`). Set `cube_view_icon_id` to a suitable icon as part of
creating the view, per `thinkwise_sf_icons` — don't leave it unset by default.

**Default presentation**: `default_cube_view_type` — `none`, `pivot_table`, or `chart`.

**Totals** (pivot): `show_col_grand_total`/`show_row_grand_total` (an extra column/row presenting
the opposite axis's grand total), `show_col_total`/`show_row_total` (subtotals), `total_position` —
`near` or `far`. Show totals only where they're mathematically meaningful — a semi-additive or
non-additive value's grand total can be actively misleading.

**Drill-down**: `drill_down_grid` — double-clicking a pivot cell opens the underlying records,
still honoring the view's filters. Essential for trust in a number, but the underlying detail must
still be covered by the subject's own row-level authorization — drill-down is not a security
boundary by itself.

**Chart settings**: `chart_type` (a large enum — 2D/3D area/bar/line/pie/doughnut/funnel/bubble/
radar/gantt/candlestick and stacked/full-stacked/side-by-side variants of most of them),
`chart_palette_id`, `chart_rotated`, `show_labels` + `label_position_bar` (`center`/`top`) +
`label_position_pie` (`inside`/`outside`/`two_columns`), `show_percentage`, `transparency` (0–100 in
steps of 10), `show_legend` + `legend_alignment_horizontal`/`legend_alignment_vertical` +
`legend_direction` + `legend_max_horizontal_percentage`/`legend_max_vertical_percentage`. Universal
maps every 3D type to its 2D equivalent for rendering and folds a few specialized/unsupported types
down to columns — design for the supported Universal behavior, since 3D rarely helps comparison
anyway.

`task_copy_cube_view`/`task_rename_cube_view`/`task_renumber_cube_view`/`task_delete_cube_view` —
same create/rename/renumber/delete family as every other ordered child object in the model.
`task_cube_view_mark_new_object_approved`/`_disapproved` — the standard new-object review workflow
(also present on `cube_field`).

### View groups — `cube_view_grp`

Groups views into a labeled submenu of the cube-view bar once there are enough views that a flat bar
becomes hard to scan (`cube_view_grp_description`, `sub_menu` flag, `icon_id`, `custom_display_type`,
`order_no`). Group by question or audience (Sales / Margin / Volume / Operations / Quality), not by
creation order. Set `icon_id` to a suitable icon representing the shared question/audience, per
`thinkwise_sf_icons`.
