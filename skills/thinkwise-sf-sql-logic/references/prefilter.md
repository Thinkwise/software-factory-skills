# Prefilter

## What it does and when it fires

A Prefilter is a predefined filter the user can toggle on a subject to show only the rows
that meet fixed criteria. It is like a regular filter but takes **no user input** — it either
shows the matching rows or it does not. A prefilter can be active by default (for example
"In progress" on a project screen) and the user can switch between prefilters or turn them
all off to see everything. It is applied the moment it is turned on, and the dataset is
refreshed to reflect it.

---

## Deliverable and object

A Prefilter is **not** a stored procedure. In the Software Factory you define a part of the
`where` clause, and the GUI/Indicium wraps it into the full query. So the deliverable is a
single boolean SQL **expression** — the `where`-clause fragment — with no `create`, no
`select`, no surrounding parentheses needed.

The current table is always addressed through the alias **`t1`**. The GUI turns your fragment
into `select * from <subject> t1 where ( <your fragment> )`, so every reference to a column of
the filtered table must be `t1.<column>`. (Smoke tests check that `t1` is used.)

A prefilter can also be built without code, as column conditions (Column, Filter condition,
Filter value — the **database** value, not the translation). Use that for simple single-column
criteria; write a query fragment when the criterion spans related tables or combines
conditions.

---

## Hard rules

- **Always alias the current table as `t1`.** Reference its columns as `t1.<column>`; other
  tables get their own aliases inside the subqueries you write.
- **A boolean expression only** — something that is valid directly after `where (`. No
  `select`, no `order by`, no trailing semicolon.
- **No user input and no parameters.** A prefilter is fixed criteria; anything the user
  should steer is a regular filter, not a prefilter.
- **Use raw database values** for columns backed by a fixed value list (the `db_value` from
  the metadata), never the translation.
- **Optimize for performance.** Prefer `exists (…)` over joins that can multiply rows, keep
  conditions sargable, and lean on indexed columns — a prefilter runs every time it is
  applied or the data refreshes. A filtered index on the criterion can help.

---

## Core idioms

**1. Single-column criterion** on the current table (raw db_value):

```sql
t1.order_status = '10'   -- New
```

**2. One of several statuses:**

```sql
t1.order_status in ('10', '20')   -- New or In progress
```

**3. Existence over a related (child) table** — the safe way to filter on details:

```sql
exists (select 1
        from order_line ol
        where ol.order_id    = t1.order_id
          and ol.line_status = '30'   --backordered
       )
```

**4. Combine conditions** with `and` / `or` (parenthesise `or` groups):

```sql
t1.order_status = '20'   --in progress
and exists (select 1
            from order_line ol
            where ol.order_id    = t1.order_id
              and ol.line_status = '30'   --backordered
           )
```

---

## Worked example

A prefilter on orders that shows only orders having at least one line still open, expressed
as an existence check so an order appears once regardless of how many open lines it has:

```sql
-- Orders with at least one open line
exists (select 1
        from order_line ol
        where ol.order_id    = t1.order_id
          and ol.line_status = '10'   --open (raw db_value from metadata)
       )
```

---

## Output checklist

- [ ] A single boolean `where`-clause expression — no `select`, no `create`, no `order by`, no semicolon.
- [ ] Current table referenced as `t1.<column>`; related tables aliased inside their own subqueries.
- [ ] Filtering on details done with `exists (…)` rather than row-multiplying joins.
- [ ] No parameters or user input; criteria are fixed.
- [ ] Domain-element values are the raw `db_value` from the metadata, with a `--` note of the meaning.
- [ ] Written to be fast (sargable, indexed columns); `t1` is platform-independent so no `@`/`v_` change applies.
