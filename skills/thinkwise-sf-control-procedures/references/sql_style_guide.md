# Thinkwise SQL coding guidelines

**0 · Match the codebase's existing style — the most important rule, not an official Thinkwise
one.** Before writing a trace timestamp, a null-check, a string concatenation, or a user lookup,
check how the model already does it and copy that — don't introduce a second convention next to an
existing one, even if the new one is technically equivalent or "more correct" in isolation. Verified
example from a real production model: it standardized on `sysutcdatetime` (never `getdate`/
`getutcdate`), `isnull` (never `coalesce`), and `dbo.tsf_user` everywhere a current-user
lookup was needed. Introducing the portable/ANSI alternative from the dialect table in
`references/sql_dialects.md` into that codebase would be correct in isolation and wrong for that
codebase. Consistency beats being technically right. Grep the model's existing control procedures
first, every time.

**General:**
- Use a domain with domain elements if you need to program on values (not magic strings/numbers).
- Avoid `distinct` (e.g. count via a `group by` in a derived table instead of `count(distinct …)`)
  — it blocks predicate pushdown; see "Write pushdown-safe queries" below.
- Avoid `union` without `all` — same reason.
- Use `local static read_only forward_only` cursors when a cursor is genuinely unavoidable.
- Use `begin`/`end` in every `if`/`while`, even single-line ones.
- Use `tsf_send_message` instead of `raiserror`, always.
- Only use `apply` when joining a table-valued function or subquery.
- Every `begin tran` needs a matching `rollback tran` and `commit tran`.
- **A recursive CTE can't be nested inside any subquery expression, in any code type — verified
  live.** This is broader than a Trigger-specific restriction: `if exists (with cte as (...) select
  1 from cte ...)` fails with a syntax error near `with` on a Handler exactly the same way it does on
  a Trigger, even though the CTE is immediately followed by the single query that consumes it — the
  CTE has to stand as its own statement, not live inside an `exists`/`in`/scalar subquery. For a
  code type that can use variables (Handler/Task/Subroutine — see the per-code-type restrictions
  below for which ones can't), run the CTE into a flag variable first as its own statement, then
  branch on the variable: `declare @flag bit = 0` / `select @flag = 1 from cte where ...` / `if @flag
  = 1 begin ... end`. Where variables aren't allowed (Triggers), see that section's bounded self-join
  workaround instead — it doesn't need a variable at all.

## Write pushdown-safe queries

This is the canonical copy. The views and cubes skills point here.

**Predicate pushdown** means a filter is applied at the base-table scan, so the database reads only
the rows it needs. When pushdown fails, the database builds the whole result first and filters it
afterward. Thinkwise always adds a filter *outside* your SQL: grid filters, prefilters, cube
drill-downs, and Indicium's `$filter=id eq 42` single-row lookups all wrap the generated view or
table-valued function. A `VIEWS` template or TVF body is fast only if that outer filter can reach
the base table.

| Blocks pushdown | Pushdown-safe alternative |
|---|---|
| `distinct` (the full deduplicated set has to be built first) | `group by` in a derived table, or remove the need for deduplication |
| `union` (deduplicates) | `union all` |
| Filter on an aggregated value (not a grouping column) | Filter on the grouping columns |
| Filter on the nullable side of an outer join | `inner join`, or filter on the preserved side |
| CTE the engine materializes (engine- and version-dependent) | Inline it as a derived table |
| Window function (`row_number`/`rank`/…) when the filter column isn't in `partition by` | Partition by the columns users filter on, or move the window function out of the view |

```sql
-- rank() partitions by region only
create view v_customer_rank as
select customer_id
      ,region
      ,order_total
      ,rank() over (partition by region order by order_total desc) as region_rank
from orders;

select * from v_customer_rank where customer_id = 42; -- scans and ranks every row, then filters
select * from v_customer_rank where region = 'EU';    -- pushes down: region is in partition by
```

Treat a suspected pushdown problem as a hypothesis: read the actual execution plan before rewriting,
and see "How to diagnose" in `logic_concept_design_guide.md`.

**By code type:**
- **Triggers**: functional-integrity validation, not complex data mutation (use a Handler/Task for
  that). Every statement should reference `inserted`/`deleted`. No cursors, no explicit
  transactions, no variables, no temp tables, never modify `inserted`/`deleted` directly.
  **A recursive CTE can't be used to feed an `if` check here**: `with cte as (...)
  if exists (select ... from cte ...)` is invalid T-SQL — a CTE must be immediately followed by the
  single query that consumes it, not a control-flow statement. This surfaces only as a deploy-time
  syntax error ("Incorrect syntax near the keyword 'if'"), not a generation-time failure, so a
  "Successful" code-generation status doesn't catch it. For a hierarchical/recursive check inside a
  Trigger — where the restrictions above also rule out capturing the CTE's result in a variable or
  temp table first — use a bounded chain of self-joins walking a fixed number of levels instead
  (e.g. 15-20 `left join`s up a self-referencing parent column): fully set-based, no CTE, variable,
  or temp table required.
- **Defaults**: wrap in `if`; don't reassign an input parameter's incoming value blindly. No
  cursors, no explicit transactions, no table writes, no temp tables.
- **Layouts, Contexts, Processes**: same restrictions as Defaults, **plus**: never send messages
  here at all.
- **Tasks & Subroutines (stored procedures)**: avoid cursors where possible; always wrap in
  explicit transactions — **verified live: for Task and Handler code types, the code group's own
  generated wrapper items (e.g. a `transaction_start`/`transaction_commit`/`transaction_catch` set)
  already bookend your assigned template as separate `prog_object_item` rows, so your own template
  should contain just the business logic, not its own `begin tran`/`commit tran`; check
  `prog_object_item` for the target object before adding transaction statements by hand**; if a cursor
  is unavoidable, wrap each iteration in its own transaction.
- **Subroutines (functions)**: no cursors, no explicit transactions, no table writes, no messaging —
  pure functions only.

**Formatting:** spaces not tabs; lowercase everywhere (keywords, built-in functions, data types,
session variables); comment every code block and non-obvious literal; strip dev-only helper code
before shipping; explicit column list on every `insert`; alias calculated values/literals and align
aliases; commas before the column name; one column per line; one `when` per line in a `case`; one
`select` (not several `set`s) to assign multiple variables, and one `declare` to declare them; a `/* element name */` comment after
every domain-element value; align comparison operators.

**One column per line — in every `insert`, `select`, `update` and `merge`.** Every column goes on its
own line: `insert` column lists, `values` lists, `select` lists, `update ... set` assignments, and
the `update set`/`insert (...)`/`values (...)` parts of a `merge`. The first column follows the
opening keyword or parenthesis; every following column starts on a new line with a leading comma,
aligned under the first column. Never write an inline list like
`insert into robot_visited_cell (robot_id, x, y, first_visited_at)` — not even for two columns. This
is a house rule: it applies even when the surrounding codebase uses inline lists (rule 0 doesn't
override it).

```sql
-- Insert: column list and select list, one column per line
insert into robot_visited_cell (robot_id
                               ,x
                               ,y
                               ,first_visited_at)
select r.robot_id
      ,r.x
      ,r.y
      ,sysutcdatetime() as first_visited_at
from robot r

-- Update: one assignment per line
update robot
set    x = @x
      ,y = @y
where  robot_id = @robot_id

-- Merge: source select, update set, insert and values lists all one column per line
merge robot_visited_cell as t
using (select @robot_id as robot_id
             ,@x        as x
             ,@y        as y) as s
on    t.robot_id = s.robot_id
  and t.x        = s.x
  and t.y        = s.y
when matched then
    update
    set    last_visited_at = sysutcdatetime()
          ,visit_count     = t.visit_count + 1
when not matched then
    insert (robot_id
           ,x
           ,y
           ,first_visited_at)
    values (s.robot_id
           ,s.x
           ,s.y
           ,sysutcdatetime());
```

**One `when` per line in every `case` expression.** Put each `when ... then ...` on its own line,
aligned under the first `when`; put `else` on its own line aligned with the `when`s; put `end` on its
own line aligned under `case`. This applies to both the simple form (`case @x when ...`) and the
searched form (`case when @x > 0 then ...`). Never write a `case` on one line, like
`case @heading when 'N' then N'▲' when 'E' then N'▶' when 'S' then N'▼' when 'W' then N'◀' else N'●' end`
— not even with just one `when`.

```sql
-- Simple case: each when on its own line, else and end on their own lines
select case @heading when 'N' then N'▲'
                     when 'E' then N'▶'
                     when 'S' then N'▼'
                     when 'W' then N'◀'
                     else N'●'
       end as heading_icon

-- Searched case: same layout
select case when @battery_pct >= 50 then 'ok'
            when @battery_pct >= 20 then 'low'
            else 'critical'
       end as battery_status
```

**Set multiple variables with one `select`, not a `set` per variable.** When you assign two or more
variables together, use a single `select` with each assignment on its own line, using the same
leading-comma layout as a column list. Use `set` only for assigning a single variable.
**Don't combine assignments that depend on each other.** SQL Server doesn't guarantee the order in
which one `select` evaluates its assignments, so `select @a = ..., @b = @a + 1` can read the old
`@a`. Put a dependent assignment in a separate, later statement.

```sql
-- Don't: one set statement per variable
set @x          = 0
set @y          = 0
set @heading    = 'N'
set @started_at = sysutcdatetime()

-- Do: one select, each variable on its own line, separated by leading commas
select @x          = 0
      ,@y          = 0
      ,@heading    = 'N'
      ,@started_at = sysutcdatetime()

-- Same layout when the values come from a table
select @x       = r.x
      ,@y       = r.y
      ,@heading = r.heading
from robot r
where r.robot_id = @robot_id
```

When the values come from a table and no row matches, the variables keep their previous values (they
are not set to `null`). Initialize them first, or check `@@rowcount`, when that matters.

**Declare variables the same way: one `declare`, each variable on its own line.** Use a single
`declare` with the first variable on the same line, and every following variable on its own line
with a leading comma. Align the data types. The exceptions are table variables and cursors: T-SQL
requires their own `declare` statement, so those stay separate.

```sql
-- Don't: one declare per variable
declare @x          int
declare @y          int
declare @heading    varchar(1)
declare @started_at datetime2

-- Do: one declare, each variable on its own line, leading commas
declare @x          int
       ,@y          int
       ,@heading    varchar(1)
       ,@started_at datetime2
```

**Name the domain element in a comment after every domain-element value.** When a statement checks
a column or variable against a domain element's value (a status, type, origin, and so on), put the
element's name in a `/* ... */` comment directly after the value. This applies everywhere the value
is checked: `where`, `on`, `if`, `case when`, and `merge` conditions. Do the same when you assign a
domain-element value. Look up the element name in the domain's elements rather than guessing it.
Skip the comment when the stored value already is the element name (e.g. `@command = 'dock'` for
element `dock`); a comment that repeats the value adds nothing.

```sql
-- Don't: a bare value, the reader has to look up what 3 means
case when @command_status = 3 then ...

-- Do: the domain element's name in a comment after the value
case when @command_status = 3 /* failed */ then ...

-- Same in joins, filters and assignments
from robot_command rc
where rc.origin         = 0 /* thinkwise */
  and rc.command_status = 1 /* pending */

update robot_command
set    command_status = 2 /* completed */
where  command_id     = @command_id
```

## Efficient Trigger example — avoid the cursor instinct

A trigger fires once per statement, not once per row — a multi-row insert lands in `inserted` all at
once. Looping through it row-by-row with a cursor throws away exactly what makes triggers fast, and
violates every Trigger rule above simultaneously:

```sql
-- Anti-pattern — do not do this in a trigger
declare @inserted_rows table (id    int
                             ,value varchar(max))

insert into @inserted_rows (id
                           ,value)
select order_id
      ,order_number
from inserted

declare @id int
declare cursor_id cursor local static read_only forward_only for
select id
from @inserted_rows

open cursor_id
fetch next from cursor_id into @id

while @@fetch_status = 0
begin
    insert into order_insert_log (order_id
                                 ,log_message)
    values (@id
           ,'order inserted')

    fetch next from cursor_id into @id
end

close cursor_id
deallocate cursor_id
```

```sql
-- Efficient rewrite — set-based, no cursor, references inserted directly
insert into order_insert_log (order_id
                             ,log_message)
select order_id
      ,'order inserted' as log_message
from inserted
```

One statement, no cursor, no variables, no temp table — the entire batch logs in one set-based
operation whether the triggering statement affected 1 row or 10,000. The `local static read_only
forward_only` cursor exception in the General guidelines is for Tasks/Subroutines, not Triggers —
needing a cursor inside a trigger is usually a sign the row-by-row work belongs in a Handler or Task
instead.
