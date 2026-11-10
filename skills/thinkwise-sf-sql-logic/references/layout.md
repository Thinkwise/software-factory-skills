# Layout

## What it does and when it fires

A Layout determines, from the values in the current record, whether fields are visible,
editable and mandatory, and whether the data-manipulation buttons (add, update, delete,
confirm, cancel) are available. The Software Factory calls it automatically:

- when another record is selected;
- as soon as the user clicks Add or Modify, or executes a Task or Report;
- in edit mode, as soon as a field the user modified is left.

Like a Default, a Layout runs in the front-end on the current record, before commit.

---

## Hard rules

- **Stateless.** A Layout's effect lasts only until its next call. Set a field's type or
  mandatory flag, or a button's availability, **only when it must differ from the
  modelled meta-level default**. Do not reset a value back: whatever you do not set
  reverts to the model default on the next call. Never rely on a value persisting
  between calls.
- **Only restrict, never widen.** The model and authorization settings are the ceiling.
  A field hidden in the model cannot be shown by a Layout; a button disabled by rights
  cannot be enabled. A Layout can only tighten what the model already allows.
- **No DML on tables.** A Layout is UI-control logic that runs before and around editing.
  Read with `select` only — never `insert`, `update` or `delete`.
- **Read the current row via `@<col>`** and branch on `@layout_mode` where add, update or
  navigate should behave differently. A Layout reads column values; it does not set them
  (setting a column value is a Default).
- **Keep it lightweight.** Avoid cursors, explicit transactions and temporary tables — a
  Layout runs on every relevant UI event and must stay fast.

---

## Fixed variables (provided by the generated proc — do NOT declare them)

Shown with the SQL Server `@` prefix; use `v_` for Oracle/DB2 and `p_<id>` for PostgreSQL.

| Variable                | Type          | Direction | Meaning                                                                 |
|-------------------------|---------------|-----------|-------------------------------------------------------------------------|
| `@layout_mode`          | tinyint       | in        | `0` = add, `1` = update, `2` = navigate                                 |
| `@import_mode`          | tinyint       | in        | `0` = regular, `1` = import row, `2` = export, `3` = import             |
| `@add_button_type`      | tinyint       | out       | Add button: `0` = enabled, `1` = disabled, `2` = hidden                 |
| `@update_button_type`   | tinyint       | out       | Update button (same enum)                                               |
| `@delete_button_type`   | tinyint       | out       | Delete button (same enum)                                               |
| `@confirm_button_type`  | tinyint       | out       | Confirm/save button (same enum)                                         |
| `@cancel_button_type`   | tinyint       | out       | Cancel button (same enum)                                               |
| `@<col>_type`           | tinyint       | out       | field display: `0` = normal (editable), `1` = read only, `2` = hidden within the form (space stays reserved), `3` = hidden outside the form |
| `@<col>_mand`           | tinyint       | out       | `1` = mandatory (`0` = optional)                                        |
| `@<col>`                | column domain | in        | current value of each column — read to branch on, do not assign         |

**No messages.** Per the Thinkwise guidelines a Layout must not send messages
(`tsf_send_message` or `raiserror`); it enforces purely through field state (`_type` /
`_mand`) and button availability. If the user needs to be told something, that belongs in
a Default (which may inform with `abort = 0`). The other helpers in
`references/conventions.md` (username, domain elements) still apply.

---

## Core idioms

**1. Branch on the mode.** Add, update and navigate often need different layouts:

```sql
if @layout_mode = 1   --update
begin
    ...
end
```

**2. Make a field mandatory conditionally.**

```sql
set @activated_date_mand = 1   -- mandatory
```

**3. Change a field's display.** Hide, make read-only, or hide outside the form:

```sql
set @remark_type = 1   -- read only
set @secret_type = 2   -- hidden
set @note_type   = 3   -- hidden outside the form
```

**4. Control a data-manipulation button.**

```sql
set @delete_button_type = 1   -- disabled
set @add_button_type    = 2   -- hidden
```

**5. Set only what differs (stateless).** Only assign an output when it should deviate
from the model default. Omit the rest; do not add "reset to 0" lines, because an unset
output already falls back to the model default on the next call.

**6. Read extra data from the database (read-only).** A Layout only receives the current
record's column values. To decide on data that is not in the call, query it — with
`select` only, never DML. Inline it in the condition:

```sql
-- Lock editing once the linked order is closed
if (select o.order_status from sales_order o where o.sales_order_id = @sales_order_id) = 2   --closed
begin
    set @update_button_type = 1   --disabled
    set @delete_button_type = 1
end
```

Or, if the value is reused, declare your own local variable for it (declaring your own
working variables is fine; only the generated/standard variables must not be declared):

```sql
declare @order_status int =
    (select o.order_status from sales_order o where o.sales_order_id = @sales_order_id)

if @order_status = 2   --closed
begin
    set @update_button_type = 1
    set @delete_button_type = 1
end
```

The `if exists (...)` check in Example 3 below is the same idea for presence rather than
a value.

---

## Worked examples (real Thinkwise layouts)

**Example 1 — hide a field based on a domain value** (idiom 3; branches on the
`db_value` of a fixed value list, `0` = standard order):

```sql
-- When the order is not a standard order, hide the delivery_window
if @order_type <> 0 --standard
begin
    set @delivery_window_id_type = 3 --hidden outside
end
```

**Example 2 — read-only depending on the mode** (idioms 1 and 3):

```sql
--When adding, set active to readonly
if @layout_mode = 0 --add
begin
    set @active_type = 1 --readonly
end
```

**Example 3 — disable buttons from a read-only check** (idiom 4; one `select` sets
several button outputs at once, `exists` reads the row without any DML):

```sql
-- Disable add/update/delete when the current record is (future) active
if exists (select 1
           from [table_name]
           where (   active        = 1   --active
                  or future_active = 1   --future active
                 )
             and [primary_key] = @[primary_key]
          )
begin
    select @add_button_type    = 1
          ,@update_button_type = 1
          ,@delete_button_type = 1
end
```

**Example 4 — several fields driven by relation-type flags** (idioms 2, 3, 5; the same
field is mandatory, read-only or hidden depending on the flags, and nothing is reset):

```sql
-- Determine field behavior based on the relation type
if @is_supplier = 1
begin
    if @is_preferred = 1
    begin
        set @tax_registration_number_mand = 1 --mandatory
    end
    else
    begin
        set @tax_registration_number_type = 1 --read only
    end
end

if @is_customer = 0
begin
    set @pickup_location_id_type = 3 --hidden outside form
end

if @is_supplier = 0
begin
    set @tax_registration_number_type = 3 --hidden outside form
end
```

---

## Output checklist

- [ ] Only the fragment — no `create`/`alter`, no declaration of the fixed variables.
- [ ] No `insert` / `update` / `delete` on any table; column values are read, not set.
- [ ] Outputs are set only where they must differ from the model default — no reset lines.
- [ ] `@<col>_type` uses `0`/`1`/`2`/`3`; `@<col>_mand` uses `1`; button types use `0`/`1`/`2`.
- [ ] Logic only restricts; it never tries to widen beyond the model/authorization.
- [ ] Short `--` comments explain the intent of each block.
- [ ] `@` prefix for SQL Server, `v_` for Oracle/DB2, `p_<id>` for PostgreSQL (`v_` only for locals the template declares).
