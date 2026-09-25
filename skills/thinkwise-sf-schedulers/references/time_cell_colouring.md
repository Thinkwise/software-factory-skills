# Scheduler time-cell colouring

Loaded on demand from `thinkwise_sf_schedulers`.

## `scheduler_view_conditional_layout` / `_condition` / `_tag` — time-cell colouring

Keyed by `(model_id, branch_id, tab_id, scheduler_view_id, cell_color_id[, cell_color_no |
tag_id])`. Distinct from the ordinary `conditional_layout` entity used for activities/resources below —
this family colours the **time cells** of the grid itself.

`scheduler_view_conditional_layout` (the "cell colour"):

| Column | Purpose |
|---|---|
| `cell_color_description` | Name |
| `background_color_light` / `background_color_dark` (`Edm.Int32`) | Per-theme background colour |

`scheduler_view_conditional_layout_condition`:

| Column | Purpose |
|---|---|
| `type_of_time_scale` (enum) | `col` = 0 · `time_scale` = 1 · `date` = 2 |
| `time_scale` (enum, only when `type_of_time_scale = time_scale`) | `year`=0 · `quarter`=1 · `month`=2 · `week`=3 · `day`=4 · `hour`=5 · `minute`=6 |
| `col_id` (only when `type_of_time_scale = col`) | Column evaluated against the **resource** record |
| `condition` (enum, 18 operators) | `equal_to`=0 · `not_equal_to`=1 · `greater_than`=2 · `smaller_than`=3 · `greater_than_or_equal_to`=4 · `smaller_than_or_equal_to`=5 · `between`=6 · `starts_with`=7 · `contains`=8 · `does_not_contain`=9 · `is_empty`=10 · `is_not_empty`=11 · `does_not_start_with`=12 · `not_between`=13 · `ends_with`=14 · `does_not_end_with`=15 · `in`=16 · `not_in`=17 |
| `type_of_value` / `until_type_of_value` (enum) | `constant`=0 · `column`=1 |
| `value` / `until_value` / `value_col_id` / `until_value_col_id` | Constant or column-sourced comparison value(s) |
| `date_value` / `until_date_value` (datetimeoffset) | Exact UTC range, only for `type_of_time_scale = date` |

**When staging a write**, expect `type_of_time_scale`/`condition`/`type_of_value` to require the raw
numeric value rather than the string key shown above (e.g. `2` for `date`, not the string `"date"`) —
consistent with the general enum-key-rejection quirk noted in `thinkwise_sf_data_model`'s
API-write-quirks reference.

`scheduler_view_conditional_layout_tag`: a plain `(tag_id, value)` pair per cell colour, same tagging
mechanism used elsewhere in the model.

### Worked pattern: colouring cells for a varying, per-period resource state

The field reference above gives the raw enum shape but not the technique for the single most common
real use of this family: showing a state that comes and goes over time for a given resource — a
machine's planned downtime, an employee's vacation/sick leave, a truck's maintenance window — as a
coloured block on the time cells, distinct from any activity bar.

, on a real scheduler subject (`GREEN_FLOW`'s `Production_Planning_Tab_Task_POC`,
modeling resource "work time" windows): the subject's `UNION`-based query gets **one extra row per
state-period**, alongside its resource and activity rows — each such row shares the resource's own
grouping key (so it lands under the right resource) but leaves every activity-rendering column
(title, tooltip, and the start/end date columns `scheduler.activity_start_date_col_id`/
`activity_end_date_col_id` point at) `null`, so it never draws as an activity bar. It carries only its
own pair of period-start/period-end date columns and a state/type column.

For **each distinct colour/state**, model one `scheduler_view_conditional_layout` row with **two
AND'ed conditions**:
1. A `date`-type condition (`type_of_time_scale = date`) testing whether the cell's date falls
   `between` that row's own two period columns, with `type_of_value = column` on both bounds
   (`value_col_id`/`until_value_col_id` pointing at the period-start/period-end columns) — not a fixed
   `date_value`. This is what makes the colouring track each row's own dates instead of a constant range.
2. A `col`-type condition (`type_of_time_scale = col`) testing that same row's state/type column
   `equal_to` a constant identifying this specific colour.

Both conditions target columns on the **same underlying subject row** (the unioned period row), not
necessarily the resource's own header row — "column evaluated against the resource record" in the
field reference above means whichever row of the subject is being evaluated for that resource, which
for this pattern is the unioned period row.

Repeat the pair for every distinct state (one `scheduler_view_conditional_layout` per colour), and for
every `scheduler_view` that should show the colouring — a layout only applies to the view it's keyed
under.

### "Work time" — a resource-availability/capacity pattern, not a built-in mechanism

The legacy Windows GUI Resource Scheduler extender had a literal, first-class **Worktime** subject —
a separate table saying, per resource, which hours/days it's available (see "Migrating off the legacy
Resource/Task/Worktime model" above). **The Universal Scheduler has no equivalent built-in entity** —
the business need still comes up constantly, but has to be reconstructed with the plain data-modeling
and conditional-layout tools available, using exactly the union-per-period pattern above.

**Verified live shape**: a dedicated child table, keyed by its own identity, with a resource FK, a
period-start date column, a period-end date column, and a colour/state column — wired into the
scheduler subject exactly per the worked pattern above: unioned in as extra non-activity rows sharing
the resource's own grouping key, then coloured with one `scheduler_view_conditional_layout` per
distinct colour value that row can carry.

**Common uses of the same mechanism, different business meaning:**
- **Standard business hours / shift patterns per resource** — tint a resource's own working hours
  distinctly from its off-hours, when the Scheduler-wide `min_displayed_time`/`max_displayed_time`/
  `hide_*day` settings (identical for every resource) aren't granular enough for per-resource
  variation.
- **Planned downtime / maintenance windows** — for equipment, room, or vehicle resources: a block
  over the period a machine is offline for servicing.
- **Employee absence, vacation, sick leave** — the same technique applied to people instead of
  equipment.
- **Part-time / reduced-capacity periods** — a resource only available some days a week, or at
  reduced hours during a specific date range (e.g. a seasonal contract).
- **Public holidays** — a period that colours the same day across every resource at once, rather than
  one resource's own schedule.

**Design choice: a raw colour column vs. a named-state enum domain.** Storing a literal colour value
directly on each period row keeps the second condition a simple equality check against that colour
code, but a model with distinct named states (`vacation`/`sick_leave`/`maintenance`/`holiday`) is
usually clearer with a proper enum domain instead (see `thinkwise_sf_data_model`'s "Domain
elements" section) — one value per state, with the meaning explicit in the data rather than encoded as
a colour that only means something by convention.

**Critical gotcha — match the condition to the enabled timescales.** A condition on a timescale the
view doesn't include is always true. A view enabling only Year/Month/Day with an `hour > 8` condition
colours *every* cell, because there is no hour timescale to evaluate against — the condition must
also constrain at least the lowest timescale actually present.

**Known gap** — colouring specifically Saturday/Sunday via a time-scale condition on day-of-week isn't
directly supported; Thinkwise's stated workaround is custom CSS, alongside the coarser
`hide_saturday`/`hide_sunday` flags on `scheduler_view` as a partial substitute.

this family is genuinely optional — a scheduler can rely entirely on activity-level HTML
styling (below) instead, and `PROJECT_MANAGER`'s scheduler did exactly that across all three of its
views for a long time. It later gained `scheduler_view_conditional_layout` rows specifically to colour
employee absence/vacation periods (see the worked pattern above) — don't assume every real scheduler
uses this family, but don't assume none ever will either.

Bound tasks (on `scheduler_view_conditional_layout`): `task_copy_scheduler_view_conditional_layout`,
`task_delete_scheduler_view_conditional_layout`, `task_rename_scheduler_view_conditional_layout`,
`task_show_history`, `task_unlink_generated_object`.
