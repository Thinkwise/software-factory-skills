# Context

## What it does and when it fires

A Context determines, from the values in the current record, which tasks, reports and
detail tabs are available, and which detail tab is active. The Software Factory calls it
automatically:

- when another record is selected;
- in edit mode, as soon as a field the user modified is left.

Note: a Context is not re-triggered when the user merely switches detail tabs; it runs on
record selection and refresh.

---

## Hard rules

- **Stateless.** Set an availability output only when it must differ from the modelled
  default. Do not reset: whatever you do not set reverts to the model default on the next
  call. Never rely on a value persisting between calls.
- **Only restrict, never widen.** The model and authorization settings are the ceiling. A
  detail tab, task or report hidden in the model cannot be shown by a Context; a Context
  can only tighten what the model already allows.
- **No DML on tables.** A Context is UI-control logic. Read with `select` only — never
  `insert`, `update` or `delete`.
- **Read the current row via `@<col>`** to decide. A Context has no `@layout_mode` and no
  `@import_mode`; it does not know add vs update.
- **Keep it lightweight.** Avoid cursors, explicit transactions and temporary tables — a
  Context runs whenever the record changes and must stay fast.

---

## Fixed variables (provided by the generated proc — do NOT declare them)

Shown with the SQL Server `@` prefix; use `v_` for Oracle/DB2 and `p_<id>` for PostgreSQL.

| Variable                | Type          | Direction | Meaning                                                       |
|-------------------------|---------------|-----------|---------------------------------------------------------------|
| `@active_target_ref_id` | varchar(400)  | out       | the active detail tab when the procedure is called; assign it to set which detail tab is active |
| `@<col>`                | column domain | in        | current value of each column — read to decide, do not assign  |
| `@<ref_id>_type`        | tinyint       | out       | detail/reference tab availability: `0` = enabled, `1` = disabled, `2` = hidden |
| `@<task_id>_type`       | tinyint       | out       | task availability: `0` = enabled, `1` = disabled, `2` = hidden |
| `@<report_id>_type`     | tinyint       | out       | report availability: `0` = enabled, `1` = disabled, `2` = hidden |

**Variable naming.** The variable is simply `@<id>_type` — the object's id plus `_type`,
using the id exactly as it appears in the metadata. References are always named with a
`ref_` prefix in the model, so `@<ref_id>_type` naturally renders as `@ref_..._type`
(e.g. `@ref_location_resource_type`); do not add another `ref_` yourself. When a reference
sits in more than one screen area, use the area-specific variant instead of plain `_type`:
`@<ref_id>_form_type` (shown in the form) or `@<ref_id>_child_type` (shown as a detail/child
grid). Tasks and reports use the plain task or report id plus `_type`
(`@<task_id>_type`, `@<report_id>_type`) — no extra prefix.

**No messages.** Per the Thinkwise guidelines a Context must not send messages
(`tsf_send_message` or `raiserror`); it expresses itself only through availability. The
other helpers in `references/conventions.md` (username, domain elements) still apply.

Note on the active tab: `@active_target_ref_id` (`varchar(400)`, output) holds the active
detail tab when the procedure is called. Assign it to make a specific detail tab active by
setting it to a reference id from the metadata. Leave it untouched to keep the tab the user or
model would otherwise land on.

---

## Resolving the ids from the metadata

Never invent a `<ref_id>`, `<task_id>` or `<report_id>`. Take them from the pasted
`get_sf_metadata` output:

- **Detail tabs** — a Context can only address a detail tab that is present in the
  metadata as a reference, so the metadata must include the reference sections
  (`detail_refs` / `lookup_refs`; on by default). When the user says "hide the order line
  tab", find the reference that links to that detail table and use its reference id (the
  `id` / `ref_id` field, which already starts with `ref_`) in `@<ref_id>_type`. Do not
  guess the id from the table name.
- **Tasks / reports** — use the `task_id` / `report_id` from the `tasks` and `reports`
  sections of the table's metadata for `@<task_id>_type` / `@<report_id>_type`.

If the request targets a detail tab, task or report that is not in the metadata, ask the
user to paste metadata that includes it rather than assuming an id.

---

## Core idioms

**1. Hide or disable a detail/reference tab.** Use `2` to hide, `1` to disable. The ref id
already carries its `ref_` prefix:

```sql
set @ref_sales_order_line_type = 2   -- hidden
```

When the reference sits in multiple screen areas, target the area you mean with
`@<ref_id>_form_type` (form) or `@<ref_id>_child_type` (detail grid).

**2. Hide or disable a task or report.** Just the task or report id plus `_type`:

```sql
set @approve_order_type = 1   -- task disabled
set @print_invoice_type = 2   -- report hidden
```

**Set many availabilities at once** with a single `select`, which is handy when one
condition drives several tabs:

```sql
select @ref_product_category_form_type    = 0   -- enabled
      ,@ref_product_subcategory_form_type = 2   -- hidden
      ,@ref_product_group_child_type      = 2   -- hidden
```

**3. Read extra data from the database (read-only).** A Context receives only the current
record's column values. To decide on data that is not in the call, query it with `select`
only; you may declare your own local variables (only the generated/standard variables must
not be declared).

```sql
if (select o.order_status from sales_order o where o.sales_order_id = @sales_order_id) = 2   --closed
begin
    set @add_order_line_type = 1   --disable the add-line task on a closed order
end
```

**4. Set only what differs (stateless).** Only assign an output when it should deviate
from the model default. Omit the rest; do not add "reset to 0" lines, because an unset
output already falls back to the model default on the next call.

**5. Set the active detail tab** by assigning a reference id to `@active_target_ref_id`.

---

## Worked examples (patterns from real contexts, fully anonymized)

**Example 1 — hide references based on a type domain value** (single and IN-list guards on
a fixed value list; `@<ref_id>_type = 2` to hide):

```sql
-- Determine reference visibility based on the project type

-- Not an external project
if @project_type <> 2 --external
begin
    set @ref_project_invoice_type = 2 --hidden
end

-- Not an internal project
if @project_type <> 1 --internal
begin
    set @ref_project_cost_center_type = 2 --hidden
end

-- Internal or maintenance
if @project_type in (1, 3) --internal, maintenance
begin
    set @ref_project_billing_type = 2 --hidden
end
```

**Example 2 — drive many references from a hierarchy** (if / else-if over the filled key
levels; one `select` sets all availabilities; note the `_form_type` and `_child_type`
screen-area variants):

```sql
-- Show the country and its child region, hide the rest, when only a country is chosen
if @region_id is null
begin
    select @ref_area_selection_country_form_type  = 0 --enabled
          ,@ref_area_selection_region_form_type   = 2 --hidden
          ,@ref_area_selection_city_form_type     = 2 --hidden
          ,@ref_area_selection_region_child_type  = 0 --enabled
          ,@ref_area_selection_city_child_type    = 2 --hidden
          ,@ref_area_selection_city_contact_type  = 2 --hidden
end
-- Show the region and its child city, hide the rest, when a region is chosen
else if @city_id is null
begin
    select @ref_area_selection_country_form_type  = 2 --hidden
          ,@ref_area_selection_region_form_type   = 0 --enabled
          ,@ref_area_selection_city_form_type     = 2 --hidden
          ,@ref_area_selection_region_child_type  = 2 --hidden
          ,@ref_area_selection_city_child_type    = 0 --enabled
          ,@ref_area_selection_city_contact_type  = 2 --hidden
end
-- Show the city and its contact details when a city is chosen
else if @country_id is not null
    and @region_id is not null
begin
    select @ref_area_selection_country_form_type  = 2 --hidden
          ,@ref_area_selection_region_form_type   = 2 --hidden
          ,@ref_area_selection_city_form_type     = 0 --enabled
          ,@ref_area_selection_region_child_type  = 2 --hidden
          ,@ref_area_selection_city_child_type    = 2 --hidden
          ,@ref_area_selection_city_contact_type  = 0 --enabled
end
```

A read-only database query is allowed here too when a decision needs data that is not in
the call (idiom 3) — prefer the record's own column values where you can.

---

## Output checklist

- [ ] Only the fragment — no `create`/`alter`, no declaration of the fixed variables.
- [ ] No `insert` / `update` / `delete` on any table; column values are read, not set.
- [ ] Outputs are set only where they must differ from the model default — no reset lines.
- [ ] `@<ref_id>_type` / `@<task_id>_type` / `@<report_id>_type` use `0` / `1` / `2` (ids from the metadata, ref ids already include `ref_`).
- [ ] Logic only restricts; it never tries to widen beyond the model/authorization.
- [ ] Short `--` comments explain the intent of each block.
- [ ] `@` prefix for SQL Server, `v_` for Oracle/DB2, `p_<id>` for PostgreSQL (`v_` only for locals the template declares).
