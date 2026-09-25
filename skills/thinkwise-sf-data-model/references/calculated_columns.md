# Calculated columns

Loaded on demand from `thinkwise_sf_data_model`.

**Default to a real, physically stored column (`calculated_field_type = none`) and only reach for a
calculated column when the value genuinely cannot be a normal one** — it must always be perfectly
derived from other data that can change independently, with no acceptable point where it could
instead just be set once (an insert/update-time Default control procedure, or plain application
logic). A calculated column is a special-case tool for that narrow situation, not a stylistic
alternative to writing normal columns — most of a table's values belong in real columns, per "One
fact per column" and "Prefer NOT NULL..." above.

`col.calculated_field_type` has four values against real models:

| Value | Meaning | What it actually is |
|---|---|---|
| `none` (0) | Real column | Ordinary, independently writable — the default. |
| `expression` (1) | Cross-row/cross-table formula | `calculated_field_query` is evaluated as a correlated subquery, referencing the current row via alias `t1` (e.g. `t1.project_id`) — free to join or subquery into *other* tables. |
| `calculated_column` (2) | Same-row computed column | `calculated_field_query` is the literal body of a native `AS (<expr>) [PERSISTED]` computed column — may reference only *other columns already on the same row*, no `t1.` prefix, no reaching into other tables. |
| `calculated_column_function` (3) | Function-backed computed column | **Unconfirmed** — no live example found in any model checked. `col.function_input` marks which column(s) feed a shared scalar function as parameters. Verify its actual generated shape in a real model before relying on it, rather than assuming this description is complete. |

**Writing `calculated_field_type` through the staging API**: pass the raw numeric value (`2` for a
same-row `calculated_column`), not the string key — `"calculated_column"` is rejected with
`invalid_input`. Set it together with `calculated_field_query` in the same `stage_resource`/
`patch_resource` call; `col.mand` typically flips to read-only `false` once the type is non-`none`,
which is expected. (Instance of the general enum-key-rejection quirk in
`references/api_write_quirks.md`, but this specific field wasn't called out there.)

**PostgreSQL-specific pitfall**: a `calculated_column`'s expression compiles to a
native generated/persisted column on PostgreSQL, which requires every function used to be
`IMMUTABLE` — `concat` is `STABLE`, not `IMMUTABLE`, and fails with error `42P17`. See
`thinkwise_sf_control_procedures`'s `references/sql_dialects.md`
("PostgreSQL generated/calculated columns require IMMUTABLE functions") for the fix and the
NULL-handling difference between `||` and `concat`. This does **not** apply to `expression`-type
columns below — those are correlated subqueries, not stored generated columns.

**A calculated column still needs `col.dom_id` set, the same as any physical column, verified
live** — even though its value comes from `calculated_field_query` rather than being written
directly, the domain is still mandatory (it's what drives the column's data type/display). This is
easy to miss when a table's other domains are all entity-specific. When a calculated column used as a
table's look-up display column (see "Look-up display column" below — and give it a descriptive
name there, never the generic `lookup`) doesn't map naturally onto any domain you're already
creating for the table, consider one small, genuinely reusable domain for that purpose (a generic
display-label string type) shared across tables' calculated display columns, rather than inventing a
one-off domain per table.

### When to use which

- **`none`** — the default, always, unless one of the below genuinely applies.
- **`calculated_column`** — when the formula only touches other columns already on the same row:
  arithmetic, `concat`, `cast`/`case`, date differences, bitwise flips, hashes. Confirmed live
  examples: `active = ~archived`; `duration_seconds = datediff(second, start_date_time, finish_date_time) PERSISTED`;
  `full_name = concat(first_name, ' ', last_name)` (SQL-Server-shaped; if PostgreSQL is a target
  platform, write this as `coalesce(first_name,'') || ' ' || coalesce(last_name,'')` instead — see
  the PostgreSQL caveat above). Decide `PERSISTED` vs. not based on read/write balance — see
  Performance below.
- **`expression`** — only when the value genuinely needs to reach outside the row: a join/subquery
  to another table, a translation fallback, a session-context-dependent value (current
  language/user). This is the more expensive option (see Performance below), so don't reach for it
  when `calculated_column` would do.
- **`calculated_column_function`** — only for logic complex/reusable enough to justify a shared
  function definition instead of an inline expression, and only after confirming its actual behavior
  live, since no example exists here to model from.

**After generating, verify the specific column's rendered clause, not just the table's overall
status.** A `calculated_column`'s expression is woven directly into the generated `CREATE TABLE`
statement — a table-level "generation successful" result confirms the statement compiled, not that
any one column's `calculated_field_query` rendered the intended expression/`PERSISTED` syntax. Read
the generated DDL back and check that specific column's clause before considering a newly added
calculated column done.

### Writing an `expression` query

The current row is available as `t1` — every confirmed live example correlates back to it. (The
`concat` use below is unaffected by the PostgreSQL IMMUTABLE caveat above — `expression` is a
correlated subquery re-evaluated per query, not a stored generated column.)
```sql
-- translation fallback (table has a *_translated companion)
isnull(
  (select t.name from employee_function_translated t
   where t.appl_lang_id = session_context(N'tsf_appl_lang_id')
     and t.employee_function_id = t1.employee_function_id),
  t1.name)

-- composite identity pulled from other tables
concat(
  (select description from project where project_id = t1.project_id),
  ' | ',
  (select name from sub_project where sub_project_id = t1.sub_project_id))
```
Keep the query to exactly the scalar value needed — one narrow subquery per related fact, not a
sprawling multi-join formula — since it re-runs on every row read, not once.

### Performance: `expression` columns get expensive fast

An `expression` column is a correlated subquery the generated SQL re-runs **for every row returned**,
every time the table — or anything showing it, e.g. a `look_up_display_col_id` — is queried. It is
not indexed and not materialized, and it reads back identically to a real column, so the cost is
invisible.

- Same-row logic → use `calculated_column`, never `expression`: it costs nothing beyond a normal
  column read and can be indexed when `PERSISTED`.
- Mark a `calculated_column` `PERSISTED` when it is read far more often than its sources are written,
  or when it must be filtered/sorted/joined/indexed on. A virtual one is cheaper to write and fine for
  a formula read rarely.
- Keep an `expression` to one scalar with minimal joins, and make sure the column it correlates on in
  the *other* table is indexed — an unindexed correlated subquery is the usual way these go slow as
  data grows.
- Check the execution plan for any `expression` used somewhere high-traffic (a look-up display column,
  a default-visible grid column) before shipping.
- Don't use a calculated column of any kind where a Default control procedure could set the value once
  at write time — recomputing on every read is wasted work when the inputs rarely change.
- For a heavy *cross-row* value (a per-row subquery or lookup) on a large grid, store it in a real
  column maintained by a Handler or Trigger when the source changes (see
  `thinkwise_sf_control_procedures`), instead of an `expression` recomputed on every read.
- Smoke tests validate expression fields and flag ones that are broken or time out. Run them after
  adding or changing one.

