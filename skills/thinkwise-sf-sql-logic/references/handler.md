# Handler

## What it does and when it fires

A Handler overrides the default `INSERT`, `UPDATE` or `DELETE` that the GUI or Indicium
(API) would otherwise run for a subject, replacing or extending it with your own logic.
It is activated **only when the action is initiated by the GUI or the API** — not when an
insert/update/delete happens through a plain SQL statement. That is exactly why a Handler
is a good way to avoid a cascade of trigger activations.

A Handler is the right concept for **row-by-row** work: deleting child rows before a
parent, populating a detail table after an insert, or calling a procedure or task per
record. For set-based work, use a Trigger.

Handlers are **atomic by default**: the Software Factory wraps the whole procedure in a
transaction with `try/catch`, so all mutations either succeed together or roll back. They
can also be unit tested.

---

## Deliverable and object

A Handler becomes a stored procedure per action — `ins_<table>`, `upd_<table>`,
`del_<table>` — but the deliverable is still only the logic fragment woven into the
generated body. You never write the `create procedure`, the `set nocount on`, or the
`begin try / begin transaction … commit / catch … rollback / throw` wrapper — the Software
Factory generates all of that.

---

## Auto-generate: base statement vs. deviation

Each handler can auto-generate the base statement for its own table (the plain
`insert` / `update` / `delete`). This drives what your fragment contains:

- **Auto-generate on** (default for tables) — the base statement is generated for you; your
  fragment is the **extra** logic around it (delete children first, populate a detail table
  after, call a task). Initially the handler behaves exactly like the CRUD button.
- **Auto-generate off** (default for views, or when you deviate) — you write the
  **replacement** behavior yourself. For example, a delete handler that archives instead of
  deleting.

---

## Parameters per action (provided by the generated proc — do NOT declare them)

Shown with the SQL Server `@` prefix; use `v_` for Oracle/DB2 and `p_<id>` for PostgreSQL.

| Action | Parameters                                                                                  |
|--------|---------------------------------------------------------------------------------------------|
| Insert | `@<col>` for every table column. An identity PK is an **output**: set it with `@<pk> = scope_identity()` so the GUI can select the new row. |
| Update | `@<col>` for every table column, **plus** `@upd_<pk>` for each primary-key column, holding the original key value that locates the row to update. |
| Delete | `@<pk>` for each primary-key column only.                                                    |

Columns can be excluded from the generated insert/update statements (e.g. trace columns)
by clearing their Insert/Update handler checkboxes; a PK or a mandatory column without a
default cannot be excluded from insert.

---

## Hard rules

- **Respect the DML scope.** You may insert/update/delete within **your own table** and
  within a **child table of your own entity**. Do **not** perform DML directly into a
  **parent** table or into a table in **another entity** — that is a Trigger's job (within
  its own scope) or belongs elsewhere.
- **No explicit transaction.** The handler is already atomic (SF generates the
  `begin transaction … commit` and the `catch … rollback … throw`). Never add your own
  `begin tran` / `commit tran`.
- **Row-by-row and procedure calls are fine.** Unlike a Trigger, a Handler may call a
  procedure or task — this is one of its main strengths.
- **Set the identity output on insert** (`set @<pk> = scope_identity()`) when the table has
  an identity PK and it is not already handled by the generated statement.
- **Keep it disciplined:** minimize cursors, limit variables, avoid temporary tables and
  `while` loops.

---

## Handler or Trigger?

Mirror of the choice in `references/trigger.md`:

- **Handler** — the action comes from the GUI/API, and you need row-by-row logic, want to
  call a procedure/task, want to populate a detail/child table, or want to deviate from the
  standard CRUD (archive instead of delete). Fires only on GUI/API, so no trigger cascade.
- **Trigger** — set-based integrity checks and in-scope updates that must fire for **any**
  data change, including plain SQL DML.

If unsure, and the work is per-record or calls out to other logic, lean Handler.

---

## Core idioms

**1. Delete children before the parent** (delete handler, auto-generate on — the SF adds
the parent delete after your fragment):

```sql
-- Remove the child rows first
delete project_phase
where project_id = @project_id
```

**2. Archive instead of delete** (delete handler, auto-generate off — you replace the
behavior; a locked prefilter hides archived rows from users):

```sql
update sales_order
set archived       = 1
   ,retention_date = dateadd(year, 1, sysutcdatetime())
where sales_order_id = @sales_order_id
```

**3. Populate a child table after insert**, using the new identity (insert handler):

```sql
-- @sales_order_id is the identity set by the generated insert / scope_identity()
insert into order_checklist(sales_order_id
                           ,checklist_item_id
                           ,done
                           )
select @sales_order_id
      ,ci.checklist_item_id
      ,0                    --not done yet
from checklist_item ci
```

**4. Return the identity on insert** when needed:

```sql
set @sales_order_id = scope_identity()
```

**5. Call a task or procedure per record** (well-suited to the handler's single-row model):

```sql
exec recalculate_order_total @sales_order_id = @sales_order_id
```

---

## Worked example (from the documentation)

Delete handler for `project`: the sub-projects must be removed before the project itself.
Only the child delete is the fragment; the Software Factory generates the atomic wrapper
and the `delete project …` base statement:

```sql
delete sub_project
where project_id = @project_id
```

---

## Dialect note

On **SQL Server** you use `@` parameters and `scope_identity()`. On **Oracle** and **DB2**
you cannot mutate `IN` parameters, so the platform generates **mutable variables**
(`m_<col>`, always generated); the generated insert/update/delete statements use those, and
you assign an identity from a sequence (e.g. `select <seq>.nextval into m_<pk> from dual`)
and return it via the `out` parameter. So for those platforms it is not just `@` → `v_`:
work with the generated `m_` variables. Confirm the platform's handler shape before writing.

---

## Output checklist

- [ ] Only the fragment — no `create procedure`, no `set nocount on`, no transaction/try-catch wrapper.
- [ ] Fragment matches the auto-generate setting: extra logic (on) or full replacement behavior (off).
- [ ] DML stays in scope: own table and own child tables only; no parent or other-entity DML.
- [ ] Insert with an identity PK sets `@<pk> = scope_identity()`.
- [ ] Update logic relies on `@upd_<pk>` to locate the row; delete uses the PK parameters.
- [ ] No explicit `begin tran` (the handler is already atomic).
- [ ] Cursors, variables, temp tables and `while` loops kept to a minimum.
- [ ] Short `--` comments explain the intent; `@` for SQL Server, `v_`/`m_` for Oracle/DB2, `p_<id>` for PostgreSQL.
