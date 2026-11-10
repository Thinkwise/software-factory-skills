# Task

## What it does and when it fires

A Task is standalone business logic that the user starts explicitly — a button on a screen
(ribbon, context menu, task bar) or a menu item — or that runs on a schedule (batch). It can
also be called from any other logic concept. A Task is linked to one or more tables; columns
can be linked to its parameters, so the active record's values flow into those parameters.

When the user presses the button, the GUI shows a popup if the Task has visible parameters,
the user fills them, presses Execute, and the GUI runs the stored procedure with the
parameter values. A Task also has its own Default and Layout mechanisms for that popup
(`def_<task_id>`, `lay_<task_id>`) — those are separate concepts; this reference is about
the Task's business logic itself.

---

## Deliverable and object

A Task becomes a stored procedure named `task_<task_id>`, but the deliverable is only the
logic fragment woven into the body — no `create procedure`, no parameter list, no
`set nocount on`. Whether you also write the transaction handling depends on the mode below.

---

## Parameters (provided by the generated proc — do NOT declare them)

Each Task parameter is available as `@<param_id>`, typed by its domain. Take the parameter
ids, datatypes, mandatory flags and any fixed value lists from the `tasks` → `parameters`
section of the pasted `get_sf_metadata` output; do not invent them. Store domain-element
values as the raw `db_value` (see `references/conventions.md`).

---

## Atomic vs. batch (transactions)

This is the key choice for a Task:

- **Atomic task** — mark the Task as atomic in the Software Factory and it generates the
  transaction wrapper (`begin try / begin transaction … commit / catch … rollback / throw`),
  exactly like a Handler. Your fragment is then **only the business logic**; do not open your
  own transaction. (You can weave code into the generated `catch` for things like logging.)
- **Batch task** — for large or multi-step work, do **not** use one big transaction. Wrap
  smaller parts in their own transactions, typically **one transaction per iteration** of a
  cursor. This way a failure late in the run does not roll back the records already processed,
  and locking time stays short. Here you **do** write the transaction statements yourself.

---

## Hard rules

- **Always use transactions.** In an atomic task the wrapper is generated; in a batch task
  you write `begin tran` / `commit tran` / `rollback tran` yourself. When using a cursor,
  **every iteration is its own transaction**.
- **Prefer set-based over cursors.** Reach for a cursor only for genuine row-by-row batch
  work; when you do, declare it `local static read_only forward_only`.
- A Task **may** do DML, call procedures/tasks, and send messages — it is full business
  logic, not UI-control logic.
- **Report progress on long-running work** with `tsf_send_progress`, so the user sees status
  during execution (and during automatic saving).
- **Validate and abort** with `tsf_send_message '<msg>', null, 1`; in a batch task follow it
  with `rollback; return;`, in an atomic task the generated `catch` rolls back.

---

## Core idioms

**1. Simple atomic task — business logic only** (the SF wraps the transaction):

```sql
-- Generate invoices for hours not yet invoiced, up to the chosen date
insert into sales_invoice(customer_id
                         ,invoice_date
                         ,due_date
                         )
select c.customer_id
      ,getdate()                     as invoice_date
      ,dateadd(day, 30, getdate())   as due_date
from customer c
where (@customer_id is null or c.customer_id = @customer_id)
  and exists (select 1
              from project p
                   join hour h
                     on h.project_id = p.project_id
              where h.sales_invoice_id is null
                and p.customer_id      = c.customer_id
                and h.date            <= @until_date
             )
```

**2. Batch task — one transaction per iteration** (a late failure keeps earlier work):

```sql
declare invoice_cursor cursor local static read_only forward_only for
    select c.customer_id
    from customer c
    where @customer_id is null or c.customer_id = @customer_id

declare @cur_customer_id int
open invoice_cursor
fetch next from invoice_cursor into @cur_customer_id

while @@fetch_status = 0
begin
    begin try
        begin transaction
        insert into sales_invoice(customer_id
                                 ,invoice_date
                                 ,due_date
                                 )
        values (@cur_customer_id
               ,getdate()
               ,dateadd(day, 30, getdate())
               )
        fetch next from invoice_cursor into @cur_customer_id
        commit transaction
    end try
    begin catch
        if @@trancount > 0 rollback transaction
        throw
    end catch
end

close invoice_cursor
deallocate invoice_cursor
```

**3. Report progress** on a long task:

```sql
exec tsf_send_progress 'generate_invoices', '<text>Invoices</text>', 82
```

**4. Validate and abort** (batch task shown; an atomic task can omit the rollback/return):

```sql
if @until_date > getdate()
begin
    exec tsf_send_message 'until_date_in_future', null, 1
    rollback
    return
end
```

**5. Reuse from other logic.** A Task can be called with `exec task_<task_id> …` from a
process procedure, another task, or a handler.

---

## Output checklist

- [ ] Only the fragment — no `create procedure`, no parameter declarations.
- [ ] Atomic task: business logic only, no own `begin tran`. Batch task: explicit transactions, one per cursor iteration.
- [ ] Set-based where possible; cursors only for batch, declared `local static read_only forward_only`.
- [ ] Parameters use `@<param_id>` taken from the metadata; domain-element values stored as raw `db_value`.
- [ ] Long-running work reports progress with `tsf_send_progress`.
- [ ] Validation aborts with `tsf_send_message … , 1` (+ `rollback; return;` when not atomic).
- [ ] Short `--` comments explain the intent; `@` for SQL Server, `v_` for Oracle/DB2, `p_<id>` for PostgreSQL (`v_` only for locals the template declares).
