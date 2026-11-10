# Badge

## What it does and when it fires

A Badge shows a number on a subject, task or report — for example the number of open items,
or how many invoices can be generated. It draws the user's attention to a part of the
application. A badge is recalculated automatically on a predefined interval **and** after
every data modification of the subject it belongs to, so it runs often and must be cheap.

---

## Deliverable and object

A Badge becomes a stored procedure named `bdg_<subject_id>`, where the subject is the table,
task or report id it is attached to. The deliverable is only the fragment that populates the
output parameter `@badge_value` — no `create procedure`, no parameter list, no
`set nocount on`.

---

## Fixed variables (provided by the generated proc — do NOT declare them)

| Variable        | Direction | Meaning |
|-----------------|-----------|---------|
| `@variant_id`   | in        | `varchar(128)`; the name of the variant that shows the badge, `NULL` when no variant is involved. |
| `@badge_value`  | **out**   | `int`; the number shown on the badge. `NULL` = no badge is shown. Populating this is the whole purpose of the proc. |
| `@<fk_col>`     | in        | one parameter per lookup/foreign-key column of the subject; these give the context in which the badge is calculated (for example per parent record on a detail tab). |

Take the foreign-key/lookup columns from the pasted `get_sf_metadata` output (the subject's
FK columns / `lookup_refs`); do not invent them.

---

## Hard rules

- **Optimal performance always.** The badge runs on an interval and after every data change,
  so keep it a single cheap query. Avoid cursors, temp tables and heavy joins.
- **Read-only.** Only assign `@badge_value`; never do `insert`/`update`/`delete`.
- **No messages, no transactions** — a badge is a pure calculation.
- **Honour the context parameters.** When a FK parameter is filled, scope the count to it;
  when it is `NULL`, calculate across the board — usually
  `(@<fk> is null or <col> = @<fk>)`.
- **Decide what an empty result means.** `@badge_value = NULL` shows no badge; returning `0`
  shows a `0` bubble. Use `nullif(count(*), 0)` when you do not want a badge on zero.

---

## Core idioms

**1. Simple count** into the output parameter:

```sql
select @badge_value = count(*)
from order_header oh
where oh.order_status = '10'   -- New / awaiting processing (raw db_value from metadata)
```

**2. Suppress the badge when the count is zero:**

```sql
select @badge_value = nullif(count(*), 0)
from order_header oh
where oh.order_status = '10'
```

**3. Context-scoped** — same count, but per parent record when the FK is supplied:

```sql
select @badge_value = nullif(count(*), 0)
from order_header oh
where oh.order_status = '10'
  and (@customer_id is null or oh.customer_id = @customer_id)
```

---

## Worked example

Badge on an "orders to process" subject/task: how many orders still have status New, scoped
to a customer when the badge sits on a customer detail tab and left overall otherwise:

```sql
-- Number of orders still awaiting processing
select @badge_value = nullif(count(*), 0)
from order_header oh
where oh.order_status = '10'   -- New
  and (@customer_id is null or oh.customer_id = @customer_id)
```

---

## Output checklist

- [ ] Only the fragment — no `create procedure`, no parameter declarations.
- [ ] Assigns `@badge_value` and nothing else; read-only, no messages, no transactions.
- [ ] A single cheap query (no cursors/temp/heavy joins) — badges must be fast.
- [ ] Context FK parameters honoured with `(@<fk> is null or <col> = @<fk>)`.
- [ ] Zero handled deliberately (`nullif(count(*), 0)` for no badge on zero).
- [ ] Domain-element values stored as raw `db_value` from the metadata; `@` for SQL Server, `v_` for Oracle/DB2, `p_<id>` for PostgreSQL (`v_` only for locals the template declares).
