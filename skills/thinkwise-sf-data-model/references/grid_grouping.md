# Grid row grouping and aggregation

Loaded on demand from `thinkwise_sf_data_model`.

Distinct from the grid *column* header grouping in "Form & grid groups" above
(`grid_field_in_next_grp`/`grid_next_grp_label`, which visually bands grid *columns* under a shared
header) — this covers grouping grid *rows* into a collapsible tree by one or more column values,
plus per-column footer totals. Verified live against real application models (`INSIGHTS`/
`INSIGHTS_DEMO`, a time-tracking/invoicing app) as well as the Software Factory's own meta-model.

**Mechanism**:
- Table-level (`tab`): `allow_grp` (bool) turns the feature on for the table's grid at all;
  `grp_box_visibility` (`never`/`when_grouped`/`always`) controls whether the drag-to-group drop
  area is shown to end users; `grp_grid_default_expanded` (bool) + `grp_grid_default_expanded_level`
  (byte) control whether the default grouping starts expanded, and how many levels deep.
- Column-level (`col`): `grp_until` (bool) — flip it on the column(s), in grid display order, that
  should form the default group-by hierarchy. Every column from the first up through the last one
  flagged `grp_until=true` becomes a grouping level, in that order (one flag = a single-level default
  group-by on that column; flag more than one, in order, for a multi-level nested group).
- Aggregation (`col`): `show_aggregation_in_grid` (bool) + `aggregation_summary_type` (enum: `sum`,
  `count`, `average`, `min`, `max`, `stddev`, `stddevp`, `var`, `varp`) puts a per-column summary in
  the grid's footer — and in each group's own footer row too, when grouping is active on the same
  grid.

### When to use grouping

Real usage clusters into two shapes:
- **Worklist/overview/junction-style grids** — many flat rows that are more scannable collapsed under
  a categorical owner/type dimension. Confirmed live: `validation_msg_assignment_overview` groups by
  `assigned_to_developer_id` (validation issues collapse per developer); `deployment_module_role_overview`
  groups by `role_grp_id` (permissions collapse per role group). `grp_box_visibility` is `never` on
  nearly every one of these in the reference model — the grouping is a fixed, developer-chosen
  default the user isn't expected to rearrange, not an open-ended ad hoc feature.
- **Genuinely ad hoc, user-driven grouping** — rarer; set `grp_box_visibility` to `when_grouped` or
  `always` only when end users should be able to drag arbitrary columns into their own grouping, not
  just view a fixed default.

Detail/transactional grids reached from a parent's tab (e.g. `hour`, `booking_hour`, `sub_project` in
the reference model) typically leave `allow_grp=false` entirely — they're already scoped to one
parent row, so an in-grid group-by adds nothing.

**When it's not obvious whether a table's grid should default-group by something, ask the user**
rather than picking a column — like default sort, this is a judgment call about how the business
data is actually consumed, not a mechanical rule.

### When to use aggregation

Two distinct, real patterns, independent of whether grouping is also used:
- **`sum` on genuine numeric measure columns** — money amounts, hours, quantities, durations (e.g.
  `amount_incl_vat`, `number_of_hours`, `hours_booked`, `function_points`). Gives a subtotal per
  group and a grand total in the grid footer. Used with or without grouping — `hour`/`booking_hour`/
  `sub_project` show grand-total sums with no grouping at all, since they're already scoped under one
  parent.
- **`count` on any already-visible, always-populated column** (very often the primary key, or a
  status/icon column already on the grid) purely to show a row count per group and overall —
  confirmed live on columns like `col_id`, `test_scenario_id`, `unit_test_id`, `change_log_status`,
  `icon`. This is the cheap way to get an "N records" indicator without adding a dedicated column
  just to count rows — the column chosen for `count` doesn't need to be meaningful in itself.
- `average`/`min`/`max`/`stddev`/`stddevp`/`var`/`varp` exist but are rare in practice — reserve them
  for grids genuinely doing statistical/range analysis, not typical business data.

**When it's unclear whether a numeric column should be summed (or which column should carry a
`count`), ask the user** — same reasoning as grouping and default sort.

### Decide grouping and aggregation before creating any columns

Same rule as grouping, sort, search, and filter above: work out which column(s) (if any) get
`grp_until`, and which column(s) (if any) get `show_aggregation_in_grid`/`aggregation_summary_type`,
as part of the same upfront design pass — before the first create call for the table's columns — and
set the table-wide flags (`allow_grp`, `grp_box_visibility`, `grp_grid_default_expanded[_level]`) at
the same time the table itself is created. Set each column's `grp_until`/aggregation fields in the
same write that creates the column, avoiding a second patch pass once the columns already exist. The
only things worth pausing for user confirmation are which column(s) should drive the default
grouping and which numeric column(s) should be summed — exactly as with default sort.

