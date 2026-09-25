# References (foreign keys) and the look-up display column

Loaded on demand from `thinkwise_sf_data_model`.

## References (foreign keys)

**Model the reference as part of designing the table (or view) — not as an afterthought added once screens are already being built.** Whenever a column's value is meant to match another table's primary key, that relationship must be represented by an actual `ref` row (plus one `ref_col` row per join column). Two columns that merely happen to hold matching values are not a reference to the platform: without a modeled `ref`, there is no look-up combo, no detail grid, no auto-derived OData/Indicium navigation property, and (when `check_ref` is on) no database-level integrity check. Add the `ref`/`ref_col` at the same time you add the FK-shaped column, before moving on to screens, tasks, or reports that would want to use it.

### Look-up vs. detail: what one reference gives you

A single reference always has two possible presentations, toggled independently via `show_look_up` / `show_detail` on the `ref` row:
- **Look-up** — a field/combo on one table's screen letting a user search and select a single related row on the other table. This belongs on the table that actually holds the FK-shaped value — it is picking "the one" row it relates to.
- **Detail** — a grid/tab on one table's screen listing every row on the other table whose key matches. This belongs on the table being pointed at — it has "many" related rows to show.

**Direction — one unified rule, no exceptions:** `source_tab_id` = the table whose primary key is being referenced (the "parent"); `target_tab_id` = the table *or view* holding the FK-shaped column that points at it (the "child"). This is identical whether the child is a normal table or a view — there is no separate "view case" that reverses anything; a view with an FK-shaped column follows exactly the same direction as any other child table. Mechanically, `ref_col.source_col_id` must be a column that is part of `source_tab_id`'s own primary key, while `ref_col.target_col_id` is simply the FK-shaped column on `target_tab_id` holding the matching value — that's the one fact to check if direction is ever in doubt (see verification note below). Look-up goes on the target (the FK-holder, since it's picking "the one" parent row it relates to); detail goes on the source (the PK-owner, since it has "many" children pointing at it).

Example — `absence.employee_id` → `employee.employee_id` (a normal table-to-table FK):
```
ref:      source_tab_id = employee,   target_tab_id = absence
ref_col:  source_col_id = employee_id,   target_col_id = employee_id
```
Result: `absence`'s screen shows a look-up to pick the employee; `employee`'s screen shows a detail grid of that employee's absences.

Example — a view `employee_absence_overview` with a column `employee_id` that should look up `employee`:
```
ref:      source_tab_id = employee,   target_tab_id = employee_absence_overview,   check_ref = false,   show_detail = false
ref_col:  source_col_id = employee_id,   target_col_id = employee_id
```
Same rule, same direction as the table-to-table example above — `check_ref = false` here is because a view carries no physical FK constraint (not because the direction itself changes), and `show_detail = false` is typical since a detail grid on the real table listing view rows is rarely useful.

Confirmed against real production references in a live model (`ref_company_dev_event_company`, `ref_person_dev_event_company_account_manager`, both against a view target).

**When a table ends up with more than one detail tab** (multiple references showing `show_detail =
true` against the same parent), give each a distinct order number — two detail tabs left at the same
position is flagged by a Software Factory validation and produces an ambiguous tab order in the UI.

**If direction is ever in doubt**, a wrong direction is accepted at write time with no error. It
surfaces later as a validation resembling *"foreign key reference with integrity does not contain the
full primary key of the source table"* — which always means `source`/`target` are swapped. Check the
model's own validation output after creating a `ref` rather than re-deriving the rule from memory.

**Disambiguating multiple references to the same table pair:** if a table (or view) has two or more FK-shaped columns pointing at the same target, the auto-derived `ref_id` (`ref_<source>_<target>`) collides between them. Set `ref_add` on each (e.g. `"most_recent"` / `"upcoming"`) — it appends a suffix (`ref_<source>_<target>_<ref_add>`) so each gets a distinct primary key instead of silently overwriting the first.

**Self-referencing foreign keys can't cascade on SQL Server.** A reference where `source_tab_id` equals `target_tab_id` (a table's own parent-child hierarchy, e.g. a `parent_id` pointing back at the same table) fails to deploy with `on_delete`/`on_update` set to anything other than `no_action` — SQL Server rejects the constraint outright at deploy time ("Introducing FOREIGN KEY constraint ... may cause cycles or multiple cascade paths"), even though the identical `on_delete = set_null`/`cascade` value deploys fine on an ordinary two-table reference. Model a self-referencing FK with `on_delete = no_action` and `on_update = no_action`, and if reparenting/promote-to-top-level-on-delete behavior is actually wanted, implement it in a control procedure or at the application level rather than relying on the database constraint to do it. Verify the same restriction independently before assuming it holds on a non-SQL-Server target dialect.

## Look-up display column

Every table should have a deliberately chosen `tab.look_up_display_col_id` — the column (or
calculated column) used to represent one of its rows wherever the table is looked up from elsewhere:
combo/auto-complete fields, look-up popups, detail headers. Leaving it unset or pointing at the
wrong column means users see a raw ID or a meaningless field the moment the table is referenced from
another screen. (`tab.tree_display_col_id` is the equivalent for tree views, when used.)

Two patterns, both confirmed live against a real application (`INSIGHTS`):

- **Point it at an existing descriptive column**, when one already identifies the row well:
  `customer` → `name`, `employee` → `name`, `project` → `description`, `task`/`meeting`/`email` →
  `subject`, `sales_invoice` → `sales_invoice_description`.
- **Add a dedicated calculated column** (see "Calculated columns" above) when no single column does
  the job:
  - **Translation fallback**, for a table with a `_translated` companion table — resolve the row's
    name in the session's current language, falling back to the base-language column. Confirmed
    live on `activity`, `country`, `document_type`, `employee_function`, `meeting_type`.
  - **Composite/concatenation**, when the row's identity is really a combination of several related
    fields — e.g. a real live model has `hour.lookup` = `project.description + ' | ' + sub_project.name`;
    `booking_hour.lookup` = employee name + the ISO week number; `declaration.lookup` = project +
    employee + description + date, joined together.

**Never name this column the generic `lookup`, despite that older live examples above use exactly
that** — it's the same meta-information-free naming this document rules out everywhere else (see
"General naming rules"). Give it a name that says what it actually computes: `full_name` for a
first+last name concatenation, `full_address` for an address composite, `display_label` for a
translation fallback, and so on. A calculated column built this way is almost always an
`expression`-type calculated column, not a same-row `calculated_column` — it exists specifically to
reach into other tables. Keep it narrow (see "Calculated columns" → Performance above) since it runs
once per visible row everywhere the table is looked up from, which can be a lot of places.

**The chosen display column (or calculated column) should return a distinct value per row.** A
look-up display column that returns duplicate values across rows is flagged by a Software Factory
validation, since it leaves a user unable to tell two rows apart in a combo/auto-complete. If no
single existing column is reliably unique, prefer the composite/concatenation calculated-column
pattern above over accepting a display column with likely duplicates.

**Decide this at the same time as the rest of the table's design** — before the column-creation
pass, the same as grouping/sort/search/filter/aggregation above: know whether an existing column
will serve, or whether a dedicated calculated column is needed, what it should compute, and what to
name it, so
`look_up_display_col_id` (and the calculated column itself, if needed) get set in the same
create-time writes instead of a follow-up patch pass.
