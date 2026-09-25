# Calling a subroutine from every place it can be invoked

Loaded on demand from `thinkwise_sf_subroutines`.

## Calling a subroutine — every place it gets invoked from

A subroutine has no UI surface of its own; it only ever runs because something else calls it.

- **From another control procedure (any code type)** — the most common path. Named parameters, always:
  ```sql
  exec dbo.calculate_order_amounts
       @order_id = @order_id,
       @amount   = @amount output;
  ```
  Named calls survive the callee's parameter insertion/reordering; positional calls don't. The caller
  owns the broader transaction unless the subroutine's own contract says otherwise (see "Transaction
  behavior"). `alias_subroutine_id`/`alias_subroutine_parmtr_id`/`api_alias` only affect the *external*
  API surface — an internal caller always uses the real `subroutine_id`/`subroutine_parmtr_id`.
- **From a query, view, or calculated column** — scalar use is concise
  (`select dbo.calculate_age(employee.birth_date, @as_of_date) from employee`), but repeated per-row
  scalar execution can be slow; prefer a set-based expression, join, `apply`, or an inline table-valued
  function for bulk use. A Template-method view (`thinkwise_sf_views`) can call a
  subroutine directly in its `SELECT`.
- **From a process flow — there is no dedicated "call subroutine" process action, verified.** Two
  mechanisms carry real SQL in a process flow (see `thinkwise_sf_process_flows`'s "Process
  logic and control procedures" section):
  1. A `decision` action with `use_processes = true` opts that action into the `PROCESSES` code group;
     its control procedure can call the subroutine directly. Use this for a code-only step between two
     other actions (no task/report/connector attached).
  2. More commonly, an `execute_task`/`execute_system_task` action calls a task whose own **Stored
     procedure**-type logic (in the `TASKS` code group) calls the subroutine.
- **From a task** — the task's Default/Layout/Handler/Task-type control procedure calls it exactly like
  any other control-procedure code type (`thinkwise_sf_tasks`).
- **From external applications, via Indicium** — only once `api`/`basic_api` is enabled (see below).
  External clients should never depend on the generated routine's internal name/ordering; call only
  through the published API contract.

### SQL restrictions by code type, when writing a subroutine's own body

From `thinkwise_sf_control_procedures`'s SQL style guide, the subroutine-specific
rules:
- **Subroutines (functions)**: no cursors, no explicit transactions, no table writes, no messaging —
  pure functions only.
- **Subroutines (procedures)**: avoid cursors where possible; wrap logic in explicit transactions, but
  check `prog_object_item` first — if the code group's own generated wrapper already bookends the
  template with transaction-start/commit items (as Task/Handler code groups do), the hand-written body
  should contain only the business logic, not its own `begin tran`/`commit tran`.
