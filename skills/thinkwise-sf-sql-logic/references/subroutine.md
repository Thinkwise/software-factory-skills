# Subroutine

## What it does

A Subroutine is reusable logic — a stored procedure — that other logic calls to avoid
duplication and keep each concept small. It is never called by the GUI directly; it is
invoked with `exec <subroutine_id> …` from a task, a process procedure, a handler, a trigger
or another subroutine. If the reusable logic only computes a value or a result set and does
no data modification, use a Function instead (see `references/function.md`).

---

## Deliverable and object

A Subroutine becomes a stored procedure named after its subroutine id (no fixed prefix). The
deliverable is only the fragment woven into the body — no `create procedure`, no parameter
list, no `set nocount on`.

---

## Parameters (from the subroutine definition — do NOT declare them)

Each parameter is available as `@<param_id>`, typed by its domain. These names come from the
subroutine's own definition in the Software Factory, not from `get_sf_metadata` (which covers
tables, tasks and reports, not standalone subroutines). If the parameters are not provided,
ask for them rather than guessing. Store domain-element values as the raw `db_value` (see
`references/conventions.md`).

---

## Atomic vs. manual transactions

Just like a Task, a subroutine of type procedure can be marked **atomic** in the Software
Factory:

- **Atomic subroutine** — the SF generates the transaction wrapper (`begin try / begin
  transaction … commit / catch … rollback / throw`), so your fragment is **only the business
  logic**; do not open your own transaction.
- **Non-atomic subroutine** — you write the transaction handling yourself. For row-by-row
  batch work use **one transaction per cursor iteration** (see `references/task.md` for the
  full cursor pattern).

---

## Hard rules

- **Always use transactions.** In an atomic subroutine the wrapper is generated; otherwise
  wrap data modification in `begin tran` / `commit tran` / `rollback tran` yourself. When
  using a cursor, **every iteration is its own transaction**; declare the cursor
  `local static read_only forward_only`.
- **Mind transaction nesting.** When the subroutine is called from an atomic context (an
  atomic task, handler or atomic subroutine), its statements run inside that transaction;
  guard any manual rollback with `if @@trancount > 0` so you do not fight the caller's
  transaction.
- A Subroutine **may** do DML, call other procedures and send messages — it is full business
  logic.
- **Keep it single-purpose.** A subroutine exists to be reused; give it one clear
  responsibility so several concepts can share it.

---

## Subroutine or another concept?

Use a Subroutine only for logic genuinely shared by more than one caller. If the logic
belongs to one table and one event, put it in that table's concept instead (Default, Trigger,
Handler, and so on). If it returns a value or a set with no side effects, make it a Function.

---

## Core idioms

**1. Reusable procedure with its own transaction** (callable from many places):

```sql
-- Recalculate and store an order's total from its lines
begin try
    begin transaction

    update oh
    set oh.order_total = isnull(l.line_total, 0)
    from order_header oh
         outer apply (select sum(ol.quantity * ol.unit_price) as line_total
                      from order_line ol
                      where ol.order_id = oh.order_id
                     ) l
    where oh.order_id = @order_id

    commit transaction
end try
begin catch
    if @@trancount > 0 rollback transaction
    throw
end catch
```

**2. Called from another concept** — a task or handler invokes it:

```sql
exec recalculate_order_total @order_id
```

**3. Batch work** — one transaction per cursor iteration (see `references/task.md` for the
full cursor pattern), used when the subroutine processes many rows row-by-row.

---

## Worked example

A subroutine `recalculate_order_total` that a "recalculate" task and the order-line handler
both call — idiom 1 above is its body; both callers reach it with
`exec recalculate_order_total @order_id`.

---

## Output checklist

- [ ] Only the fragment — no `create procedure`, no parameter declarations.
- [ ] Atomic subroutine: business logic only, no own transaction. Non-atomic: explicit transaction; cursors one per iteration, declared `local static read_only forward_only`.
- [ ] Rollbacks guarded with `if @@trancount > 0` so a caller's transaction is respected.
- [ ] Single, clearly named responsibility; a Function used instead when there are no side effects.
- [ ] Parameters use `@<param_id>` from the subroutine definition (asked for if absent); domain-element values stored as raw `db_value`.
- [ ] Short `--` comments explain the intent; `@` for SQL Server, `v_` for Oracle/DB2, `p_<id>` for PostgreSQL (`v_` only for locals the template declares).
