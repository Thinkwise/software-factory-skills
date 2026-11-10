# Process procedure

## What it does and when it fires

A process procedure runs automatically after a process action that is part of a process flow
(in the flow design such an action shows a gear icon; a decision node always has one). It
decides which follow-up steps run and in what order, reads and updates the flow's variables
to carry state through the flow, and may also operate on data in the database.

The initial status of the next steps is already set by how the action completed: on failure
the "successful" follow-up steps are disabled, on success the "unsuccessful" ones are. The
process procedure refines this further.

---

## Deliverable and object

A process procedure becomes a stored procedure named `prc_<flow>_<action>` (the process flow
id followed by the process action id). The deliverable is only the fragment woven into the
body — no `create procedure`, no parameter list, no `set nocount on`.

---

## Fixed variables (provided by the generated proc — do NOT declare them)

| Variable            | Direction  | Meaning |
|---------------------|------------|---------|
| `@<process_var>`    | in / out   | one per process-flow variable; read it to branch on, and set it to carry a value forward to later steps (variables keep their value for the flow's lifetime). |
| `@<next_step_id>`   | **out** (`int`) | one per outgoing step; default `1` = the step executes, set `0` to skip that step. |

These names come from the process-flow definition (the generated procedure's parameter list),
**not** from `get_sf_metadata`, which does not cover process flows. If the variable and
outgoing-step names are not provided, ask for them rather than guessing.

---

## Hard rules

- **Steer the flow only through the fixed variables** — set an outgoing-step variable to `0`
  to skip it (or `1` to keep it), reorder/enable the immediate next steps, and write process
  variables to pass state on. Do not try to control the flow any other way.
- **Only override what differs.** The step variables already default to executing and the
  action's success/failure has pre-disabled the wrong branch; touch only the steps you need
  to change.
- **Branch only on variables that are filled.** If an action did not complete successfully,
  some variables may be empty or unvalidated.
- **Not atomic by default.** Unlike handlers (and tasks marked atomic), a process procedure
  gets no generated transaction wrapper, so when you perform multi-statement DML, open and
  close the transaction yourself (`begin tran` / `commit tran` / `rollback tran`).
- **Loop inside the procedure, not in the flow.** Looping within a process procedure is much
  faster than a loop in the process flow, because it avoids round trips between Indicium and
  the database.

---

## Core idioms

**1. Skip a follow-up step conditionally** — set its step variable to `0`:

```sql
-- Do not print the confirmation report when the order is already closed
if @order_status = 1
begin
    set @print_report = 0
end
```

**2. Follow exactly one branch** — disable every outgoing step except the matching one:

```sql
if @order_status <> 1 begin set @print_report      = 0 end
if @order_status <> 2 begin set @send_notification  = 0 end
if @order_status <> 3 begin set @escalate_to_manager = 0 end
```

**3. Carry state forward** — write a process variable that later steps read as input:

```sql
set @process_invoice_id = @order_invoice_id
```

**4. Operate on data with your own transaction** (process procedures are not atomic):

```sql
begin try
    begin tran
    update order_header
    set order_status = 2               -- Approved
    where order_id = @order_id
    commit tran
end try
begin catch
    if @@trancount > 0 rollback tran
    throw
end catch
```

---

## Worked example

After an "approve order" action, print a confirmation report only for approved orders and
send a notification only when the order is on hold, skipping the branches that do not apply:

```sql
-- Print the confirmation report only when the order is approved
if @order_status <> 2
begin
    set @print_report = 0
end

-- Notify only when the order is on hold
if @order_status <> 3
begin
    set @send_notification = 0
end
```

---

## Output checklist

- [ ] Only the fragment — no `create procedure`, no parameter declarations.
- [ ] Flow steered only via outgoing-step variables (`0`/`1`) and process variables; only the steps that differ are touched.
- [ ] Branches guard on filled variables; no reliance on values an unsuccessful action left empty.
- [ ] Any multi-statement DML wraps its own transaction (process procedures are not atomic).
- [ ] Loops live inside the procedure, not in the flow, when a loop is needed.
- [ ] Variable/step names taken from the flow definition (asked for if absent); `@` for SQL Server, `v_` for Oracle/DB2, `p_<id>` for PostgreSQL (step switches `p_<step_id>`; `v_` only for locals the template declares).
