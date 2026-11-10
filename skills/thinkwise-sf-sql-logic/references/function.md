# Function

## What it does

A Function is a reusable calculation that returns either a single value (**scalar**) or a
result set (**table-valued**, TVF). It is called from other SQL — a query, a stored
procedure, another function — not directly by the GUI. Scalar functions are used in
`select`, `update` and assignments; table-valued functions are used in the `from` clause,
usually via `cross apply`.

```sql
-- scalar
select dbo.get_tax_rate(c.customer_id) from customer c
set @tax_rate = dbo.get_tax_rate(@customer_id)
-- table-valued
select q.* from customer c cross apply customer_sales_per_quarter(c.customer_id) q
```

---

## Deliverable and object

A Function becomes an actual database **function**, not a stored procedure. Its signature
(name, parameters, return type) is defined as a subroutine in the Software Factory, which
generates the `create function … returns … as` wrapper and the `grant`. The deliverable is
only the **body** woven inside — no `create function`, no `returns`/`with` clause.

---

## Choosing the function type

- **Scalar** — returns one typed value. Fine for a focused calculation, but be careful
  calling one per row in a large query or a view (performance).
- **Inline table-valued** — a single `select`, no `begin/end`. **Preferred**: the optimizer
  inlines it into the calling query, like a parameterized view.
- **Multi-statement table-valued (MSTVF)** — declares and fills a table variable, then
  returns it. More flexible but slower and opaque to the optimizer; use only when a single
  `select` genuinely cannot express the result.

Prefer inline forms for performance (scalar functions can be marked `with inline = on`;
choose an inline TVF over an MSTVF where possible).

---

## Hard rules

- **No DML on tables.** A function reads only — never `insert`, `update` or `delete`.
- **No messages.** A function cannot and must not use `tsf_send_message` or `raiserror`.
- **No cursors and no explicit transactions.**
- **Watch performance in views and per-row use** — a scalar function evaluated for every
  row can be a bottleneck; prefer set-based expressions or an inline TVF.

---

## Function options (set on the subroutine, shown here for context)

- `with inline = on` — treat a scalar function as inline for better plans.
- `with schemabinding` — binds to the objects it depends on (needed for persisted/indexed
  computed columns; blocks changing those objects until the function is altered).
- `with returns null on null input` — returns `null` immediately if any argument is `null`.
- `with execute as` — the security context (`caller`, `self`, `owner`, a specific user).

---

## Core idioms

**1. Scalar — single-expression body.** The whole body is one `return`:

```sql
return (
    select co.tax_rate
    from customer c
         join country co
           on co.country_id = c.country_id
    where c.customer_id = @customer_id
)
```

**2. Scalar — multi-statement body.** Compute into a local variable, then return it:

```sql
declare @tax_rate numeric(3, 2)

select @tax_rate = co.tax_rate
from customer c
     join country co
       on co.country_id = c.country_id
where c.customer_id = @customer_id

return @tax_rate
```

**3. Inline TVF — one select** returned directly (no `begin/end`):

```sql
return (select year(si.invoice_date)                      as year
              ,concat('Q', datepart(qq, si.invoice_date)) as quarter
              ,round(sum(si.amount_incl_vat), 0)          as total_amount
        from sales_invoice si
        where si.customer_id    = @customer_id
          and si.invoice_status = 2   --sent
        group by year(si.invoice_date)
                ,datepart(qq, si.invoice_date)
       )
```

**4. MSTVF — fill the declared result table, then return** (only when a single select will
not do):

```sql
insert @result(year
              ,quarter
              ,total_amount
              )
select year(si.invoice_date)
      ,concat('Q', datepart(qq, si.invoice_date))
      ,round(sum(si.amount_incl_vat), 0)
from sales_invoice si
where si.invoice_status = 2   --sent
  and (si.customer_id = @customer_id or @customer_id is null)
group by year(si.invoice_date)
        ,datepart(qq, si.invoice_date)

return
```

---

## Worked examples

**Scalar** — the tax rate for a customer (single-expression body; the SF generates the
`create function get_tax_rate(@customer_id int) returns numeric(3,2) with inline = on`
wrapper around it):

```sql
return (
    select co.tax_rate
    from customer c
         join country co
           on co.country_id = c.country_id
    where c.customer_id = @customer_id
)
```

**Inline table-valued** — sales per quarter for a customer (idiom 3 above), called with
`cross apply customer_sales_per_quarter(c.customer_id)`.

---

## Dialect note

Bodies above are T-SQL. Oracle and PostgreSQL functions differ in syntax (`v_` parameters on Oracle, `p_<id>` on PostgreSQL,
`return`/`return query`, PL/pgSQL or PL/SQL blocks, different TVF equivalents), so for those
platforms confirm the function form rather than only swapping the `@` prefix.

---

## Output checklist

- [ ] Only the body — no `create function`, no `returns`/`with` clause, no `grant`.
- [ ] Correct form for the type: scalar `return`, inline TVF `return ( select … )`, MSTVF fill-then-`return`.
- [ ] Inline preferred over multi-statement / per-row scalar use for performance.
- [ ] No DML, no cursors, no explicit transactions, no messages.
- [ ] Short `--` comments explain the intent; `@` for SQL Server, `v_` for Oracle/DB2, `p_<id>` for PostgreSQL (`v_` only for locals the template declares).
