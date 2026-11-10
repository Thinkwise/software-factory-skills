# Trigger (event)

## What it does and when it fires

Trigger (event) logic runs around data manipulation, after data in a table is added,
changed or deleted. It is used to:

- perform controls that may reverse a transaction (functional integrity), and
- update other fields or rows in other tables as a consequence of a change.

It is the concept to reach for when something must happen **at or after commit** and may
touch **other rows or tables** — unlike a Default or Layout, which run in the UI on the
current record before commit.

---

## Deliverable and object

Unlike most concepts, a Trigger becomes an actual database **trigger**, not a stored
procedure. Still, the deliverable is only the logic fragment woven into the generated
trigger body — no `create trigger`, no header/footer. The fragment is **statement-level and
set-based**: it works on the affected rows through the pseudo-tables, not on per-column
`@` variables.

---

## Event and timing

A trigger is defined for one event and one timing:

- **Events:** insert, update, delete.
- **Timing:** *instead of*, *before*, *after*.

Determine both from the request (e.g. "after an order is deleted…" → after / delete). On
**SQL Server** the native timings are **`AFTER`** and **`INSTEAD OF`** (there is no `BEFORE`
trigger); prefer `AFTER`, and use `INSTEAD OF` only when justified, such as on a view.

---

## Context per event (SQL Server: the `inserted` / `deleted` pseudo-tables)

| Event  | Available rows                                                        |
|--------|-----------------------------------------------------------------------|
| insert | `inserted` — the new rows                                             |
| update | `inserted` (new values) and `deleted` (old values); the update fires only when a user actually changed a field |
| delete | `deleted` — the removed rows                                          |

There are no `@<col>` variables in a trigger. Read column values from `inserted` /
`deleted`, and because a statement can affect many rows, always write **set-based** logic.

---

## Hard rules

- **Always work through `inserted` / `deleted`, set-based.** Every statement should join or
  filter on the pseudo-tables so it only touches the affected rows. Never assume a single
  row (no scalar subquery over `inserted`/`deleted` without handling multiple rows).
- **Use triggers for integrity checks** (where constraints are not enough) **and for
  allowed-scope updates** — not for complex data mutations.
- **Respect the update scope.** For a strong entity, update its **own** table only. For a
  weak entity, you may update its **own** table and its **parent**. Avoid all other updates.
- **Avoid insert and delete operations on business tables** inside a trigger — they cause
  trigger cascades and belong in a Handler. Writing to a dedicated **log/audit** table is
  the accepted exception.
- **Do not call procedures** from a trigger. If you need to call a procedure or task, that
  is a Handler.
- **Do not update the `inserted` / `deleted` tables**, avoid cursors and `while` loops,
  limit variables, and avoid temporary tables. Keep it set-based.
- **Do not open an explicit `begin tran`.** The trigger already runs inside the triggering
  statement's transaction. To reject a change, `rollback` (optionally after a message) —
  this undoes the whole statement.

---

## Trigger or Handler?

The trigger Do's & Don'ts above narrow when a Trigger is the right concept. Before writing,
switch to `references/handler.md` (and re-confirm the concept with the user) if the task
needs any of these, which a Trigger must not do:

- call a procedure or task;
- work **row-by-row** rather than set-based;
- **populate a detail / child table** after saving (that is a Handler);
- insert into or delete from a business table, or update a table outside the strong/weak
  scope above;
- deliberately avoid a cascade of trigger activations.

Choose a **Trigger** for set-based integrity checks and in-scope updates (own table, or own
+ parent for a weak entity), and for reversing a transaction on a rule violation. Choose a
**Handler** for row-by-row logic, calling procedures/tasks, and populating child tables.

---

## Core idioms

**1. Log or audit after a change.** Insert into a log table from the pseudo-table:

```sql
insert into deleted_order_log(order_id
                             ,deleted_date
                             )
select d.order_id
      ,getdate()   --deletion timestamp
from deleted d
```

**2. Update the parent from the changed rows, set-based** (in scope for a weak entity's
trigger — a strong entity updates only its own table):

```sql
update o
set o.line_count = (select count(*) from order_line ol where ol.order_id = o.order_id)
from sales_order o
where o.order_id in (select order_id from inserted)
```

**3. Validate and reject.** Check the affected rows; if the rule is violated, message the
user and roll back the statement:

```sql
if exists (select 1 from inserted i where i.amount < 0)
begin
    exec tsf_send_message 'negative_amount_not_allowed', null, 1
    rollback
    return
end
```

**4. Act only on rows that really changed (update).** Compare `inserted` to `deleted`:

```sql
insert into price_change_log(product_id
                            ,old_price
                            ,new_price
                            ,changed_date
                            )
select i.product_id
      ,d.price     as old_price
      ,i.price     as new_price
      ,getdate()   as changed_date
from inserted i
     join deleted d
       on d.product_id = i.product_id
where i.price <> d.price   --price actually changed
```

`tsf_send_message` with `abort = 1` plus `rollback` is the documented way to reverse a
transaction from a trigger; see `references/conventions.md`.

---

## Worked example

After deleting an order, write a log record (the canonical documentation example, set-based
over `deleted`):

```sql
insert into deleted_order_log(order_id
                             ,deleted_date
                             )
select d.order_id
      ,getdate()   --deletion timestamp
from deleted d
```

---

## Dialect note

Triggers are the most platform-dependent concept. The `inserted` / `deleted`, statement-
level model above is **SQL Server**. Other platforms differ substantially — Oracle uses
row-level triggers with `:new` / `:old`, and PostgreSQL supports `BEFORE`/`AFTER` and
`ROW`/`STATEMENT` triggers with its own syntax. For a non-SQL-Server model the simple
variable-prefix swap does **not** carry over; confirm the platform's trigger model before
writing, rather than translating the T-SQL form literally.

---

## Output checklist

- [ ] Only the fragment — no `create trigger`, no header/footer.
- [ ] Event and timing are clear (e.g. after / delete); on SQL Server, `AFTER` unless `INSTEAD OF` is justified.
- [ ] Logic is set-based via `inserted` / `deleted`; no single-row assumption, no cursors.
- [ ] Updates stay in scope (own table; a weak entity may also update its parent); no inserts/deletes into business tables (logging excepted); no procedure calls.
- [ ] The task genuinely fits a Trigger — row-by-row work, calling procedures/tasks, or populating a detail table would be a Handler instead.
- [ ] No explicit `begin tran`; a rejection uses `rollback` (with a message where useful).
- [ ] For update logic, only rows that actually changed are acted on (`inserted` vs `deleted`).
- [ ] Short `--` comments explain the intent of each block.
- [ ] SQL Server assumed; for other platforms the trigger model is confirmed, not just prefix-swapped.
