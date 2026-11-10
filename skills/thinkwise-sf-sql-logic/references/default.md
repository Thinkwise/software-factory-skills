# Default

## What it does and when it fires

A Default changes the value of fields (and can move the cursor) during add, import or
modify, based on values entered in other fields. The Software Factory calls it
automatically:

- as soon as the user clicks Add, or executes a Task or Report;
- in edit mode, as soon as a field that the user modified is left.

A Default runs in the front-end, on the current record, **before** the user saves.
Nothing it touches is committed yet.

---

## Hard rules

- **Never do DML on a table.** No `insert`, `update` or `delete`. The record is not
  committed and the Default runs client-side before save; writing to tables here is
  wrong and unsupported. Read with `select` only. If the intent is to change other rows
  or tables, that is a Trigger or a Task, not a Default.
- **Only affect the current row**, through its `@<col_id>` variables (plus the cursor
  and auto-commit variables below).
- **Guard on `@cursor_from_col_id`.** The Default is re-invoked every time a field is
  left, so unguarded logic runs far too often and fights the user's typing. Run each
  block only when the field(s) it depends on triggered it.

---

## Fixed variables (provided by the generated proc — do NOT declare them)

The SF generates the procedure signature; the fragment only uses these. Shown with the
SQL Server `@` prefix; use `v_` for Oracle/DB2 and `p_<id>` for PostgreSQL.

| Variable              | Type          | Direction | Meaning                                                        |
|-----------------------|---------------|-----------|----------------------------------------------------------------|
| `@default_mode`       | tinyint       | in        | `0` = add, `1` = update                                        |
| `@import_mode`        | tinyint       | in        | `0` = regular, `1` = import row, `3` = import                  |
| `@cursor_from_col_id` | varchar(255)  | in        | the column that triggered the default (the field just left)    |
| `@cursor_to_col_id`   | varchar(255)  | out       | set this to move the cursor to a column after the default      |
| `@auto_commit`        | bit           | out       | set to `1` to commit without the user pressing save/execute    |
| `@<col_id>`           | column domain | in / out  | one per table column; read the current value, assign to change |

Only touch `@cursor_to_col_id` and `@auto_commit` when the request actually asks to move
the cursor or auto-commit; otherwise leave them alone.

**Helpers available inside a Default:**

- `tsf_send_message '[message_id]', [xml_params | null], [abort]` — inform or warn the
  user. In a Default, **always use `abort = 0`** (informational, continues): a Default
  corrects the value and tells the user, it never aborts. A hard save-block belongs in a
  Layout (mandatory/validation), not here. Full parameter reference in
  `references/conventions.md`.
- `tsf_user()` / `tsf_original_login()` — current username.
- `get_dom_elemnt_id('domain', db_value)` — resolve an element id. To store a value,
  assign the raw `db_value` (match `elemnt_id` in the metadata to its `db_value`).

---

## Core idioms

**1. Guard on the triggering column(s).** Single column or a set:

```sql
if @cursor_from_col_id = 'postal_code'
...
if @cursor_from_col_id in ('product_id', 'customer_id', 'quantity')
```

**2. Derive one or more fields with a select.** Assign several outputs in one read:

```sql
select @city     = pc.city
      ,@province = pc.province
from postal_code pc
where pc.postal_code = @postal_code
```

Reset an output first (`set @out = null`) only when the code logic actually calls for it,
for example when a later block might leave it unset and a stale value would be wrong. It
is not a default habit; add it only where it makes sense.

**3. Validate, correct, inform.** A Default never aborts. Correct the variable and send an
informational message (`abort = 0`), never `abort = 1`:

```sql
if <invalid condition>
begin
    set @some_flag = 0                              --correct the value
    exec tsf_send_message 'some_message', null, 0   --inform the user
end
```

**4. Program on domain values, not magic literals.** When a column is backed by a fixed
value list, compare and assign the `db_value`, and prefer a domain with elements over
hard-coded numbers. This keeps the logic readable and stable.

**5. Move the cursor or auto-commit — only when asked.**

```sql
set @cursor_to_col_id = 'next_col'   -- park the cursor after the default
set @auto_commit      = 1            -- commit without an explicit save
```

**6. Fill when empty.** Suggest a value only while the target field is still empty, so a
value the user typed is never overwritten. Combine with the guard on the driving column:

```sql
-- Fill the delivery address from the customer, only while it is still empty
if @cursor_from_col_id = 'customer_id'
   and @delivery_address is null
begin
    select @delivery_address = c.address
    from customer c
    where c.customer_id = @customer_id
end
```

To fill it once when the form opens (add, or a task form) and leave it alone afterward,
guard on the initial pass instead: `@cursor_from_col_id` is empty then — check both
`is null` and `= ''`.

```sql
-- Default the end date from the start date on the initial pass only
if (   @cursor_from_col_id is null
    or @cursor_from_col_id = ''
   )
   and @end_date is null
begin
    set @end_date = dateadd(day, 2, @start_date)
end
```

---

## Worked examples (real Thinkwise defaults)

**Example 1 — validate, correct and inform** (idiom 3, reading a parent row read-only):

```sql
-- Deny activating when the parent is inactive
if @cursor_from_col_id = 'active'
   and @active         = 1                --activating
   and exists (select 1
               from location l
               where l.location_id = @parent_location_id
                 and l.active      = 0    --parent inactive
              )
begin
    set @active = 0                        --force back to inactive
    exec tsf_send_message 'cannot_activate_without_active_parent', null, 0
end
```

**Example 2 — guard on a set of triggering columns, then look up** (idiom 1):

```sql
-- Resolve the price agreement based on the chosen values
if @cursor_from_col_id in ('product_id', 'customer_id', 'quantity')
begin
    -- Try to retrieve an applicable price agreement
    select @price_agreement_id = pa.price_agreement_id
    from price_agreement pa
         left join customer c
           on c.customer_id = @customer_id
    where pa.product_id = @product_id
      and (   (    pa.customer_group_id = c.customer_group_id
               and pa.min_quantity     <= @quantity
              )
           or @customer_id is null       --no customer chosen yet
          )
end
```

**Example 3 — derive multiple fields from one choice** (idioms 1 and 2):

```sql
-- Set the city and province after entering a postal code
if @cursor_from_col_id = 'postal_code'
   and @postal_code is not null
begin
    select @city     = pc.city
          ,@province = pc.province
    from postal_code pc
    where pc.postal_code = @postal_code
end
```

---

## Output checklist

- [ ] Only the fragment — no `create`/`alter`, no declaration of the fixed variables.
- [ ] Guarded on `@cursor_from_col_id` wherever the logic is field-driven.
- [ ] A suggested value never overwrites one the user entered (fill when empty) unless the request says it should.
- [ ] No `insert` / `update` / `delete` on any table.
- [ ] Any `tsf_send_message` uses `abort = 0` — a Default corrects and informs, never aborts.
- [ ] Columns with a fixed value list are set to the raw `db_value`.
- [ ] Short `--` comments explain the intent of each block.
- [ ] `@` prefix for SQL Server, `v_` for Oracle/DB2, `p_<id>` for PostgreSQL (`v_` only for locals the template declares).
