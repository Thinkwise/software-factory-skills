# Cube field placement, pivot axes, and chart settings

Loaded on demand from `thinkwise_sf_cubes`.

## Field placement in a view — `cube_view_field`

Places one `cube_field` into exactly one area of exactly one `cube_view`. Confirmed `cube_area` enum:

| Value | Meaning |
|---|---|
| `cube_area_filter` | Restricts the view without becoming an axis |
| `cube_area_category_row` | Primary drill path — put the broadest dimension first |
| `cube_area_series_column` | Secondary axis — keep cardinality low or the pivot gets very wide / the chart legend gets illegible |
| `cube_area_value` | The aggregated number(s) shown |
| `cube_area_menu` | A fifth value present in the schema alongside the four documented UI areas; its exact rendering isn't covered by current docs/community material — likely the "not yet placed on any axis" pool feeding the field picker. Verify in the SF UI on a live row before treating it as equivalent to one of the four areas above. |

**Setting the area**: `task_cube_view_field_area_drag_drop` is confirmed live to take **no
parameters** on either binding (`cube_view_field` or the mirror `cube_view_field_set_up`) — it exists
to back the SF's own visual drag-and-drop panel, where the target area is implied by which UI
drop-zone triggered it. Via an MCP connector, don't try to call this task — **just patch
`cube_view_field.cube_area` directly** with `stage_resource`/`patch_resource`/`commit_resource`; it's
a plain field, not a snapshot-gated one. **This field has also been seen silently dropping when set
together with other fields in one combined write** (the general "last field in a combined write can
drop" quirk — see `thinkwise_sf_data_model`) — after patching `cube_area`, re-read the row
back and confirm the value actually stuck. **Re-tested and fixed**: setting `cube_area`
*last* among the properties in one combined `stage_resource`/`patch_resource` call (after `order_no` and
any other field being changed alongside it) avoided the drop entirely — both fields held correctly with
no follow-up patch needed. Order the properties this way instead of isolating `cube_area` into its own
call.

Other confirmed fields: `order_no`/`abs_order_no` (field order within its area), `field_width`
(pixels), `sort_order` (`asc`/`desc`) + `sort_by_cube_field_id` (sort this category/series by
**another field's aggregated value** — e.g. sort customers by revenue rather than alphabetically —
distinct from simply sorting the axis's own display value), `show_top_x` + `type_of_show_top_x`
(`absolute`/`percentage`) + `show_other` (fold everything outside the Top X into an "Other" bucket —
strongly prefer enabling `show_other` whenever `show_top_x` is set, so users don't mistake a partial
ranking for the full total), `expand` (default expansion state — for a Year→Quarter→Month
hierarchy, expanding only the top level usually communicates the pattern better than expanding every
leaf).

### Default filter values — `cube_view_field_filter`

A repeatable child row per allowed/default value, keyed by `(cube_view_id, cube_field_id,
filter_value)` — only meaningful for a field placed in `cube_area_filter`. This is how a view's
default context (current company, recent years, completed-only transactions) gets modeled. Whatever
default filter you set here must remain **visible and understandable** to the user — a hidden
default filter that silently excludes canceled orders or old periods breaks reconciliation even when
the exclusion was intentional. Row-level security belongs in the subject/authorization layer, never
only in a cube view's default filter — a saved filter is a user convenience, not an access control.

### Extra totals — `cube_view_field_total`

Keyed by `(cube_field_id, summary_type)` — **a value field can carry more than one total row**, each
with its own `summary_display_type`/`no_of_decimals`/`order_no`. This is distinct from the cube
field's own base `summary_type` (used for each leaf cell): a total row can legitimately use a
*different* aggregation than the cell aggregation for a subtotal/grand-total presentation (e.g. an
average unit price at the leaf cell, but the total row instead shows a sum of the underlying
quantity via a second cube field, or the same value totaled with a different display type). Add a
total row deliberately per value, and treat a semi-additive or non-additive value's total with
extra scrutiny — a naive `sum` total row on a balance or a ratio field looks fine and is wrong.

### Conditional layouts on a cube view

`cube_view_field_conditional_layout` — a **cube-specific** conditional-layout family (not a row in
the generic `conditional_layout` entity the `thinkwise_sf_conditional_layouts` skill
covers). Confirmed fields: `condition_cube_field_id` (which field the condition evaluates),
`numeric_condition` (`equal_to`, `not_equal_to`, `greater_than[_or_equal_to]`,
`smaller_than[_or_equal_to]`, `between`/`not_between`, `is_empty`/`is_not_empty`), `value`/
`until_value`, and four independent apply-to flags — `apply_to_cell`, `apply_to_total_cell`,
`apply_to_custom_total_cell`, `apply_to_grand_total_cell` — plus the same
color/font/bold/italic/underline/strikethrough/font_size formatting fields as the generic mechanism,
each split into light/dark theme variants. **Test each apply-to flag independently**: a condition
that's meaningful on a leaf cell (e.g. "utilization above 95%") is frequently misleading when the
same rule also colors a grand total. This mechanism applies only to modeled standard cube views, not
ad hoc views end users build for themselves via the Cube panel.

### Chart extras — constant lines and custom series colors

- `cube_view_constant_line` — a fixed threshold/target line drawn on a chart's `x_axis` or `y_axis`
  at a given `value`, with `color`, `thickness`, `dash_style`, optional title
  (`show_title`/`title_color`/`title_font_id`/`title_alignment`), `show_in_front_or_behind` the data,
  and `show_in_legend`. Use for SLA thresholds, budget targets, or capacity limits overlaid on a
  trend.
- `chart_legend_color` — overrides the palette's automatic color for one specific value member
  (`cube_field_id` + `color_light`/`color_dark`), letting e.g. a fixed red always represent "Returns"
  regardless of palette rotation.

For making pivot values directly editable (preconditions, and the self-referencing-hierarchy
structural trap), read `references/editable_values.md` before enabling this.
